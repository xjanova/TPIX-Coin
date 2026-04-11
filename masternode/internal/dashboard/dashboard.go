package dashboard

import (
	"context"
	"crypto/rand"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"
	"strings"
	"sync/atomic"
	"time"

	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
	"github.com/sirupsen/logrus"
	"github.com/xjanova/tpix-masternode/config"
	"github.com/xjanova/tpix-masternode/internal/monitor"
	"github.com/xjanova/tpix-masternode/internal/node"
)

//go:embed static/*
var staticFS embed.FS

//go:embed templates/*
var templateFS embed.FS

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		// Allow localhost origins only
		return origin == "" ||
			origin == "http://localhost" ||
			origin == "http://127.0.0.1" ||
			strings.HasPrefix(origin, "http://localhost:") ||
			strings.HasPrefix(origin, "http://127.0.0.1:")
	},
}

// Max concurrent WebSocket connections
const maxWSConnections = 10

var activeWSConnections int32

// Dashboard serves the web UI and WebSocket for real-time updates
type Dashboard struct {
	cfg      *config.Config
	node     *node.Node
	monitor  *monitor.Monitor
	log      *logrus.Logger
	router   *mux.Router
	apiToken string
}

// New creates a new dashboard server
func New(cfg *config.Config, n *node.Node, mon *monitor.Monitor, log *logrus.Logger) *Dashboard {
	// Generate a random API token for this session
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		log.Fatalf("Failed to generate secure API token: %v", err)
	}
	apiToken := fmt.Sprintf("%x", tokenBytes)

	d := &Dashboard{
		cfg:      cfg,
		node:     n,
		monitor:  mon,
		log:      log,
		router:   mux.NewRouter(),
		apiToken: apiToken,
	}
	d.setupRoutes()
	log.Infof("Dashboard API token: %s... (use full token for auth)", apiToken[:8])
	return d
}

// requireAuth middleware checks for valid API token via Bearer header or query param
func (d *Dashboard) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := ""
		// Check Authorization header first
		auth := r.Header.Get("Authorization")
		if strings.HasPrefix(auth, "Bearer ") {
			token = strings.TrimPrefix(auth, "Bearer ")
		}
		// Fallback to query parameter
		if token == "" {
			token = r.URL.Query().Get("token")
		}
		if token != d.apiToken {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

func (d *Dashboard) setupRoutes() {
	// API endpoints (require authentication)
	api := d.router.PathPrefix("/api").Subrouter()
	api.HandleFunc("/status", d.requireAuth(d.handleStatus)).Methods("GET")
	api.HandleFunc("/metrics", d.requireAuth(d.handleMetrics)).Methods("GET")
	api.HandleFunc("/rewards", d.requireAuth(d.handleRewards)).Methods("GET")
	api.HandleFunc("/network", d.requireAuth(d.handleNetwork)).Methods("GET")

	// WebSocket for real-time updates (requires token query param)
	d.router.HandleFunc("/ws", d.requireAuth(d.handleWebSocket))

	// Serve embedded static files
	d.router.PathPrefix("/static/").Handler(http.FileServer(http.FS(staticFS)))

	// Main page
	d.router.HandleFunc("/", d.handleIndex).Methods("GET")
}

// Start begins serving the dashboard (localhost only for security)
func (d *Dashboard) Start(ctx context.Context) {
	addr := fmt.Sprintf("127.0.0.1:%d", d.cfg.DashboardPort)
	server := &http.Server{
		Addr:         addr,
		Handler:      d.router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		<-ctx.Done()
		server.Close()
	}()

	d.log.Infof("Dashboard listening on http://%s", addr)
	if err := server.ListenAndServe(); err != http.ErrServerClosed {
		d.log.Errorf("Dashboard error: %v", err)
	}
}

func (d *Dashboard) handleIndex(w http.ResponseWriter, r *http.Request) {
	tmpl, err := template.ParseFS(templateFS, "templates/index.html")
	if err != nil {
		http.Error(w, "Template error", 500)
		return
	}
	data := map[string]interface{}{
		"Version":   "1.0.0",
		"NodeName":  d.cfg.NodeName,
		"Tier":      d.cfg.GetTier().String(),
		"Port":      d.cfg.DashboardPort,
	}
	tmpl.Execute(w, data)
}

func (d *Dashboard) handleStatus(w http.ResponseWriter, r *http.Request) {
	info := d.node.GetInfo()
	writeJSON(w, info)
}

func (d *Dashboard) handleMetrics(w http.ResponseWriter, r *http.Request) {
	metrics := d.monitor.GetMetrics()
	writeJSON(w, metrics)
}

func (d *Dashboard) handleRewards(w http.ResponseWriter, r *http.Request) {
	history := d.node.GetRewardHistory()
	writeJSON(w, history)
}

func (d *Dashboard) handleNetwork(w http.ResponseWriter, r *http.Request) {
	info := d.node.GetInfo()
	writeJSON(w, info.Network)
}

func (d *Dashboard) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Limit concurrent WebSocket connections
	if atomic.LoadInt32(&activeWSConnections) >= maxWSConnections {
		http.Error(w, "Too many connections", http.StatusServiceUnavailable)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		d.log.Errorf("WebSocket upgrade error: %v", err)
		return
	}
	atomic.AddInt32(&activeWSConnections, 1)
	defer func() {
		conn.Close()
		atomic.AddInt32(&activeWSConnections, -1)
	}()

	// Read pump to detect client disconnect
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()

	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-done:
			return
		case <-ticker.C:
			conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			data := map[string]interface{}{
				"status":  d.node.GetInfo(),
				"metrics": d.monitor.GetMetrics(),
			}
			if err := conn.WriteJSON(data); err != nil {
				return
			}
		}
	}
}

// GetAPIToken returns the dashboard API token for use by the Electron frontend
func (d *Dashboard) GetAPIToken() string {
	return d.apiToken
}

func writeJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	// No CORS header — dashboard is localhost-only, no cross-origin access needed
	json.NewEncoder(w).Encode(data)
}
