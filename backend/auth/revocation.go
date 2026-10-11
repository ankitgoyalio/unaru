package auth

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	kiteconnect "github.com/zerodha/gokiteconnect/v4"
)

type TokenRevoker interface {
	RevokeAccess(context.Context, string) error
}

func (b KiteBroker) RevokeAccess(ctx context.Context, token string) error {
	c := b.client()
	c.SetAccessToken(token)
	_, err := c.InvalidateAccessToken()
	return err
}
func tokenAlreadyInvalid(err error) bool {
	var provider kiteconnect.Error
	return errors.As(err, &provider) && provider.ErrorType == "TokenException"
}

// RetryRevocations drains due work. Row locks prevent concurrent workers from
// revoking the same token; a crash releases its lock and leaves the queue durable.
func (s *Server) RetryRevocations(ctx context.Context) error {
	revoker, ok := s.Broker.(TokenRevoker)
	if !ok {
		return errors.New("broker revocation unavailable")
	}
	for count := 0; count < 20; count++ {
		tx, err := s.Pool.Begin(ctx)
		if err != nil {
			return err
		}
		var id, user string
		var encrypted []byte
		var failures int
		err = tx.QueryRow(ctx, "SELECT id,user_id,encrypted_token,failures FROM pending_revocations WHERE retry_at<=$1 ORDER BY retry_at FOR UPDATE SKIP LOCKED LIMIT 1", s.Now()).Scan(&id, &user, &encrypted, &failures)
		if errors.Is(err, pgx.ErrNoRows) {
			tx.Rollback(ctx)
			return nil
		}
		if err != nil {
			tx.Rollback(ctx)
			return err
		}
		var token []byte
		if len(encrypted) < s.cipher.NonceSize() {
			err = errors.New("invalid encrypted token")
		} else {
			token, err = s.cipher.Open(nil, encrypted[:s.cipher.NonceSize()], encrypted[s.cipher.NonceSize():], []byte(user))
		}
		if err == nil {
			err = revoker.RevokeAccess(ctx, string(token))
		}
		if err == nil || tokenAlreadyInvalid(err) {
			_, err = tx.Exec(ctx, "DELETE FROM pending_revocations WHERE id=$1", id)
		} else {
			delay := time.Second * 30
			for i := 0; i < failures && delay < time.Hour; i++ {
				delay *= 2
			}
			if delay > time.Hour {
				delay = time.Hour
			}
			_, err = tx.Exec(ctx, "UPDATE pending_revocations SET failures=LEAST(failures+1,100),retry_at=$2 WHERE id=$1", id, s.Now().Add(delay))
		}
		if err != nil {
			tx.Rollback(ctx)
			return err
		}
		if err = tx.Commit(ctx); err != nil {
			return err
		}
	}
	return nil
}

// RunRevocations resumes persisted work at startup and then checks once per minute.
func (s *Server) RunRevocations(ctx context.Context) {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		s.RetryRevocations(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
