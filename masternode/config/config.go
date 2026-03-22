package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/spf13/viper"
)

// NodeTier represents the master node tier
type NodeTier int

const (
	TierValidator NodeTier = iota // 1M TPIX stake
	TierSentinel                  // 100K TPIX stake
	TierLight                     // 10K TPIX stake
)

func (t NodeTier) String() string {
	switch t {
	case TierValidator:
		return "Validator"
	case TierSentinel:
		return "Sentinel"
	case TierLight:
		return "Light"
	default:
		return "Unknown"
	}
}

// Config holds all node configuration
type Config struct {
	// Node identity
	NodeName string `mapstructure:"node_name"`
	Tier     string `mapstructure:"tier"` // "validator", "sentinel", "light"
	Endpoint string `mapstructure:"endpoint"`

	// Wallet
	WalletAddress string `mapstructure:"wallet_address"`
	KeystorePath  string `mapstructure:"keystore_path"`

	// Network
	ChainRPC       string `mapstructure:"chain_rpc"`
	ChainID        int64  `mapstructure:"chain_id"`
	RegistryAddr   string `mapstructure:"registry_address"`
	P2PPort        int    `mapstructure:"p2p_port"`
	RPCPort        int    `mapstructure:"rpc_port"`
	DashboardPort  int    `mapstructure:"dashboard_port"`

	// Polygon Edge
	PolygonEdgePath string `mapstructure:"polygon_edge_path"`
	DataDir         string `mapstructure:"data_dir"`

	// Performance
	MaxPeers       int  `mapstructure:"max_peers"`
	SyncMode       string `mapstructure:"sync_mode"` // "full", "light"
	EnableMetrics  bool `mapstructure:"enable_metrics"`
	MetricsPort    int  `mapstructure:"metrics_port"`

	// Logging
	LogLevel string `mapstructure:"log_level"`
	LogFile  string `mapstructure:"log_file"`

	// Auto-update
	AutoUpdate     bool   `mapstructure:"auto_update"`
	UpdateChannel  string `mapstructure:"update_channel"` // "stable", "beta"
}

// DefaultConfig returns default configuration
func DefaultConfig() *Config {
	homeDir, _ := os.UserHomeDir()
	dataDir := filepath.Join(homeDir, ".tpix-node")

	return &Config{
		NodeName:       fmt.Sprintf("tpix-node-%s", randomID()),
		Tier:           "light",
		Endpoint:       "",
		WalletAddress:  "",
		KeystorePath:   filepath.Join(dataDir, "keystore"),
		ChainRPC:       "https://rpc.tpix.online",
		ChainID:        4289,
		RegistryAddr:   "",
		P2PPort:        30303,
		RPCPort:        8545,
		DashboardPort:  3847,
		PolygonEdgePath: findPolygonEdge(),
		DataDir:        dataDir,
		MaxPeers:       50,
		SyncMode:       "full",
		EnableMetrics:  true,
		MetricsPort:    9090,
		LogLevel:       "info",
		LogFile:        filepath.Join(dataDir, "logs", "node.log"),
		AutoUpdate:     true,
		UpdateChannel:  "stable",
	}
}

// LoadConfig loads configuration from file
func LoadConfig(path string) (*Config, error) {
	cfg := DefaultConfig()

	if path != "" {
		viper.SetConfigFile(path)
	} else {
		viper.SetConfigName("tpix-node")
		viper.SetConfigType("yaml")
		viper.AddConfigPath(".")
		viper.AddConfigPath(filepath.Join(cfg.DataDir))
		if runtime.GOOS != "windows" {
			viper.AddConfigPath("/etc/tpix-node")
		}
	}

	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("error reading config: %w", err)
		}
		// Use defaults if no config file found
	}

	if err := viper.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("error parsing config: %w", err)
	}

	return cfg, nil
}

// SaveConfig saves configuration to file
func SaveConfig(cfg *Config, path string) error {
	viper.Set("node_name", cfg.NodeName)
	viper.Set("tier", cfg.Tier)
	viper.Set("endpoint", cfg.Endpoint)
	viper.Set("wallet_address", cfg.WalletAddress)
	viper.Set("keystore_path", cfg.KeystorePath)
	viper.Set("chain_rpc", cfg.ChainRPC)
	viper.Set("chain_id", cfg.ChainID)
	viper.Set("registry_address", cfg.RegistryAddr)
	viper.Set("p2p_port", cfg.P2PPort)
	viper.Set("rpc_port", cfg.RPCPort)
	viper.Set("dashboard_port", cfg.DashboardPort)
	viper.Set("polygon_edge_path", cfg.PolygonEdgePath)
	viper.Set("data_dir", cfg.DataDir)
	viper.Set("max_peers", cfg.MaxPeers)
	viper.Set("sync_mode", cfg.SyncMode)
	viper.Set("enable_metrics", cfg.EnableMetrics)
	viper.Set("metrics_port", cfg.MetricsPort)
	viper.Set("log_level", cfg.LogLevel)
	viper.Set("log_file", cfg.LogFile)
	viper.Set("auto_update", cfg.AutoUpdate)
	viper.Set("update_channel", cfg.UpdateChannel)

	return viper.WriteConfigAs(path)
}

// GetTier converts string tier to NodeTier
func (c *Config) GetTier() NodeTier {
	switch c.Tier {
	case "validator":
		return TierValidator
	case "sentinel":
		return TierSentinel
	default:
		return TierLight
	}
}

func randomID() string {
	b := make([]byte, 4)
	// Simple random from timestamp
	for i := range b {
		b[i] = "abcdefghijklmnopqrstuvwxyz0123456789"[int(os.Getpid()+i)%36]
	}
	return string(b)
}

func findPolygonEdge() string {
	// Try common locations
	paths := []string{
		"polygon-edge",
		"/usr/local/bin/polygon-edge",
		"/usr/bin/polygon-edge",
	}
	if runtime.GOOS == "windows" {
		paths = append([]string{
			"polygon-edge.exe",
			`C:\Program Files\polygon-edge\polygon-edge.exe`,
		}, paths...)
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "polygon-edge"
}
