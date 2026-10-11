package auth

import (
	"context"
	"errors"
	kiteconnect "github.com/zerodha/gokiteconnect/v4"
	"net/http"
	"time"
)

var ErrBrokerTokenExpired = errors.New("broker authorization expired")

type AccessChecker interface {
	CheckAccess(context.Context, string) error
}

// CheckAccess confirms token invalidation by exception type, never by HTTP status alone.
func (b KiteBroker) CheckAccess(ctx context.Context, token string) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	c := b.client(ctx)
	c.SetAccessToken(token)
	_, err := c.GetUserProfile()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	var brokerError kiteconnect.Error
	if errors.As(err, &brokerError) && brokerError.ErrorType == kiteconnect.TokenError {
		return ErrBrokerTokenExpired
	}
	return err
}

func (s *Server) decrypt(token []byte, user string) (string, error) {
	n := s.cipher.NonceSize()
	if len(token) < n {
		return "", errors.New("invalid encrypted authorization")
	}
	plain, err := s.cipher.Open(nil, token[:n], token[n:], []byte(user))
	return string(plain), err
}

func (s *Server) checkBrokerStatus(r *http.Request, status SessionStatus) (SessionStatus, error) {
	if status.Connection != "active" {
		return status, nil
	}
	checker, ok := s.Broker.(AccessChecker)
	if !ok {
		return status, nil
	}
	var encrypted []byte
	err := s.Pool.QueryRow(r.Context(), "SELECT encrypted_token FROM broker_authorizations WHERE user_id=$1 AND status='active'", status.UserID).Scan(&encrypted)
	if err != nil {
		return SessionStatus{}, err
	}
	token, err := s.decrypt(encrypted, status.UserID)
	if err != nil {
		return SessionStatus{}, err
	}
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	checkErr := checker.CheckAccess(ctx, token)
	if checkErr != nil && !errors.Is(checkErr, ErrBrokerTokenExpired) {
		status.Connection = "temporarily_unavailable"
		return status, nil
	}
	if errors.Is(checkErr, ErrBrokerTokenExpired) {
		result, err := s.Pool.Exec(r.Context(), "UPDATE broker_authorizations SET status='reconnect_required',updated_at=$3 WHERE user_id=$1 AND encrypted_token=$2 AND status='active'", status.UserID, encrypted, s.Now())
		if err != nil {
			return SessionStatus{}, err
		}
		if result.RowsAffected() == 1 {
			status.Connection = "reconnect_required"
		}
	}
	return status, nil
}
