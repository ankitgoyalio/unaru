package auth_test

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"sync/atomic"
	"testing"
	"time"
)

type acceptanceBroker struct {
	fakeBroker
	invalid atomic.Bool
}

func (b *acceptanceBroker) Exchange(ctx context.Context, token string) (auth.Authorization, error) {
	b.invalid.Store(false)
	return b.fakeBroker.Exchange(ctx, token)
}
func (b *acceptanceBroker) RevokeAccess(context.Context, string) error {
	b.invalid.Store(true)
	return nil
}
func (b *acceptanceBroker) CheckAccess(context.Context, string) error {
	if b.invalid.Load() {
		return auth.ErrBrokerTokenExpired
	}
	return nil
}
func TestAcceptanceObservesHTTPLogout(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL")
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer admin.Close()
	schema := fmt.Sprintf("acceptance_%d", time.Now().UnixNano())
	if _, err = admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		t.Fatal(err)
	}
	defer admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE")
	pc, _ := pgxpool.ParseConfig(dsn)
	pc.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(ctx, pc)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	if err = auth.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	b := &acceptanceBroker{fakeBroker: fakeBroker{user: "OWNER"}}
	cfg := auth.Config{AppOrigin: "http://localhost:5173", CallbackURL: "http://localhost:5173/api/auth/callback", EncryptionKey: make([]byte, 32)}
	server, err := auth.NewServer(cfg, pool, b, nil)
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(server.Handler())
	defer ts.Close()
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, _ := http.NewRequest("POST", ts.URL+"/api/auth/login", nil)
	req.Header.Set("Origin", cfg.AppOrigin)
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var start struct{ URL string }
	json.NewDecoder(res.Body).Decode(&start)
	res.Body.Close()
	u, _ := url.Parse(start.URL)
	q, _ := url.ParseQuery(u.Query().Get("redirect_params"))
	res, err = client.Get(ts.URL + "/api/auth/callback?attempt=" + q.Get("attempt") + "&request_token=success&status=success")
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	// Provider invalidation alone must not be reported as dashboard logout.
	short, stop := context.WithTimeout(ctx, 25*time.Millisecond)
	if err = server.VerifyLogoutForAcceptance(short, func() { b.invalid.Store(true) }); err == nil {
		t.Fatal("provider invalidation incorrectly proved logout")
	}
	stop()
	b.invalid.Store(false)
	reconnectCtx, stopReconnect := context.WithTimeout(ctx, 2*time.Second)
	err = server.VerifyReconnectForAcceptance(reconnectCtx, func() {
		req, _ := http.NewRequest("POST", ts.URL+"/api/auth/reconnect", nil)
		req.Header.Set("Origin", cfg.AppOrigin)
		res, err := client.Do(req)
		if err != nil {
			t.Error(err)
			return
		}
		var next struct{ URL string }
		json.NewDecoder(res.Body).Decode(&next)
		res.Body.Close()
		u, _ := url.Parse(next.URL)
		q, _ := url.ParseQuery(u.Query().Get("redirect_params"))
		res, err = client.Get(ts.URL + "/api/auth/callback?attempt=" + q.Get("attempt") + "&request_token=success&status=success")
		if err != nil {
			t.Error(err)
			return
		}
		res.Body.Close()
	})
	stopReconnect()
	if err != nil {
		t.Fatal(err)
	}
	timeout, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err = server.VerifyLogoutForAcceptance(timeout, func() {
		req, _ := http.NewRequest("POST", ts.URL+"/api/auth/logout", nil)
		req.Header.Set("Origin", cfg.AppOrigin)
		res, err := client.Do(req)
		if err != nil {
			t.Error(err)
			return
		}
		res.Body.Close()
		if res.StatusCode != 204 {
			t.Errorf("logout %d", res.StatusCode)
		}
	}); err != nil {
		t.Fatal(err)
	}
	res, err = client.Get(ts.URL + "/api/session")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var status auth.SessionStatus
	json.NewDecoder(res.Body).Decode(&status)
	if status.Kind != "signed_out" {
		t.Fatal("logout helper granted access")
	}
}
