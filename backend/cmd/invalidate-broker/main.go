// invalidate-broker is a local live-acceptance command. It has no HTTP endpoint
// and reads all credentials internally from the backend environment.
package main

import (
	"context"
	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"log"
	"time"
)

func main() {
	godotenv.Load(".env")
	cfg, err := auth.LoadConfig()
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal("database configuration invalid")
	}
	defer pool.Close()
	server, err := auth.NewServer(cfg, pool, auth.KiteBroker{APIKey: cfg.APIKey, APISecret: cfg.APISecret}, nil)
	if err != nil {
		log.Fatal("backend configuration invalid")
	}
	if err = server.InvalidateBrokerForAcceptance(ctx); err != nil {
		log.Fatal(err)
	}
	log.Print("Broker token invalidated. Dashboard sessions and expiry are unchanged. Reload the dashboard to reconnect.")
}
