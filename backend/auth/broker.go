package auth

import (
	"context"
	kiteconnect "github.com/zerodha/gokiteconnect/v4"
	"net/http"
	"net/url"
	"time"
)

type Authorization struct{ UserID, AccessToken string }
type Broker interface {
	LoginURL(attempt string) string
	Exchange(context.Context, string) (Authorization, error)
}
type KiteBroker struct{ APIKey, APISecret string }

func (b KiteBroker) client() *kiteconnect.Client {
	c := kiteconnect.New(b.APIKey)
	c.SetHTTPClient(&http.Client{Timeout: 15 * time.Second})
	return c
}
func (b KiteBroker) LoginURL(attempt string) string {
	u, _ := url.Parse(b.client().GetLoginURL())
	q := u.Query()
	q.Set("redirect_params", url.Values{"attempt": {attempt}}.Encode())
	u.RawQuery = q.Encode()
	return u.String()
}
func (b KiteBroker) Exchange(ctx context.Context, token string) (Authorization, error) {
	data, err := b.client().GenerateSession(token, b.APISecret)
	return Authorization{UserID: data.UserID, AccessToken: data.AccessToken}, err
}
