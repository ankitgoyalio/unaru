package main

import (
	"context"
	"github.com/ankitgoyalio/unaru/backend/auth"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"log"
	"net/http"
	"time"
)

func main() {
	godotenv.Load(".env")
	cfg, err := auth.LoadConfig()
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal("database configuration invalid")
	}
	defer pool.Close()
	if err = auth.Migrate(ctx, pool); err != nil {
		log.Fatal("database migration failed; check DATABASE_URL and database availability")
	}
	server, err := auth.NewServer(cfg, pool, auth.KiteBroker{APIKey: cfg.APIKey, APISecret: cfg.APISecret}, nil)
	if err != nil {
		log.Fatal(err)
	}
	log.Print("Unaru backend ready")
	httpServer := &http.Server{Addr: cfg.ListenAddr, Handler: server.Handler(), ReadHeaderTimeout: 5 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second}
	log.Fatal(httpServer.ListenAndServe())
}
