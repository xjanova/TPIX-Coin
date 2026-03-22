package dashboard

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"
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
	CheckOrigin: func(r *http.Request) bool { return true },
}

// Dashboard serves the web UI and WebSocket for real-time updates
type Dashboard struct {
	cfg     *config.Config
	node    *node.Node
	monitor *monitor.Monitor
	log     *logrus.Logger
	router  *mux.Router
}

// New creates a new dashboard server
func New(cfg *config.Config, n *node.Node, mon *monitor.Monitor, log *logrus.Logger) *Dashboard {
	d := &Dashboard{
		cfg:     cfg,
		node:    n,
		monitor: mon,
		log:     log,
		router:  mux.NewRouter(),
	}
	d.setupRoutes()
	return d
}

func (d *Dashboard) setupRoutes() {
	// API endpoints
	api := d.router.PathPrefix("/api").Subrouter()
	api.HandleFunc("/status", d.handleStatus).Methods("GET")
	api.HandleFunc("/metrics", d.handleMetrics).Methods("GET")
	api.HandleFunc("/rewards", d.handleRewards).Methods("GET")
	api.HandleFunc("/network", d.handleNetwork).Methods("GET")

	// WebSocket for real-time updates
	d.router.HandleFunc("/ws", d.handleWebSocket)

	// Serve embedded static files
	d.router.PathPrefix("/static/").Handler(http.FileServer(http.FS(staticFS)))

	// Main page
	d.router.HandleFunc("/", d.handleIndex).Methods("GET")
}

// Start begins serving the dashboard
func (d *Dashboard) Start(ctx context.Context) {
	addr := fmt.Sprintf(":%d", d.cfg.DashboardPort)
	server := &http.Server{
		Addr:    addr,
		Handler: d.router,
	}

	go func() {
		<-ctx.Done()
		server.Close()
	}()

	d.log.Infof("Dashboard listening on http://localhost%s", addr)
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
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		d.log.Errorf("WebSocket upgrade error: %v", err)
		return
	}
	defer conn.Close()

	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
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

func writeJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(data)
}
