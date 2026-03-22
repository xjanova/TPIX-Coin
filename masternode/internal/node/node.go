package node

import (
	"context"
	"fmt"
	"math/big"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/xjanova/tpix-masternode/config"
)

// NodeState represents the running state of the master node
type NodeState int

const (
	StateStopped NodeState = iota
	StateStarting
	StateSyncing
	StateRunning
	StateError
)

func (s NodeState) String() string {
	switch s {
	case StateStopped:
		return "Stopped"
	case StateStarting:
		return "Starting"
	case StateSyncing:
		return "Syncing"
	case StateRunning:
		return "Running"
	case StateError:
		return "Error"
	default:
		return "Unknown"
	}
}

// NetworkStats holds real-time network statistics
type NetworkStats struct {
	TotalNodes         int       `json:"total_nodes"`
	ValidatorNodes     int       `json:"validator_nodes"`
	SentinelNodes      int       `json:"sentinel_nodes"`
	LightNodes         int       `json:"light_nodes"`
	TotalStaked        string    `json:"total_staked"`
	TotalRewards       string    `json:"total_rewards_distributed"`
	RemainingRewards   string    `json:"remaining_rewards"`
	CurrentBlockReward string    `json:"current_block_reward"`
	CurrentYear        int       `json:"current_year"`
	BlockHeight        uint64    `json:"block_height"`
	LastBlockTime      time.Time `json:"last_block_time"`
}

// NodeInfo holds this node's status information
type NodeInfo struct {
	Name           string         `json:"name"`
	Tier           string         `json:"tier"`
	State          string         `json:"state"`
	WalletAddress  string         `json:"wallet_address"`
	StakedAmount   string         `json:"staked_amount"`
	PendingReward  string         `json:"pending_reward"`
	TotalRewards   string         `json:"total_rewards"`
	Uptime         float64        `json:"uptime_percent"`
	UptimeSeconds  int64          `json:"uptime_seconds"`
	ConnectedPeers int            `json:"connected_peers"`
	BlockHeight    uint64         `json:"block_height"`
	SyncProgress   float64        `json:"sync_progress"`
	Version        string         `json:"version"`
	StartedAt      time.Time      `json:"started_at"`
	LastRewardAt   time.Time      `json:"last_reward_at"`
	RegisteredAt   time.Time      `json:"registered_at"`
	Network        *NetworkStats  `json:"network"`
}

// RewardHistory holds reward event
type RewardHistory struct {
	Timestamp time.Time `json:"timestamp"`
	Amount    string    `json:"amount"`
	Block     uint64    `json:"block"`
	TxHash    string    `json:"tx_hash"`
}

// Node is the main master node instance
type Node struct {
	cfg       *config.Config
	log       *logrus.Logger
	state     NodeState
	startedAt time.Time

	// Blockchain interaction
	blockHeight   uint64
	syncProgress  float64
	connectedPeers int

	// Staking
	stakedAmount  *big.Int
	pendingReward *big.Int
	totalRewards  *big.Int
	uptimeScore   float64
	lastRewardAt  time.Time
	registeredAt  time.Time

	// Network stats (from contract)
	networkStats *NetworkStats

	// Reward history
	rewardHistory []RewardHistory

	// Concurrency
	mu     sync.RWMutex
	cancel context.CancelFunc
}

// New creates a new master node
func New(cfg *config.Config, log *logrus.Logger) (*Node, error) {
	if cfg.WalletAddress == "" {
		return nil, fmt.Errorf("wallet address is required")
	}

	return &Node{
		cfg:           cfg,
		log:           log,
		state:         StateStopped,
		stakedAmount:  big.NewInt(0),
		pendingReward: big.NewInt(0),
		totalRewards:  big.NewInt(0),
		uptimeScore:   100.0,
		networkStats:  &NetworkStats{},
		rewardHistory: make([]RewardHistory, 0),
	}, nil
}

// Start begins node operations
func (n *Node) Start(ctx context.Context) error {
	n.mu.Lock()
	defer n.mu.Unlock()

	n.state = StateStarting
	n.startedAt = time.Now()

	ctx, n.cancel = context.WithCancel(ctx)

	n.log.Info("Connecting to TPIX Chain...")
	n.log.Infof("RPC: %s", n.cfg.ChainRPC)

	// Start background tasks
	go n.syncLoop(ctx)
	go n.rewardLoop(ctx)
	go n.heartbeatLoop(ctx)

	n.state = StateRunning
	return nil
}

