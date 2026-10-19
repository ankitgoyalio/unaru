package auth

import (
	"context"
	kiteconnect "github.com/zerodha/gokiteconnect/v4"
	"net/http"
	"net/url"
	"time"
)

type Authorization struct{ UserID, AccessToken, DisplayName string }
type Broker interface {
	LoginURL(attempt string) string
	Exchange(context.Context, string) (Authorization, error)
}
type KiteBroker struct{ APIKey, APISecret string }

func (b KiteBroker) client(ctx context.Context) *kiteconnect.Client {
	c := kiteconnect.New(b.APIKey)
	c.SetHTTPClient(&http.Client{Transport: contextTransport{ctx: ctx}})
	return c
}
func (b KiteBroker) LoginURL(attempt string) string {
	u, _ := url.Parse(b.client(context.Background()).GetLoginURL())
	q := u.Query()
	q.Set("redirect_params", url.Values{"attempt": {attempt}}.Encode())
	u.RawQuery = q.Encode()
	return u.String()
}
func (b KiteBroker) Exchange(ctx context.Context, token string) (Authorization, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	data, err := b.client(ctx).GenerateSession(token, b.APISecret)
	if ctx.Err() != nil {
		return Authorization{}, ctx.Err()
	}
	return Authorization{UserID: data.UserID, AccessToken: data.AccessToken, DisplayName: data.UserName}, err
}

// The SDK does not expose context arguments. Attach the operation context at
// its HTTP boundary so cancellation interrupts exchange, checks and revocation.
type contextTransport struct{ ctx context.Context }

func (t contextTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	return http.DefaultTransport.RoundTrip(r.Clone(t.ctx))
}
