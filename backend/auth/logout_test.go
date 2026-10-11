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

type revokingBroker struct {
	fakeBroker
	fail          bool
	revocations   int
	entered       chan struct{}
	release       chan struct{}
	revokeRelease chan struct{}
}

func (b *revokingBroker) Exchange(ctx context.Context, token string) (auth.Authorization, error) {
	if b.entered != nil {
		close(b.entered)
		<-b.release
	}
	return b.fakeBroker.Exchange(ctx, token)
}
func (b *revokingBroker) RevokeAccess(context.Context, string) error {
	if b.revokeRelease != nil {
		<-b.revokeRelease
	}
	b.revocations++
	if b.fail {
		return errors.New("outage")
	}
	return nil
}
func TestLogout(t *testing.T) {
	for _, path := range []string{"/api/auth/login", "/api/auth/reconnect"} {
		t.Run(path, func(t *testing.T) { testLogout(t, path) })
	}
}

func testLogout(t *testing.T, pendingPath string) {
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
	// Saved investment data belongs to the installation, not its login session.
	if _, err := pool.Exec(context.Background(), "CREATE TABLE saved_investment_fixture (id text PRIMARY KEY, holdings jsonb NOT NULL); INSERT INTO saved_investment_fixture VALUES ('portfolio', '{\"units\":7}')"); err != nil {
		t.Fatal(err)
	}
	broker := &revokingBroker{fakeBroker: fakeBroker{user: "OWNER1"}, fail: true, revokeRelease: make(chan struct{})}
	revokeRelease := broker.revokeRelease

	now := time.Date(2026, 10, 11, 12, 0, 0, 0, time.UTC)
	cfg := auth.Config{AppOrigin: "http://localhost:5173", CallbackURL: "http://localhost:5173/api/auth/callback", EncryptionKey: make([]byte, 32)}
	srv, err := auth.NewServer(cfg, pool, broker, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(srv.Handler())
	defer func() { close(revokeRelease); ts.Close() }()
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

	oldCookies := jar.Cookies(mustURL(ts.URL))
	// Pause a new callback inside the external token exchange while logout wins.
	req, _ = http.NewRequest("POST", ts.URL+pendingPath, nil)
	req.Header.Set("Origin", cfg.AppOrigin)
	res, _ = client.Do(req)
	json.NewDecoder(res.Body).Decode(&start)
	res.Body.Close()
	u, _ = url.Parse(start.URL)
	q, _ = url.ParseQuery(u.Query().Get("redirect_params"))
	pendingRequest, _ := http.NewRequest("GET", ts.URL+"/api/auth/callback?attempt="+q.Get("attempt")+"&request_token=ok&status=success", nil)
	for _, c := range jar.Cookies(mustURL(ts.URL)) {
		pendingRequest.AddCookie(c)
	}
	broker.entered = make(chan struct{})
	broker.release = make(chan struct{})
	pendingResult := make(chan *http.Response, 1)
	go func() {
		r, _ := (&http.Client{CheckRedirect: client.CheckRedirect}).Do(pendingRequest)
		pendingResult <- r
	}()
	<-broker.entered

	req, _ = http.NewRequest("POST", ts.URL+"/api/auth/logout", nil)
	req.Header.Set("Origin", "https://attacker.invalid")
	res, _ = client.Do(req)
	res.Body.Close()
	if res.StatusCode != 403 {
		t.Fatal("unprotected logout")
	}
	req.Header.Set("Origin", cfg.AppOrigin)
	client.Timeout = time.Second
	res, err = client.Do(req)
	if err != nil {
		close(broker.release)
		t.Fatalf("logout waited for blocked broker: %v", err)
	}
	res.Body.Close()
	if res.StatusCode != 204 {
		t.Fatalf("logout status %d", res.StatusCode)
	}
	close(broker.release)
	pendingResponse := <-pendingResult
	if pendingResponse == nil {
		t.Fatal("callback failed")
	}
	pendingResponse.Body.Close()
	if !strings.Contains(pendingResponse.Header.Get("Location"), "error=invalid_attempt") {
		t.Fatal("concurrent callback restored logged-out session")
	}
	broker.entered = nil
	if broker.revocations != 0 {
		t.Fatal("HTTP logout called broker")
	}
	broker.revokeRelease = nil
	if err := srv.RetryRevocations(context.Background()); err != nil {
		t.Fatal(err)
	}
	if broker.revocations != 2 {
		t.Fatal("durable worker lost tokens")
	}
	res, _ = client.Do(req)
	res.Body.Close()
	if res.StatusCode != 204 {
		t.Fatal("repeated logout failed")
	}
	stale, _ := http.NewRequest("GET", ts.URL+"/api/session", nil)
	for _, c := range oldCookies {
		stale.AddCookie(c)
	}
	res, _ = (&http.Client{}).Do(stale)
	json.NewDecoder(res.Body).Decode(&status)
	res.Body.Close()
	if status.Kind != "signed_out" {
		t.Fatal("revoked cookie accepted")
	}
	now = now.Add(time.Minute)
	broker.fail = false
	restarted, _ := auth.NewServer(cfg, pool, broker, func() time.Time { return now })
	if err := restarted.RetryRevocations(context.Background()); err != nil {
		t.Fatal(err)
	}
	if broker.revocations != 4 {
		t.Fatal("restart lost pending revocation")
	}
	restarted.RetryRevocations(context.Background())
	if broker.revocations != 4 {
		t.Fatal("completed revocation repeated")
	}

	var retained string
	if err := pool.QueryRow(context.Background(), "SELECT holdings->>'units' FROM saved_investment_fixture WHERE id='portfolio'").Scan(&retained); err != nil || retained != "7" {
		t.Fatal("logout changed saved investment data")
	}
	// Retaining the installation identity prevents another account taking over.
	broker.user = "OTHER"
	req, _ = http.NewRequest("POST", ts.URL+"/api/auth/login", nil)
	req.Header.Set("Origin", cfg.AppOrigin)
	res, _ = client.Do(req)
	json.NewDecoder(res.Body).Decode(&start)
	res.Body.Close()
	u, _ = url.Parse(start.URL)
	q, _ = url.ParseQuery(u.Query().Get("redirect_params"))
	res, _ = client.Get(ts.URL + "/api/auth/callback?attempt=" + q.Get("attempt") + "&request_token=ok&status=success")
	res.Body.Close()
	if !strings.Contains(res.Header.Get("Location"), "error=account_mismatch") {
		t.Fatal("logout erased installation identity")
	}
}
