package auth

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	_ "embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"time"
)

//go:embed migrations.sql
var migrations string

func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, "SELECT pg_advisory_xact_lock(7634821)"); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, migrations); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

type Server struct {
	Config Config
	Pool   *pgxpool.Pool
	Broker Broker
	Now    func() time.Time
	cipher cipher.AEAD
}
type SessionStatus struct {
	Kind       string    `json:"kind"`
	UserID     string    `json:"userId,omitempty"`
	Connection string    `json:"connection,omitempty"`
	ExpiresAt  time.Time `json:"expiresAt,omitempty"`
}

func NewServer(config Config, pool *pgxpool.Pool, broker Broker, now func() time.Time) (*Server, error) {
	if err := validateConfig(&config); err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(config.EncryptionKey)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if now == nil {
		now = time.Now
	}
	return &Server{Config: config, Pool: pool, Broker: broker, Now: now, cipher: aead}, nil
}
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/auth/login", s.startLogin)
	mux.HandleFunc("POST /api/auth/reconnect", s.startReconnect)
	mux.HandleFunc("GET /api/auth/callback", s.callback)
	mux.HandleFunc("GET /api/session", s.session)
	mux.HandleFunc("POST /api/auth/logout", s.logout)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		mux.ServeHTTP(w, r.WithContext(ctx))
	})
}
func randomID() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}
func hash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}
func (s *Server) cookie(w http.ResponseWriter, name, value string, expires time.Time) {
	http.SetCookie(w, &http.Cookie{Name: name, Value: value, Path: "/", HttpOnly: true, Secure: s.Config.SecureCookies, SameSite: http.SameSiteLaxMode, Expires: expires, MaxAge: int(expires.Sub(s.Now()).Seconds())})
}
func (s *Server) protect(r *http.Request) bool { return r.Header.Get("Origin") == s.Config.AppOrigin }
func jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
func unavailable(w http.ResponseWriter) {
	jsonResponse(w, 503, map[string]string{"error": "service_unavailable"})
}
func (s *Server) startLogin(w http.ResponseWriter, r *http.Request) {
	if !s.protect(r) {
		jsonResponse(w, 403, map[string]string{"error": "invalid_origin"})
		return
	}
	attempt, binding := randomID(), randomID()
	expiry := s.Now().Add(5 * time.Minute)
	_, err := s.Pool.Exec(r.Context(), "INSERT INTO login_attempts(hash,binding_hash,expires_at,auth_generation) SELECT $1,$2,$3,auth_generation FROM installation WHERE id=true", hash(attempt), hash(binding), expiry)
	if err != nil {
		unavailable(w)
		return
	}
	s.cookie(w, "unaru_login", binding, expiry)
	jsonResponse(w, 200, map[string]string{"url": s.Broker.LoginURL(attempt)})
}
func (s *Server) fail(w http.ResponseWriter, r *http.Request, code string) {
	http.Redirect(w, r, s.Config.AppOrigin+"/?error="+code, http.StatusSeeOther)
}
func (s *Server) callback(w http.ResponseWriter, r *http.Request) {
	attempt := r.URL.Query().Get("attempt")
	binding, err := r.Cookie("unaru_login")
	if err != nil || attempt == "" {
		s.fail(w, r, "invalid_attempt")
		return
	}
	var expected string
	var reconnectSession *string
	err = s.Pool.QueryRow(r.Context(), "SELECT a.binding_hash,a.session_hash FROM login_attempts a CROSS JOIN installation i WHERE a.hash=$1 AND a.consumed_at IS NULL AND a.expires_at>$2 AND a.auth_generation=i.auth_generation", hash(attempt), s.Now()).Scan(&expected, &reconnectSession)
	if err != nil || subtle.ConstantTimeCompare([]byte(expected), []byte(hash(binding.Value))) != 1 {
		s.fail(w, r, "invalid_attempt")
		return
	}
	result, err := s.Pool.Exec(r.Context(), "UPDATE login_attempts SET consumed_at=$2 WHERE hash=$1 AND consumed_at IS NULL AND expires_at>$2", hash(attempt), s.Now())
	if err != nil || result.RowsAffected() != 1 {
		s.fail(w, r, "invalid_attempt")
		return
	}
	http.SetCookie(w, &http.Cookie{Name: "unaru_login", Path: "/", HttpOnly: true, Secure: s.Config.SecureCookies, SameSite: http.SameSiteLaxMode, MaxAge: -1})
	if reconnectSession != nil && !s.validReconnectSession(r, *reconnectSession) {
		s.fail(w, r, "invalid_attempt")
		return
	}
	token := r.URL.Query().Get("request_token")
	if token == "" || r.URL.Query().Get("status") != "success" {
		s.fail(w, r, "cancelled")
		return
	}
	authorization, err := s.Broker.Exchange(r.Context(), token)
	if err != nil || authorization.UserID == "" || authorization.AccessToken == "" {
		s.fail(w, r, "exchange_failed")
		return
	}
	if reconnectSession != nil {
		err = s.completeReconnect(r.Context(), authorization, *reconnectSession, hash(attempt), s.Now())
		if errors.Is(err, errIdentity) {
			s.fail(w, r, "account_mismatch")
			return
		}
		if errors.Is(err, errReconnectSession) || errors.Is(err, errStaleAttempt) {
			s.fail(w, r, "invalid_attempt")
			return
		}
		if err != nil {
			s.fail(w, r, "service_unavailable")
			return
		}
		http.Redirect(w, r, s.Config.AppOrigin+"/dashboard", http.StatusSeeOther)
		return
	}
	sessionID := randomID()
	now := s.Now()
	err = s.completeLogin(r.Context(), authorization, hash(sessionID), hash(attempt), now)
	if errors.Is(err, errStaleAttempt) {
		s.fail(w, r, "invalid_attempt")
		return
	}
	if errors.Is(err, errIdentity) {
		s.fail(w, r, "account_mismatch")
		return
	}
	if err != nil {
		s.fail(w, r, "service_unavailable")
		return
	}
	s.cookie(w, "unaru_session", sessionID, now.Add(30*24*time.Hour))
	http.Redirect(w, r, s.Config.AppOrigin+"/dashboard", http.StatusSeeOther)
}

