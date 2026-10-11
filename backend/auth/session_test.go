package auth_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestSessionSurvivesBackendRestartAndExpiresAbsolutely(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to isolated Postgres")
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer admin.Close()
	schema := fmt.Sprintf("session_test_%d", time.Now().UnixNano())
	if _, err = admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		t.Fatal(err)
	}
	defer admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE")
	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	config.ConnConfig.RuntimeParams["search_path"] = schema
	config.ConnConfig.RuntimeParams["application_name"] = schema
	var offline atomic.Bool
	config.ConnConfig.DialFunc = func(ctx context.Context, network, addr string) (net.Conn, error) {
		if offline.Load() {
			<-ctx.Done()
			return nil, ctx.Err()
		}
		return (&net.Dialer{}).DialContext(ctx, network, addr)
	}
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	if err = auth.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC)
	initial := now
	cfg := auth.Config{AppOrigin: "http://localhost:5173", CallbackURL: "http://localhost:5173/api/auth/callback", EncryptionKey: make([]byte, 32)}
	newHTTP := func(pool *pgxpool.Pool) *httptest.Server {
		s, err := auth.NewServer(cfg, pool, &fakeBroker{user: "OWNER1"}, func() time.Time { return now })
		if err != nil {
			t.Fatal(err)
		}
		return httptest.NewServer(s.Handler())
	}
	server := newHTTP(pool)
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	login := func() *http.Cookie {
		req, _ := http.NewRequest("POST", server.URL+"/api/auth/login", nil)
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
		req, _ = http.NewRequest("GET", server.URL+"/api/auth/callback?attempt="+q.Get("attempt")+"&request_token=success&status=success", nil)
		req.AddCookie(res.Cookies()[0])
		res, err = client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		for _, c := range res.Cookies() {
			if c.Name == "unaru_session" {
				return c
			}
		}
		t.Fatal("login did not issue session cookie")
		return nil
	}
	cookie := login()
	if !cookie.Expires.Equal(initial.Add(30*24*time.Hour)) || cookie.MaxAge != 2592000 {
		t.Fatal("cookie did not persist to absolute expiry")
	}
	check := func(c *http.Cookie, want string, expiry time.Time) {
		req, _ := http.NewRequest("GET", server.URL+"/api/session", nil)
		if c != nil {
			req.AddCookie(c)
		}
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var got auth.SessionStatus
		if err = json.NewDecoder(res.Body).Decode(&got); err != nil {
			t.Fatal(err)
		}
		if res.StatusCode != 200 || got.Kind != want {
			t.Fatalf("status %d: %+v", res.StatusCode, got)
		}
		if want == "signed_in" && (got.UserID != "OWNER1" || !got.ExpiresAt.Equal(expiry)) {
			t.Fatalf("identity or expiry changed: %+v", got)
		}
		if len(res.Cookies()) != 0 {
			t.Fatal("status request rewrote persistent cookie")
		}
	}
	check(nil, "signed_out", time.Time{})
	check(&http.Cookie{Name: "unaru_session", Value: "invalid"}, "signed_out", time.Time{})
	server.Close()
	pool.Close()
	pool, err = pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	server = newHTTP(pool)
	defer server.Close()
	// Simulate Neon dropping idle connections and being unreachable on wakeup.
	pool.Reset()
	offline.Store(true)
	outageClient := &http.Client{Timeout: 7 * time.Second}
	req, _ := http.NewRequest("GET", server.URL+"/api/session", nil)
	req.AddCookie(cookie)
	began := time.Now()
	res, err := outageClient.Do(req)
	if err != nil {
		t.Fatalf("database outage was not bounded: %v", err)
	}
	res.Body.Close()
	if res.StatusCode != 503 || time.Since(began) > 5*time.Second {
		t.Fatalf("outage response %d took %s", res.StatusCode, time.Since(began))
	}
	if len(res.Cookies()) != 0 {
		t.Fatal("outage destroyed persistent cookie")
	}
	offline.Store(false)
	check(cookie, "signed_in", initial.Add(30*24*time.Hour))
	// Neon suspension can leave a previously acquired connection stale.
	if _, err = admin.Exec(ctx, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name=$1", schema); err != nil {
		t.Fatal(err)
	}
	check(cookie, "signed_in", initial.Add(30*24*time.Hour))
	now = initial.Add(29 * 24 * time.Hour)
	check(cookie, "signed_in", initial.Add(30*24*time.Hour))
	now = initial.Add(30*24*time.Hour - time.Microsecond)
	check(cookie, "signed_in", initial.Add(30*24*time.Hour))
	now = initial.Add(30 * 24 * time.Hour)
	check(cookie, "signed_out", time.Time{})
	cookie = login()
	check(cookie, "signed_in", now.Add(30*24*time.Hour))
}
