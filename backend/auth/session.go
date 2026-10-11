package auth

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"net/http"
	"time"
)

// A session read is safe to retry. pgxpool discards broken connections and
// acquires a replacement; the deadline bounds database wakeup and outages.
func (s *Server) readSession(r *http.Request) (SessionStatus, error) {
	cookie, err := r.Cookie("unaru_session")
	if err != nil {
		return SessionStatus{Kind: "signed_out"}, nil
	}
	var status SessionStatus
	var brokerStatus string
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	read := func() error {
		return s.Pool.QueryRow(ctx, "SELECT s.user_id,s.expires_at,COALESCE(b.status,'reconnect_required') FROM dashboard_sessions s LEFT JOIN broker_authorizations b ON b.user_id=s.user_id WHERE s.hash=$1 AND s.revoked_at IS NULL AND s.expires_at>$2", hash(cookie.Value), s.Now()).Scan(&status.UserID, &status.ExpiresAt, &brokerStatus)
	}
	err = read()
	var databaseError *pgconn.PgError
	stale := errors.As(err, &databaseError) && (databaseError.Code == "57P01" || databaseError.Code == "57P02" || databaseError.Code == "57P03")
	if (pgconn.SafeToRetry(err) || stale) && ctx.Err() == nil {
		err = read()
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return SessionStatus{Kind: "signed_out"}, nil
	}
	if err != nil {
		return SessionStatus{}, err
	}
	status.Kind = "signed_in"
	status.Connection = brokerStatus
	return status, nil
}