var errStaleAttempt = errors.New("attempt superseded by logout")
var errIdentity = errors.New("different linked account")

func (s *Server) encrypt(token, userID string) []byte {
	nonce := make([]byte, s.cipher.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		panic(err)
	}
	return s.cipher.Seal(nonce, nonce, []byte(token), []byte(userID))
}
func (s *Server) completeLogin(ctx context.Context, a Authorization, sessionHash, attemptHash string, now time.Time) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var linked *string
	if err = tx.QueryRow(ctx, "SELECT user_id FROM installation WHERE id=true FOR UPDATE").Scan(&linked); err != nil {
		return err
	}
	var current bool
	if err = tx.QueryRow(ctx, "SELECT a.auth_generation=i.auth_generation FROM login_attempts a CROSS JOIN installation i WHERE a.hash=$1", attemptHash).Scan(&current); err != nil {
		return err
	}
	if !current {
		// A callback may finish its provider exchange after logout has won.
		// Keep that token only in the encrypted disposal queue.
		if _, err = tx.Exec(ctx, "INSERT INTO pending_revocations(id,user_id,encrypted_token,retry_at) VALUES($1,$2,$3,$4)", randomID(), a.UserID, s.encrypt(a.AccessToken, a.UserID), now); err != nil {
			return err
		}
		if err = tx.Commit(ctx); err != nil {
			return err
		}
		return errStaleAttempt
	}
	if linked != nil && *linked != a.UserID {
		return errIdentity
	}
	if _, err = tx.Exec(ctx, "UPDATE installation SET user_id=$1 WHERE id=true", a.UserID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, "INSERT INTO dashboard_sessions(hash,user_id,created_at,expires_at) VALUES($1,$2,$3,$4)", sessionHash, a.UserID, now, now.Add(30*24*time.Hour)); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, "INSERT INTO broker_authorizations(user_id,encrypted_token,status,updated_at,expires_at) VALUES($1,$2,'active',$3,$4) ON CONFLICT(user_id) DO UPDATE SET encrypted_token=EXCLUDED.encrypted_token,status='active',updated_at=EXCLUDED.updated_at,expires_at=EXCLUDED.expires_at", a.UserID, s.encrypt(a.AccessToken, a.UserID), now, brokerExpiry(now)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func brokerExpiry(now time.Time) time.Time {
	india := time.FixedZone("Asia/Kolkata", 19800)
	local := now.In(india)
	return time.Date(local.Year(), local.Month(), local.Day()+1, 6, 0, 0, 0, india)
}
func (s *Server) readSession(r *http.Request) (SessionStatus, error) {
	cookie, err := r.Cookie("unaru_session")
	if err != nil {
		return SessionStatus{Kind: "signed_out"}, nil
	}
	var status SessionStatus
	var brokerStatus string
	err = s.Pool.QueryRow(r.Context(), "SELECT s.user_id,s.expires_at,COALESCE(b.status,'reconnect_required') FROM dashboard_sessions s LEFT JOIN broker_authorizations b ON b.user_id=s.user_id WHERE s.hash=$1 AND s.revoked_at IS NULL AND s.expires_at>$2", hash(cookie.Value), s.Now()).Scan(&status.UserID, &status.ExpiresAt, &brokerStatus)
	if errors.Is(err, pgx.ErrNoRows) {
		return SessionStatus{Kind: "signed_out"}, nil
	}
	if err != nil {
		return SessionStatus{}, err
	}
	status.Kind = "signed_in"
	status.Connection = brokerStatus
	return s.checkBrokerStatus(r, status)
}
func (s *Server) session(w http.ResponseWriter, r *http.Request) {
	status, err := s.readSession(r)
	if err != nil {
		unavailable(w)
		return
	}
	jsonResponse(w, 200, status)
}
