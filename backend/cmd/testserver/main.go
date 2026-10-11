// testserver serves the real HTTP API with isolated Postgres data and a fake broker.
// It is a test executable, never a production authentication mode.
package main

import (
	"context"
	"fmt"
	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

type broker struct{ invalid atomic.Bool }

func (*broker) LoginURL(attempt string) string {
	return "http://127.0.0.1:5173/api/test/kite?redirect_params=" + url.QueryEscape("attempt="+attempt)
}
func (*broker) Exchange(ctx context.Context, request string) (auth.Authorization, error) {
	if request == "fail" {
		return auth.Authorization{}, fmt.Errorf("fake provider failure")
	}
	user := "TESTOWNER"
	if request == "other" {
		user = "OTHER"
	}
	return auth.Authorization{UserID: user, AccessToken: "browser-test-secret"}, nil
}
func (b *broker) CheckAccess(context.Context, string) error {
	if b.invalid.Load() {
		return auth.ErrBrokerTokenExpired
	}
	return nil
}
func main() {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		log.Fatal("TEST_DATABASE_URL is required for browser integration tests")
	}
	ctx := context.Background()
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Fatal("invalid test database URL")
	}
	admin, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer admin.Close()
	schema := fmt.Sprintf("browser_test_%d", time.Now().UnixNano())
	if _, err = admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		log.Fatal(err)
	}
	defer admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE")
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()
	if err = auth.Migrate(ctx, pool); err != nil {
		log.Fatal(err)
	}
	fake := &broker{}
	server, err := auth.NewServer(auth.Config{AppOrigin: "http://127.0.0.1:5173", CallbackURL: "http://127.0.0.1:5173/api/auth/callback", EncryptionKey: make([]byte, 32)}, pool, fake, nil)
	if err != nil {
		log.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.Handle("/", server.Handler())
	mux.HandleFunc("POST /api/test/invalidate", func(w http.ResponseWriter, r *http.Request) {
		fake.invalid.Store(true)
		w.WriteHeader(204)
	})
	mux.HandleFunc("GET /api/test/kite", func(w http.ResponseWriter, r *http.Request) {
		q, _ := url.ParseQuery(r.URL.Query().Get("redirect_params"))
		outcome := r.URL.Query().Get("outcome")
		if outcome == "" {
			fake.invalid.Store(false)
		}
		if outcome == "" {
			outcome = "success"
		}
		q.Set("request_token", outcome)
		q.Set("status", "success")
		if outcome == "cancel" {
			q.Del("request_token")
			q.Set("status", "cancelled")
		}
		http.Redirect(w, r, "/api/auth/callback?"+q.Encode(), 303)
	})
	log.Print("fake Kite browser test backend ready")
	httpServer := &http.Server{Addr: "127.0.0.1:8080", Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	stopCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-stopCtx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		httpServer.Shutdown(shutdownCtx)
	}()
	if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Print("test server stopped")
	}

}
