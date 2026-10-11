// verify-live observes user-driven acceptance actions without printing secrets.
package main

import (
	"context"
	"fmt"
	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"os"
	"time"
)

func main() {
	if !run() {
		fmt.Println("verification: FAIL")
		os.Exit(1)
	}
	fmt.Println("verification: PASS")
}
func run() bool {
	if len(os.Args) != 2 || (os.Args[1] != "logout" && os.Args[1] != "reconnect") {
		return false
	}
	godotenv.Load(".env")
	cfg, err := auth.LoadConfig()
	if err != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return false
	}
	defer pool.Close()
	server, err := auth.NewServer(cfg, pool, auth.KiteBroker{APIKey: cfg.APIKey, APISecret: cfg.APISecret}, nil)
	if err != nil {
		return false
	}
	captured := func() { fmt.Println("capture: PASS") }
	if os.Args[1] == "logout" {
		err = server.VerifyLogoutForAcceptance(ctx, captured)
	} else {
		err = server.VerifyReconnectForAcceptance(ctx, captured)
	}
	return err == nil
}
