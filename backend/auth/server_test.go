package auth_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
)

type fakeBroker struct {
	user      string
	exchanges int
}

func (b *fakeBroker) LoginURL(attempt string) string {
	return "https://broker.invalid/login?redirect_params=" + url.QueryEscape("attempt="+attempt)
}
func (b *fakeBroker) Exchange(ctx context.Context, token string) (auth.Authorization, error) {
	b.exchanges++
	if token == "fail" {
		return auth.Authorization{}, errors.New("provider-token secret-access-token provider error")
	}
	return auth.Authorization{UserID: b.user, AccessToken: "secret-access-token"}, nil
}
func TestFirstLogin(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to isolated Postgres")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	schema := fmt.Sprintf("http_test_%d", time.Now().UnixNano())
	_, err = pool.Exec(context.Background(), "CREATE SCHEMA "+schema)
	defer pool.Exec(context.Background(), "DROP SCHEMA "+schema+" CASCADE")
	config, parseErr := pgxpool.ParseConfig(dsn)
	if parseErr != nil {
		t.Fatal(parseErr)
	}
	config.ConnConfig.RuntimeParams["search_path"] = schema
	scoped, scopedErr := pgxpool.NewWithConfig(context.Background(), config)
	if scopedErr != nil {
		t.Fatal(scopedErr)
	}
	defer scoped.Close()
	pool = scoped
	if err != nil {
		t.Fatal(err)
	}
	if err = auth.Migrate(context.Background(), pool); err != nil {
		t.Fatal(err)
	}
	broker := &fakeBroker{user: "OWNER1"}
	now := time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC)
	cfg := auth.Config{AppOrigin: "http://localhost:5173", CallbackURL: "http://localhost:5173/api/auth/callback", EncryptionKey: make([]byte, 32)}
	srv, err := auth.NewServer(cfg, pool, broker, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(srv.Handler())
	defer ts.Close()
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar, CheckRedirect: func(r *http.Request, v []*http.Request) error { return http.ErrUseLastResponse }}
	req, _ := http.NewRequest("POST", ts.URL+"/api/auth/login", nil)
	req.Header.Set("Origin", cfg.AppOrigin)
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var start struct {
		URL string `json:"url"`
	}
	json.NewDecoder(res.Body).Decode(&start)
	res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("start status %d", res.StatusCode)
	}
	u, _ := url.Parse(start.URL)
	q, _ := url.ParseQuery(u.Query().Get("redirect_params"))
	callback := ts.URL + "/api/auth/callback?attempt=" + q.Get("attempt") + "&request_token=provider-token&status=success"
	res, err = client.Get(callback)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	var sessionCookie *http.Cookie
	for _, cookie := range res.Cookies() {
		if cookie.Name == "unaru_session" {
			sessionCookie = cookie
		}
	}
	if sessionCookie == nil || !sessionCookie.HttpOnly || sessionCookie.Secure || sessionCookie.SameSite != http.SameSiteLaxMode || sessionCookie.MaxAge != 2592000 {
		t.Fatalf("invalid development cookie %+v", sessionCookie)
	}
	if res.StatusCode != 303 || res.Header.Get("Location") != cfg.AppOrigin+"/dashboard" {
		t.Fatalf("callback %d %s", res.StatusCode, res.Header.Get("Location"))
	}
	res, _ = client.Get(ts.URL + "/api/session")
	var status auth.SessionStatus
	json.NewDecoder(res.Body).Decode(&status)
	res.Body.Close()
	if status.Kind != "signed_in" || status.UserID != "OWNER1" || status.Connection != "active" {
		t.Fatalf("status %+v", status)
	}
	for _, c := range jar.Cookies(mustURL(ts.URL)) {
		if strings.Contains(c.Value, "secret") {
			t.Fatal("secret cookie")
		}
	}
	res, _ = client.Get(callback)
	res.Body.Close()
	if !strings.Contains(res.Header.Get("Location"), "error=invalid_attempt") || broker.exchanges != 1 {
		t.Fatal("replay exchanged")
	}
	broker.user = "OTHER"
	req, _ = http.NewRequest("POST", ts.URL+"/api/auth/login", nil)
	req.Header.Set("Origin", cfg.AppOrigin)
	res, _ = client.Do(req)
	json.NewDecoder(res.Body).Decode(&start)
	res.Body.Close()
	u, _ = url.Parse(start.URL)
	q, _ = url.ParseQuery(u.Query().Get("redirect_params"))
	res, _ = client.Get(ts.URL + "/api/auth/callback?attempt=" + q.Get("attempt") + "&request_token=other&status=success")
	res.Body.Close()
	if !strings.Contains(res.Header.Get("Location"), "error=account_mismatch") {
		t.Fatal("different identity accepted")
	}
	// Rejected callback paths never establish an additional session or exchange.
	for _, tc := range []struct {
		name, token   string
		bind, expired bool
		want          string
	}{
		{"missing token", "", true, false, "cancelled"},
		{"provider failure", "fail", true, false, "exchange_failed"},
		{"missing browser binding", "success", false, false, "invalid_attempt"},
		{"expired attempt", "success", true, true, "invalid_attempt"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req, _ := http.NewRequest("POST", ts.URL+"/api/auth/login", nil)
			req.Header.Set("Origin", cfg.AppOrigin)
			res, _ := client.Do(req)
			json.NewDecoder(res.Body).Decode(&start)
			res.Body.Close()
			u, _ := url.Parse(start.URL)
			q, _ := url.ParseQuery(u.Query().Get("redirect_params"))
			callbackClient := client
			if !tc.bind {
				callbackClient = &http.Client{CheckRedirect: client.CheckRedirect}
			}
			if tc.expired {
				now = now.Add(5 * time.Minute)
			}
			res, _ = callbackClient.Get(ts.URL + "/api/auth/callback?attempt=" + q.Get("attempt") + "&request_token=" + tc.token + "&status=success")
			res.Body.Close()
			if !strings.Contains(res.Header.Get("Location"), "error="+tc.want) {
				t.Fatalf("unexpected failure %s", res.Header.Get("Location"))
			}
		})
	}
	req, _ = http.NewRequest("POST", ts.URL+"/api/auth/login", nil)
	req.Header.Set("Origin", "https://attacker.invalid")
	res, _ = client.Do(req)
	res.Body.Close()
	if res.StatusCode != 403 {
		t.Fatal("cross-origin login accepted")
	}
	res, _ = client.Get(ts.URL + "/api/auth/callback?attempt=unsolicited&request_token=secret&status=success")
	res.Body.Close()
	if !strings.Contains(res.Header.Get("Location"), "error=invalid_attempt") {
		t.Fatal("unsolicited callback accepted")
	}
	res, _ = client.Get(ts.URL + "/api/session")
	json.NewDecoder(res.Body).Decode(&status)
	res.Body.Close()
	if status.UserID != "OWNER1" || status.Connection != "active" {
		t.Fatal("rejected callback corrupted authorization")
	}
	now = now.Add(30 * 24 * time.Hour)
	res, _ = client.Get(ts.URL + "/api/session")
	json.NewDecoder(res.Body).Decode(&status)
	res.Body.Close()
	if status.Kind != "signed_out" {
		t.Fatal("expired session accepted")
	}
}
func mustURL(s string) *url.URL { u, _ := url.Parse(s); return u }

