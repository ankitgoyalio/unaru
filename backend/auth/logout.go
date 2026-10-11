package auth

import (
	"errors"
	"github.com/jackc/pgx/v5"
	"net/http"
)

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if !s.protect(r) {
		jsonResponse(w, 403, map[string]string{"error": "invalid_origin"})
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		unavailable(w)
		return
	}
	defer tx.Rollback(r.Context())
	if _, err = tx.Exec(r.Context(), "SELECT user_id FROM installation WHERE id=true FOR UPDATE"); err != nil {
		unavailable(w)
		return
	}
	cookie, cookieErr := r.Cookie("unaru_session")
	var user string
	if cookieErr == nil {
		err = tx.QueryRow(r.Context(), "UPDATE dashboard_sessions SET revoked_at=$2 WHERE hash=$1 AND revoked_at IS NULL RETURNING user_id", hash(cookie.Value), s.Now()).Scan(&user)
	} else {
		err = pgx.ErrNoRows
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		unavailable(w)
		return
	}
	if user != "" {
		if _, err = tx.Exec(r.Context(), "INSERT INTO pending_revocations(id,user_id,encrypted_token,retry_at) SELECT $1,user_id,encrypted_token,$2 FROM broker_authorizations WHERE user_id=$3", randomID(), s.Now(), user); err != nil {
			unavailable(w)
			return
		}
		if _, err = tx.Exec(r.Context(), "DELETE FROM broker_authorizations WHERE user_id=$1", user); err != nil {
			unavailable(w)
			return
		}
	}
	// Fence attempts that are waiting for a callback or currently exchanging a token.
	if _, err = tx.Exec(r.Context(), "UPDATE installation SET auth_generation=auth_generation+1 WHERE id=true"); err != nil {
		unavailable(w)
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		unavailable(w)
		return
	}
	for _, name := range []string{"unaru_session", "unaru_login"} {
		http.SetCookie(w, &http.Cookie{Name: name, Path: "/", HttpOnly: true, Secure: s.Config.SecureCookies, SameSite: http.SameSiteLaxMode, MaxAge: -1})
	}
	// Broker disposal is handled by the durable worker, independently of this response.
	w.WriteHeader(http.StatusNoContent)
}
