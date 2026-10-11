package auth

import (
	"context"
	"errors"
	"net/http"
	"time"
)

var errReconnectSession = errors.New("dashboard session no longer active")

func (s *Server) startReconnect(w http.ResponseWriter, r *http.Request) {
	if !s.protect(r) {
		jsonResponse(w, 403, map[string]string{"error": "invalid_origin"})
		return
	}
	status, err := s.readSession(r)
	if err != nil {
		unavailable(w)
		return
	}
	if status.Kind != "signed_in" {
		jsonResponse(w, 401, map[string]string{"error": "signed_out"})
		return
	}
	cookie, _ := r.Cookie("unaru_session")
	attempt, binding := randomID(), randomID()
	expiry := s.Now().Add(5 * time.Minute)
	result, err := s.Pool.Exec(r.Context(), "INSERT INTO login_attempts(hash,binding_hash,expires_at,session_hash,auth_generation) SELECT $1,$2,$3,s.hash,i.auth_generation FROM dashboard_sessions s CROSS JOIN installation i WHERE s.hash=$4 AND s.revoked_at IS NULL AND s.expires_at>$5", hash(attempt), hash(binding), expiry, hash(cookie.Value), s.Now())
	if err != nil {
		unavailable(w)
		return
	}
	if result.RowsAffected() != 1 {
		jsonResponse(w, 401, map[string]string{"error": "signed_out"})
		return
	}
	s.cookie(w, "unaru_login", binding, expiry)
	jsonResponse(w, 200, map[string]string{"url": s.Broker.LoginURL(attempt)})
}
func (s *Server) validReconnectSession(r *http.Request, sessionHash string) bool {
	cookie, err := r.Cookie("unaru_session")
	if err != nil || hash(cookie.Value) != sessionHash {
		return false
	}
	var active bool
	err = s.Pool.QueryRow(r.Context(), "SELECT EXISTS(SELECT 1 FROM dashboard_sessions WHERE hash=$1 AND revoked_at IS NULL AND expires_at>$2)", sessionHash, s.Now()).Scan(&active)
	return err == nil && active
}
func (s *Server) completeReconnect(ctx context.Context, a Authorization, sessionHash, attemptHash string, now time.Time) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var linked *string
	if err = tx.QueryRow(ctx, "SELECT user_id FROM installation WHERE id=true FOR UPDATE").Scan(&linked); err != nil {
		return err
	}
	if err = s.fenceAuthorization(ctx, tx, a, attemptHash, now); err != nil {
		return err
	}
	var user string
	err = tx.QueryRow(ctx, "SELECT user_id FROM dashboard_sessions WHERE hash=$1 AND revoked_at IS NULL AND expires_at>$2 FOR UPDATE", sessionHash, now).Scan(&user)
	if err != nil {
		return errReconnectSession
	}
	if linked == nil || *linked != a.UserID || user != a.UserID {
		return errIdentity
	}
	err = s.replaceAuthorization(ctx, tx, a, now)
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}
