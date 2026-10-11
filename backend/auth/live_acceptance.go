package auth

import (
	"context"
	"errors"
	"time"
)

// InvalidateBrokerForAcceptance invalidates only the linked broker token. Dashboard
// sessions and authorization rows remain untouched so the next profile check can
// observe Kite's actual TokenException. It is only exposed by the local CLI.
func (s *Server) InvalidateBrokerForAcceptance(ctx context.Context) error {
	revoker, ok := s.Broker.(interface {
		RevokeAccess(context.Context, string) error
	})
	if !ok {
		return errors.New("broker invalidation unavailable")
	}
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var user string
	var encrypted []byte
	err = tx.QueryRow(ctx, "SELECT b.user_id,b.encrypted_token FROM installation i JOIN broker_authorizations b ON b.user_id=i.user_id WHERE i.id=true AND b.status='active' FOR UPDATE OF i,b").Scan(&user, &encrypted)
	if err != nil {
		return errors.New("no active broker authorization")
	}
	token, err := s.decrypt(encrypted, user)
	if err != nil {
		return errors.New("cannot read broker authorization")
	}
	if err = revoker.RevokeAccess(ctx, token); err != nil && !errors.Is(err, ErrBrokerTokenExpired) {
		return errors.New("broker invalidation failed; retry when Kite is available")
	}
	return tx.Commit(ctx)
}

// VerifyLogoutForAcceptance captures the previous token only in memory, then
// observes a user-driven logout. The caller must supply a bounded context.
func (s *Server) VerifyLogoutForAcceptance(ctx context.Context, captured func()) error {
	checker, ok := s.Broker.(AccessChecker)
	if !ok {
		return errors.New("broker checking unavailable")
	}
	var user string
	var encrypted []byte
	if err := s.Pool.QueryRow(ctx, "SELECT b.user_id,b.encrypted_token FROM installation i JOIN broker_authorizations b ON b.user_id=i.user_id WHERE i.id=true AND b.status='active'").Scan(&user, &encrypted); err != nil {
		return errors.New("active authorization required")
	}
	token, err := s.decrypt(encrypted, user)
	if err != nil {
		return errors.New("cannot read broker authorization")
	}
	rows, err := s.Pool.Query(ctx, "SELECT hash FROM dashboard_sessions WHERE user_id=$1 AND revoked_at IS NULL AND expires_at>$2", user, s.Now())
	if err != nil {
		return errors.New("cannot capture dashboard sessions")
	}
	var sessions []string
	for rows.Next() {
		var session string
		if err = rows.Scan(&session); err != nil {
			rows.Close()
			return errors.New("cannot capture dashboard sessions")
		}
		sessions = append(sessions, session)
	}
	rows.Close()
	if rows.Err() != nil || len(sessions) == 0 {
		return errors.New("active dashboard session required")
	}
	captured()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		var revoked bool
		if err = s.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM dashboard_sessions WHERE hash=ANY($1) AND revoked_at IS NOT NULL)", sessions).Scan(&revoked); err != nil {
			return errors.New("cannot verify dashboard logout")
		}
		if revoked && errors.Is(checker.CheckAccess(ctx, token), ErrBrokerTokenExpired) {
			return nil
		}
		select {
		case <-ctx.Done():
			return errors.New("logout verification timed out")
		case <-ticker.C:
		}
	}
}

// VerifyReconnectForAcceptance invalidates only broker access, then verifies
// token replacement and exact session continuity after user-driven reconnection.
func (s *Server) VerifyReconnectForAcceptance(ctx context.Context, captured func()) error {
	var before []byte
	if err := s.Pool.QueryRow(ctx, "SELECT b.encrypted_token FROM installation i JOIN broker_authorizations b ON b.user_id=i.user_id WHERE i.id=true AND b.status='active'").Scan(&before); err != nil {
		return errors.New("active authorization required")
	}
	var snapshot string
	query := "SELECT COALESCE(jsonb_agg(jsonb_build_array(hash,expires_at) ORDER BY hash),'[]'::jsonb)::text FROM dashboard_sessions WHERE revoked_at IS NULL AND expires_at>$1"
	if err := s.Pool.QueryRow(ctx, query, s.Now()).Scan(&snapshot); err != nil || snapshot == "[]" {
		return errors.New("active dashboard session required")
	}
	if err := s.InvalidateBrokerForAcceptance(ctx); err != nil {
		return err
	}
	captured()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		var replaced bool
		if err := s.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM broker_authorizations WHERE status='active' AND encrypted_token<>$1)", before).Scan(&replaced); err != nil {
			return errors.New("cannot verify broker replacement")
		}
		if replaced {
			var after string
			if err := s.Pool.QueryRow(ctx, query, s.Now()).Scan(&after); err != nil || after != snapshot {
				return errors.New("dashboard session or absolute expiry changed")
			}
			var user string
			var encrypted []byte
			if err := s.Pool.QueryRow(ctx, "SELECT user_id,encrypted_token FROM broker_authorizations WHERE status='active'").Scan(&user, &encrypted); err != nil {
				return errors.New("cannot verify new broker authorization")
			}
			token, err := s.decrypt(encrypted, user)
			if err != nil {
				return errors.New("cannot read broker authorization")
			}
			checker, ok := s.Broker.(AccessChecker)
			if !ok || checker.CheckAccess(ctx, token) != nil {
				return errors.New("new broker authorization not confirmed")
			}
			return nil
		}
		select {
		case <-ctx.Done():
			return errors.New("reconnection verification timed out")
		case <-ticker.C:
		}
	}
}
