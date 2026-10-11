package auth

import (
	"context"
	"github.com/jackc/pgx/v5"
	"time"
)

// Call after locking installation. A stale exchange must commit its encrypted
// disposal record rather than restore an authorization after logout.
func (s *Server) fenceAuthorization(ctx context.Context, tx pgx.Tx, a Authorization, attemptHash string, now time.Time) error {
	var current bool
	if err := tx.QueryRow(ctx, "SELECT a.auth_generation=i.auth_generation FROM login_attempts a CROSS JOIN installation i WHERE a.hash=$1", attemptHash).Scan(&current); err != nil {
		return err
	}
	if current {
		return nil
	}
	if _, err := tx.Exec(ctx, "INSERT INTO pending_revocations(id,user_id,encrypted_token,retry_at) VALUES($1,$2,$3,$4)", randomID(), a.UserID, s.encrypt(a.AccessToken, a.UserID), now); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return errStaleAttempt
}

func (s *Server) replaceAuthorization(ctx context.Context, tx pgx.Tx, a Authorization, now time.Time) error {
	_, err := tx.Exec(ctx, "INSERT INTO broker_authorizations(user_id,encrypted_token,status,updated_at,expires_at) VALUES($1,$2,'active',$3,$4) ON CONFLICT(user_id) DO UPDATE SET encrypted_token=EXCLUDED.encrypted_token,status='active',updated_at=EXCLUDED.updated_at,expires_at=EXCLUDED.expires_at", a.UserID, s.encrypt(a.AccessToken, a.UserID), now, brokerExpiry(now))
	return err
}
