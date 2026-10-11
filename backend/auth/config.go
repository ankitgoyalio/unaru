package auth

import (
	"encoding/base64"
	"errors"
	"net"
	"net/url"
	"os"
	"strings"
)

type Config struct {
	APIKey, APISecret, DatabaseURL, CallbackURL, AppOrigin, ListenAddr string
	EncryptionKey                                                      []byte
	SecureCookies                                                      bool
}

func LoadConfig() (Config, error) {
	c := Config{APIKey: os.Getenv("KITE_API_KEY"), APISecret: os.Getenv("KITE_API_SECRET"), DatabaseURL: os.Getenv("DATABASE_URL"), CallbackURL: os.Getenv("KITE_CALLBACK_URL"), AppOrigin: os.Getenv("APP_ORIGIN"), ListenAddr: os.Getenv("LISTEN_ADDR")}
	if c.ListenAddr == "" {
		c.ListenAddr = "127.0.0.1:8080"
	}
	var err error
	c.EncryptionKey, err = base64.StdEncoding.DecodeString(os.Getenv("TOKEN_ENCRYPTION_KEY"))
	if err != nil || len(c.EncryptionKey) != 32 {
		return c, errors.New("TOKEN_ENCRYPTION_KEY must be a base64-encoded 32-byte key")
	}
	if c.APIKey == "" || c.APISecret == "" || c.DatabaseURL == "" {
		return c, errors.New("set KITE_API_KEY, KITE_API_SECRET, and DATABASE_URL in backend/.env")
	}
	return c, validateConfig(&c)
}
func validateConfig(c *Config) error {
	if len(c.EncryptionKey) != 32 {
		return errors.New("encryption key must contain 32 bytes")
	}
	origin, err := url.Parse(c.AppOrigin)
	if err != nil || origin.Host == "" || origin.User != nil || origin.RawQuery != "" || origin.Fragment != "" || (origin.Path != "" && origin.Path != "/") {
		return errors.New("APP_ORIGIN must be an origin URL")
	}
	callback, err := url.Parse(c.CallbackURL)
	if err != nil || callback.User != nil || callback.RawQuery != "" || callback.Fragment != "" || callback.Path != "/api/auth/callback" || callback.Scheme+"://"+callback.Host != strings.TrimSuffix(c.AppOrigin, "/") {
		return errors.New("KITE_CALLBACK_URL must be APP_ORIGIN/api/auth/callback")
	}
	if origin.Scheme != "https" {
		ip := net.ParseIP(origin.Hostname())
		if origin.Scheme != "http" || (origin.Hostname() != "localhost" && (ip == nil || !ip.IsLoopback())) {
			return errors.New("HTTP is supported only on loopback; use HTTPS elsewhere")
		}
	}
	c.AppOrigin = strings.TrimSuffix(c.AppOrigin, "/")
	c.SecureCookies = origin.Scheme == "https"
	return nil
}