func TestHTTPSCookiesAndConfiguration(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	schema := fmt.Sprintf("https_test_%d", time.Now().UnixNano())
	if _, err = pool.Exec(context.Background(), "CREATE SCHEMA "+schema); err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), "DROP SCHEMA "+schema+" CASCADE")
	cfgPool, _ := pgxpool.ParseConfig(dsn)
	cfgPool.ConnConfig.RuntimeParams["search_path"] = schema
	scoped, err := pgxpool.NewWithConfig(context.Background(), cfgPool)
	if err != nil {
		t.Fatal(err)
	}
	defer scoped.Close()
	if err = auth.Migrate(context.Background(), scoped); err != nil {
		t.Fatal(err)
	}
	cfg := auth.Config{AppOrigin: "https://dashboard.example", CallbackURL: "https://dashboard.example/api/auth/callback", EncryptionKey: make([]byte, 32)}
	server, err := auth.NewServer(cfg, scoped, &fakeBroker{user: "OWNER"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(server.Handler())
	defer ts.Close()
	client := &http.Client{CheckRedirect: func(r *http.Request, v []*http.Request) error { return http.ErrUseLastResponse }}
	req, _ := http.NewRequest("POST", ts.URL+"/api/auth/login", nil)
	req.Header.Set("Origin", cfg.AppOrigin)
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var start struct {
		URL string `json:"url"`
	}
	json.NewDecoder(res.Body).Decode(&start)
	res.Body.Close()
	binding := res.Cookies()[0]
	if !binding.Secure {
		t.Fatal("HTTPS binding cookie missing Secure")
	}
	u, _ := url.Parse(start.URL)
	q, _ := url.ParseQuery(u.Query().Get("redirect_params"))
	req, _ = http.NewRequest("GET", ts.URL+"/api/auth/callback?attempt="+q.Get("attempt")+"&request_token=success&status=success", nil)
	req.AddCookie(binding)
	res, err = client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	found := false
	for _, cookie := range res.Cookies() {
		if cookie.Name == "unaru_session" {
			found = true
			if !cookie.Secure || !cookie.HttpOnly {
				t.Fatal("HTTPS session cookie not protected")
			}
		}
	}
	if !found {
		t.Fatal("session cookie missing")
	}
	cfg.AppOrigin = "http://dashboard.example"
	cfg.CallbackURL = cfg.AppOrigin + "/api/auth/callback"
	if _, err = auth.NewServer(cfg, scoped, &fakeBroker{}, nil); err == nil {
		t.Fatal("non-loopback HTTP accepted")
	}
	cfg.AppOrigin = "http://localhost:5173"
	cfg.CallbackURL = "http://localhost:5173/wrong"
	if _, err = auth.NewServer(cfg, scoped, &fakeBroker{}, nil); err == nil {
		t.Fatal("wrong callback accepted")
	}
}
