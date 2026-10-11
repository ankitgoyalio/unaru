package auth_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

type checkingBroker struct {
	fakeBroker
	checkErr error
}

func (b *checkingBroker) CheckAccess(context.Context, string) error { return b.checkErr }
func TestReconnectPreservesDashboardSession(t *testing.T) {
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
	schema := fmt.Sprintf("reconnect_%d", time.Now().UnixNano())
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
	now := time.Now().UTC()
	broker := &checkingBroker{fakeBroker: fakeBroker{user: "OWNER"}}
	cfg := auth.Config{AppOrigin: "http://localhost:5173", CallbackURL: "http://localhost:5173/api/auth/callback", EncryptionKey: make([]byte, 32)}
	s, err := auth.NewServer(cfg, pool, broker, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(s.Handler())
	defer ts.Close()
	jar, _ := cookiejar.New(nil)
	client := &http.Client{Jar: jar, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	start := func(path string) string {
		t.Helper()
		req, _ := http.NewRequest("POST", ts.URL+path, nil)
		req.Header.Set("Origin", cfg.AppOrigin)
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		if res.StatusCode != 200 {
			t.Fatalf("start %s: %d", path, res.StatusCode)
		}
		var v struct{ URL string }
		json.NewDecoder(res.Body).Decode(&v)
		u, _ := url.Parse(v.URL)
		q, _ := url.ParseQuery(u.Query().Get("redirect_params"))
		return ts.URL + "/api/auth/callback?attempt=" + q.Get("attempt")
	}
	callback := func(u, token string) *http.Response {
		t.Helper()
		res, err := client.Get(u + "&status=success&request_token=" + token)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		return res
	}
	status := func() auth.SessionStatus {
		t.Helper()
		res, err := client.Get(ts.URL + "/api/session")
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		if res.StatusCode != 200 {
			t.Fatalf("session %d", res.StatusCode)
		}
		var st auth.SessionStatus
		json.NewDecoder(res.Body).Decode(&st)
		return st
	}
	callback(start("/api/auth/login"), "success")
	original := status()
	var sessionID string
	for _, c := range jar.Cookies(mustURL(ts.URL)) {
		if c.Name == "unaru_session" {
			sessionID = c.Value
		}
	}
	broker.checkErr = errors.New("network failure")
	if got := status(); got.Kind != "signed_in" || got.Connection != "active" {
		t.Fatalf("outage changed session %+v", got)
	}
	broker.checkErr = auth.ErrBrokerTokenExpired
	if got := status(); got.Kind != "signed_in" || got.Connection != "reconnect_required" {
		t.Fatalf("invalidation %+v", got)
	}
	for _, tc := range []struct{ token, user, want string }{{"", "OWNER", "cancelled"}, {"fail", "OWNER", "exchange_failed"}, {"other", "OTHER", "account_mismatch"}} {
		broker.user = tc.user
		res := callback(start("/api/auth/reconnect"), tc.token)
		if !strings.Contains(res.Header.Get("Location"), "error="+tc.want) {
			t.Fatalf("reconnect failure %s", res.Header.Get("Location"))
		}
		if got := status(); got.UserID != "OWNER" || got.Connection != "reconnect_required" {
			t.Fatalf("failed reconnect changed access %+v", got)
		}
	}
	broker.user = "OWNER"
	broker.checkErr = nil
	attempt := start("/api/auth/reconnect")
	res := callback(attempt, "success")
	if res.Header.Get("Location") != cfg.AppOrigin+"/dashboard" {
		t.Fatal("reconnect failed")
	}
	for _, c := range res.Cookies() {
		if c.Name == "unaru_session" {
			t.Fatal("reconnect replaced dashboard cookie")
		}
	}
	restored := status()
	if restored.Connection != "active" || !restored.ExpiresAt.Equal(original.ExpiresAt) {
		t.Fatalf("reconnect extended session %+v", restored)
	}
	for _, c := range jar.Cookies(mustURL(ts.URL)) {
		if c.Name == "unaru_session" && c.Value != sessionID {
			t.Fatal("session changed")
		}
	}
	exchanges := broker.exchanges
	res = callback(attempt, "success")
	if !strings.Contains(res.Header.Get("Location"), "error=invalid_attempt") || broker.exchanges != exchanges {
		t.Fatal("callback replayed")
	}
	attempt = start("/api/auth/reconnect")
	now = original.ExpiresAt
	res = callback(attempt, "success")
	if !strings.Contains(res.Header.Get("Location"), "error=invalid_attempt") {
		t.Fatal("expired session reconnected")
	}
	if status().Kind != "signed_out" {
		t.Fatal("expired dashboard restored")
	}
}
