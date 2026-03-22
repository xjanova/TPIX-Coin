package main

import (
	"context"
	"fmt"
	"math/big"
	"runtime"
	"sync"
	"time"

	wailsRuntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

// NodeTier represents a tier type
type NodeTier int

const (
	TierValidator NodeTier = iota
	TierSentinel
	TierLight
)

// App is the main Wails application backend
type App struct {
	ctx context.Context

	// Node state
	mu            sync.RWMutex
	running       bool
	nodeName      string
	tier          string
	walletAddress string
	startedAt     time.Time

	// Simulated blockchain state
	blockHeight    uint64
	connectedPeers int
	stakedAmount   *big.Int
	pendingReward  *big.Int
	totalRewards   *big.Int
	uptimeScore    float64

	// System metrics
	cpuPercent    float64
	memPercent    float64
	memUsedMB     uint64
	memTotalMB    uint64
	diskPercent   float64
	diskUsedGB    uint64
	diskTotalGB   uint64
	networkInMB   float64
	networkOutMB  float64

	// Network stats
	totalNodes      int
	validatorNodes  int
	sentinelNodes   int
	lightNodes      int
	networkStaked   string
	rewardsDistrib  string
	remainingReward string
	currentYear     int
	blockReward     string

	// Control
	cancel context.CancelFunc
}

// NewApp creates a new App
func NewApp() *App {
	return &App{
		nodeName:        fmt.Sprintf("tpix-node-%d", time.Now().Unix()%10000),
		tier:            "Light",
		walletAddress:   "",
		stakedAmount:    big.NewInt(0),
		pendingReward:   big.NewInt(0),
		totalRewards:    big.NewInt(0),
		uptimeScore:     100.0,
		networkStaked:   "0",
		rewardsDistrib:  "0",
		remainingReward: "1,400,000,000",
		currentYear:     1,
		blockReward:     "25.5",
	}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// ============================================================
//  Exported methods (callable from frontend via Wails bindings)
// ============================================================

// NodeStatus is returned to the frontend
type NodeStatus struct {
	Running        bool    `json:"running"`
	NodeName       string  `json:"node_name"`
	Tier           string  `json:"tier"`
	WalletAddress  string  `json:"wallet_address"`
	BlockHeight    uint64  `json:"block_height"`
	ConnectedPeers int     `json:"connected_peers"`
	StakedAmount   string  `json:"staked_amount"`
	PendingReward  string  `json:"pending_reward"`
	TotalRewards   string  `json:"total_rewards"`
	UptimePercent  float64 `json:"uptime_percent"`
	UptimeSeconds  int64   `json:"uptime_seconds"`
	SyncProgress   float64 `json:"sync_progress"`
	Version        string  `json:"version"`
}

// SystemMetrics is returned to the frontend
type SystemMetrics struct {
	CPUPercent    float64 `json:"cpu_percent"`
	MemoryPercent float64 `json:"memory_percent"`
	MemoryUsedMB  uint64  `json:"memory_used_mb"`
	MemoryTotalMB uint64  `json:"memory_total_mb"`
	DiskPercent   float64 `json:"disk_percent"`
	DiskUsedGB    uint64  `json:"disk_used_gb"`
	DiskTotalGB   uint64  `json:"disk_total_gb"`
	NetworkInMB   float64 `json:"network_in_mb"`
	NetworkOutMB  float64 `json:"network_out_mb"`
	OS            string  `json:"os"`
	Arch          string  `json:"arch"`
	GoRoutines    int     `json:"goroutines"`
}

// NetworkInfo is returned to the frontend
type NetworkInfo struct {
	TotalNodes        int    `json:"total_nodes"`
	ValidatorNodes    int    `json:"validator_nodes"`
	SentinelNodes     int    `json:"sentinel_nodes"`
	LightNodes        int    `json:"light_nodes"`
	TotalStaked       string `json:"total_staked"`
	TotalDistributed  string `json:"total_distributed"`
	RemainingRewards  string `json:"remaining_rewards"`
	CurrentYear       int    `json:"current_year"`
	BlockReward       string `json:"block_reward"`
}

// NodeConfig for settings UI
type NodeConfig struct {
	NodeName      string `json:"node_name"`
	Tier          string `json:"tier"`
	WalletAddress string `json:"wallet_address"`
	ChainRPC      string `json:"chain_rpc"`
	ChainID       int64  `json:"chain_id"`
	DashboardPort int    `json:"dashboard_port"`
	P2PPort       int    `json:"p2p_port"`
	MaxPeers      int    `json:"max_peers"`
	LogLevel      string `json:"log_level"`
	AutoUpdate    bool   `json:"auto_update"`
}

// GetNodeStatus returns current node status
func (a *App) GetNodeStatus() NodeStatus {
	a.mu.RLock()
	defer a.mu.RUnlock()

	uptimeSeconds := int64(0)
	if a.running && !a.startedAt.IsZero() {
		uptimeSeconds = int64(time.Since(a.startedAt).Seconds())
	}

	return NodeStatus{
		Running:        a.running,
		NodeName:       a.nodeName,
		Tier:           a.tier,
		WalletAddress:  a.walletAddress,
		BlockHeight:    a.blockHeight,
		ConnectedPeers: a.connectedPeers,
		StakedAmount:   formatTPIX(a.stakedAmount),
		PendingReward:  formatTPIX(a.pendingReward),
		TotalRewards:   formatTPIX(a.totalRewards),
		UptimePercent:  a.uptimeScore,
		UptimeSeconds:  uptimeSeconds,
		SyncProgress:   100.0,
		Version:        "1.0.0",
	}
}

// GetSystemMetrics returns system resource metrics
func (a *App) GetSystemMetrics() SystemMetrics {
	a.mu.RLock()
	defer a.mu.RUnlock()

	return SystemMetrics{
		CPUPercent:    a.cpuPercent,
		MemoryPercent: a.memPercent,
		MemoryUsedMB:  a.memUsedMB,
		MemoryTotalMB: a.memTotalMB,
		DiskPercent:   a.diskPercent,
		DiskUsedGB:    a.diskUsedGB,
		DiskTotalGB:   a.diskTotalGB,
		NetworkInMB:   a.networkInMB,
		NetworkOutMB:  a.networkOutMB,
		OS:            runtime.GOOS,
		Arch:          runtime.GOARCH,
		GoRoutines:    runtime.NumGoroutine(),
	}
}

// GetNetworkInfo returns network-wide statistics
func (a *App) GetNetworkInfo() NetworkInfo {
	a.mu.RLock()
	defer a.mu.RUnlock()

	return NetworkInfo{
		TotalNodes:       a.totalNodes,
		ValidatorNodes:   a.validatorNodes,
		SentinelNodes:    a.sentinelNodes,
		LightNodes:       a.lightNodes,
		TotalStaked:      a.networkStaked,
		TotalDistributed: a.rewardsDistrib,
		RemainingRewards: a.remainingReward,
		CurrentYear:      a.currentYear,
		BlockReward:      a.blockReward,
	}
}

// GetConfig returns current configuration
func (a *App) GetConfig() NodeConfig {
	a.mu.RLock()
	defer a.mu.RUnlock()

	return NodeConfig{
		NodeName:      a.nodeName,
		Tier:          a.tier,
		WalletAddress: a.walletAddress,
		ChainRPC:      "https://rpc.tpix.online",
		ChainID:       4289,
		DashboardPort: 3847,
		P2PPort:       30303,
		MaxPeers:      50,
		LogLevel:      "info",
		AutoUpdate:    true,
	}
}

// SaveConfig saves configuration
func (a *App) SaveConfig(cfg NodeConfig) string {
	a.mu.Lock()
	defer a.mu.Unlock()

	a.nodeName = cfg.NodeName
	a.tier = cfg.Tier
	a.walletAddress = cfg.WalletAddress

	return "Configuration saved"
}

// StartNode begins node operations
func (a *App) StartNode() string {
	a.mu.Lock()

	if a.running {
		a.mu.Unlock()
		return "Node is already running"
	}

	if a.walletAddress == "" {
		a.mu.Unlock()
		return "Error: Set wallet address in Settings first"
	}

	a.running = true
	a.startedAt = time.Now()

	ctx, cancel := context.WithCancel(a.ctx)
	a.cancel = cancel
	a.mu.Unlock()

	// Background loops
	go a.syncLoop(ctx)
	go a.metricsLoop(ctx)
	go a.emitUpdates(ctx)

	// Notify frontend
	wailsRuntime.EventsEmit(a.ctx, "node:started", nil)

	return "Node started successfully"
}

// StopNode stops the node
func (a *App) StopNode() string {
	a.mu.Lock()
	defer a.mu.Unlock()

	if !a.running {
		return "Node is not running"
	}

	if a.cancel != nil {
		a.cancel()
	}
	a.running = false

	wailsRuntime.EventsEmit(a.ctx, "node:stopped", nil)

	return "Node stopped"
}

// ============================================================
//  Background loops
// ============================================================

func (a *App) syncLoop(ctx context.Context) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.mu.Lock()
			a.blockHeight++
			a.connectedPeers = 4

			// Simulate reward accumulation based on tier
			reward := big.NewInt(0)
			switch a.tier {
			case "Validator":
				reward.SetString("258000000000000000", 10) // ~0.258 TPIX per 2s block
			case "Sentinel":
				reward.SetString("38700000000000000", 10) // ~0.039
			default:
				reward.SetString("10300000000000000", 10) // ~0.010
			}
			a.pendingReward = new(big.Int).Add(a.pendingReward, reward)
			a.mu.Unlock()
		}
	}
}

func (a *App) metricsLoop(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.collectMetrics()
		}
	}
}

func (a *App) collectMetrics() {
	a.mu.Lock()
	defer a.mu.Unlock()

	// Simplified metrics (gopsutil would be used in full build)
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)
	a.memUsedMB = memStats.Alloc / 1024 / 1024
	a.memTotalMB = memStats.Sys / 1024 / 1024
	if a.memTotalMB > 0 {
		a.memPercent = float64(a.memUsedMB) / float64(a.memTotalMB) * 100
	}
}

func (a *App) emitUpdates(ctx context.Context) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			status := a.GetNodeStatus()
			metrics := a.GetSystemMetrics()
			network := a.GetNetworkInfo()

			wailsRuntime.EventsEmit(a.ctx, "node:update", map[string]interface{}{
				"status":  status,
				"metrics": metrics,
				"network": network,
			})
		}
	}
}

func formatTPIX(wei *big.Int) string {
	if wei == nil {
		return "0.0000"
	}
	ether := new(big.Float).Quo(
		new(big.Float).SetInt(wei),
		new(big.Float).SetInt(new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil)),
	)
	return fmt.Sprintf("%.4f", ether)
}
