package auth_test

import (
	"bytes"
	"context"
	"errors"
	kiteconnect "github.com/zerodha/gokiteconnect/v4"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/ankitgoyalio/unaru/backend/auth"
)

// Redirect the real SDK's external HTTP traffic to a controlled provider.
type providerTransport struct {
	target    *url.URL
	transport http.RoundTripper
}

func (t providerTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	request := r.Clone(r.Context())
	request.URL.Scheme, request.URL.Host = t.target.Scheme, t.target.Host
	return t.transport.RoundTrip(request)
}
func TestKiteOperationsCancelBlockedProviderRequests(t *testing.T) {
	// The SDK owns a stdout logger, separate from the application's logger.
	output, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	originalOutput := os.Stdout
	os.Stdout = writer
	var captured bytes.Buffer
	finished := make(chan struct{})
	go func() { io.Copy(&captured, output); close(finished) }()
	defer func() {
		os.Stdout = originalOutput
		writer.Close()
		<-finished
		output.Close()
		for _, marker := range []string{"sdk-api-key-marker", "sdk-api-secret-marker", "sdk-request-token-marker", "sdk-access-token-marker"} {
			if strings.Contains(captured.String(), marker) {
				t.Error("SDK leaked a credential in captured output")
			}
		}
	}()
	broker := auth.KiteBroker{APIKey: "sdk-api-key-marker", APISecret: "sdk-api-secret-marker"}
	operations := map[string]func(context.Context) error{
		"exchange": func(ctx context.Context) error {
			_, err := broker.Exchange(ctx, "sdk-request-token-marker")
			return err
		},
		"check":  func(ctx context.Context) error { return broker.CheckAccess(ctx, "sdk-access-token-marker") },
		"revoke": func(ctx context.Context) error { return broker.RevokeAccess(ctx, "sdk-access-token-marker") },
	}
	for name, operation := range operations {
		t.Run(name, func(t *testing.T) {
			entered := make(chan struct{})
			provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				io.Copy(io.Discard, r.Body)
				close(entered)
				<-r.Context().Done()
			}))
			defer provider.Close()
			target, _ := url.Parse(provider.URL)
			original := http.DefaultTransport
			http.DefaultTransport = providerTransport{target: target, transport: original}
			defer func() { http.DefaultTransport = original }()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			result := make(chan error, 1)
			go func() { result <- operation(ctx) }()
			select {
			case <-entered:
			case <-time.After(time.Second):
				t.Fatal("provider request did not start")
			}
			cancel()
			select {
			case err := <-result:
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("cancellation not propagated: %v", err)
				}
			case <-time.After(time.Second):
				t.Fatal("SDK request ignored operation cancellation")
			}
		})
	}
}

func TestKiteRevocationPreservesProviderTokenException(t *testing.T) {
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete || r.URL.Path != "/session/token" || r.URL.Query().Get("access_token") != "access" || r.Header.Get("X-Kite-Version") != "3" {
			t.Error("incorrect revocation request")
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		io.WriteString(w, `{"status":"error","error_type":"TokenException","message":"already invalid"}`)
	}))
	defer provider.Close()
	target, _ := url.Parse(provider.URL)
	original := http.DefaultTransport
	http.DefaultTransport = providerTransport{target: target, transport: original}
	defer func() { http.DefaultTransport = original }()
	err := (auth.KiteBroker{APIKey: "key", APISecret: "secret"}).RevokeAccess(context.Background(), "access")
	var providerError kiteconnect.Error
	if !errors.As(err, &providerError) || providerError.ErrorType != kiteconnect.TokenError {
		t.Fatalf("provider token classification lost: %v", err)
	}
}

func TestKiteExchangeCapturesDisplayName(t *testing.T) {
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, `{"status":"success","data":{"user_id":"OWNER","user_name":"Ankit Goyal","access_token":"access"}}`)
	}))
	defer provider.Close()
	target, _ := url.Parse(provider.URL)
	original := http.DefaultTransport
	http.DefaultTransport = providerTransport{target: target, transport: original}
	defer func() { http.DefaultTransport = original }()
	got, err := (auth.KiteBroker{APIKey: "key", APISecret: "secret"}).Exchange(context.Background(), "request")
	if err != nil || got.DisplayName != "Ankit Goyal" || got.UserID != "OWNER" {
		t.Fatalf("exchange identity: %+v, %v", got, err)
	}
}
