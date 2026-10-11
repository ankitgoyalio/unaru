package auth

import (
	"context"
	"errors"
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