// Stop shuts down the node
func (n *Node) Stop() {
	n.mu.Lock()
	defer n.mu.Unlock()

	if n.cancel != nil {
		n.cancel()
	}
	n.state = StateStopped
	n.log.Info("Node stopped")
}

// GetInfo returns current node information
func (n *Node) GetInfo() *NodeInfo {
	n.mu.RLock()
	defer n.mu.RUnlock()

	uptimeSeconds := int64(0)
	if !n.startedAt.IsZero() {
		uptimeSeconds = int64(time.Since(n.startedAt).Seconds())
	}

	// Copy network stats to avoid data race (pointer escape)
	var netStats *NetworkStats
	if n.networkStats != nil {
		statsCopy := *n.networkStats
		netStats = &statsCopy
	}

	return &NodeInfo{
		Name:           n.cfg.NodeName,
		Tier:           n.cfg.GetTier().String(),
		State:          n.state.String(),
		WalletAddress:  n.cfg.WalletAddress,
		StakedAmount:   formatTPIX(n.stakedAmount),
		PendingReward:  formatTPIX(n.pendingReward),
		TotalRewards:   formatTPIX(n.totalRewards),
		Uptime:         n.uptimeScore,
		UptimeSeconds:  uptimeSeconds,
		ConnectedPeers: n.connectedPeers,
		BlockHeight:    n.blockHeight,
		SyncProgress:   n.syncProgress,
		Version:        "1.0.0",
		StartedAt:      n.startedAt,
		LastRewardAt:   n.lastRewardAt,
		RegisteredAt:   n.registeredAt,
		Network:        netStats,
	}
}

// GetRewardHistory returns reward events
func (n *Node) GetRewardHistory() []RewardHistory {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.rewardHistory
}

// GetState returns current state
func (n *Node) GetState() NodeState {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.state
}

// syncLoop periodically syncs with the blockchain
func (n *Node) syncLoop(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			n.syncBlockchain()
		}
	}
}

// rewardLoop checks for rewards periodically
func (n *Node) rewardLoop(ctx context.Context) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			n.checkRewards()
		}
	}
}

// heartbeatLoop sends uptime heartbeat
func (n *Node) heartbeatLoop(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			n.sendHeartbeat()
		}
	}
}

func (n *Node) syncBlockchain() {
	n.mu.Lock()
	defer n.mu.Unlock()

	// Call eth_blockNumber on TPIX RPC
	// In production this uses go-ethereum ethclient
	n.blockHeight++
	n.syncProgress = 100.0
	n.connectedPeers = 4 // Will come from P2P layer

	if n.state == StateSyncing && n.syncProgress >= 100.0 {
		n.state = StateRunning
	}
}

func (n *Node) checkRewards() {
	n.mu.Lock()
	defer n.mu.Unlock()

	// Call pendingReward() on NodeRegistry contract
	// For now simulate accumulation
	rewardPerMin := big.NewInt(0)

	switch n.cfg.GetTier() {
	case config.TierValidator:
		rewardPerMin.SetString("7750000000000000000", 10) // ~7.75 TPIX/min
	case config.TierSentinel:
		rewardPerMin.SetString("1160000000000000000", 10) // ~1.16 TPIX/min
	case config.TierLight:
		rewardPerMin.SetString("310000000000000000", 10) // ~0.31 TPIX/min
	}

	n.pendingReward = new(big.Int).Add(n.pendingReward, rewardPerMin)

	n.log.Debugf("Pending reward: %s TPIX", formatTPIX(n.pendingReward))
}

func (n *Node) sendHeartbeat() {
	// Report uptime to monitoring oracle
	n.log.Debug("Heartbeat sent")
}

// UpdateNetworkStats updates network-wide statistics
func (n *Node) UpdateNetworkStats(stats *NetworkStats) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.networkStats = stats
}

// formatTPIX converts wei to TPIX string
func formatTPIX(wei *big.Int) string {
	if wei == nil {
		return "0"
	}
	ether := new(big.Float).Quo(
		new(big.Float).SetInt(wei),
		new(big.Float).SetInt(new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil)),
	)
	return fmt.Sprintf("%.4f", ether)
}
