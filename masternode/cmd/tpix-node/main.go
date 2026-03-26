package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"github.com/xjanova/tpix-masternode/config"
	"github.com/xjanova/tpix-masternode/internal/dashboard"
	"github.com/xjanova/tpix-masternode/internal/monitor"
	"github.com/xjanova/tpix-masternode/internal/node"
)

var (
	Version   = "1.0.0"
	BuildDate = "2026-03-22"
	cfgFile   string
	log       = logrus.New()
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "tpix-node",
		Short: "TPIX Master Node — Decentralized Blockchain Node",
		Long: `
╔══════════════════════════════════════════════════════╗
║         TPIX MASTER NODE v` + Version + `                      ║
║         Powered by TPIX Chain (ID: 4289)             ║
║         https://tpix.online                          ║
╚══════════════════════════════════════════════════════╝

Run a TPIX blockchain master node to earn rewards by
validating transactions and securing the network.

Node Tiers:
  Validator  - 10,000,000 TPIX stake  (15-20% APY, KYC required)
  Guardian   -  1,000,000 TPIX stake  (10-12% APY)
  Sentinel   -    100,000 TPIX stake  ( 7-9%  APY)
  Light      -     10,000 TPIX stake  (  4-6% APY)
`,
		Run: runNode,
	}

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file path")

	// Sub-commands
	rootCmd.AddCommand(initCmd())
	rootCmd.AddCommand(statusCmd())
	rootCmd.AddCommand(versionCmd())
	rootCmd.AddCommand(dashboardCmd())

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func runNode(cmd *cobra.Command, args []string) {
	cfg, err := config.LoadConfig(cfgFile)
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	setupLogger(cfg)

	log.Infof("═══════════════════════════════════════════")
	log.Infof("  TPIX Master Node v%s", Version)
	log.Infof("  Tier: %s", cfg.GetTier())
	log.Infof("  Chain: TPIX (ID: %d)", cfg.ChainID)
	log.Infof("  RPC: %s", cfg.ChainRPC)
	log.Infof("  Dashboard: http://localhost:%d", cfg.DashboardPort)
	log.Infof("═══════════════════════════════════════════")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start the node
	n, err := node.New(cfg, log)
	if err != nil {
		log.Fatalf("Failed to create node: %v", err)
	}

	if err := n.Start(ctx); err != nil {
		log.Fatalf("Failed to start node: %v", err)
	}

	// Start monitoring
	mon := monitor.New(cfg, n, log)
	go mon.Start(ctx)

	// Start dashboard
	dash := dashboard.New(cfg, n, mon, log)
	go dash.Start(ctx)

	log.Infof("Node running. Dashboard: http://localhost:%d", cfg.DashboardPort)
	log.Info("Press Ctrl+C to stop")

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	log.Info("Shutting down gracefully...")
	cancel()
	n.Stop()
	log.Info("Node stopped")
}

func initCmd() *cobra.Command {
	var tier string
	var wallet string
	var name string

	cmd := &cobra.Command{
		Use:   "init",
		Short: "Initialize a new master node",
		Run: func(cmd *cobra.Command, args []string) {
			cfg := config.DefaultConfig()
			cfg.Tier = tier
			cfg.WalletAddress = wallet
			if name != "" {
				cfg.NodeName = name
			}

			// Create data directories
			dirs := []string{
				cfg.DataDir,
				filepath.Join(cfg.DataDir, "logs"),
				filepath.Join(cfg.DataDir, "data"),
				cfg.KeystorePath,
			}
			for _, dir := range dirs {
				os.MkdirAll(dir, 0755)
			}

			configPath := filepath.Join(cfg.DataDir, "tpix-node.yaml")
			if err := config.SaveConfig(cfg, configPath); err != nil {
				log.Fatalf("Failed to save config: %v", err)
			}

			fmt.Println("╔══════════════════════════════════════════╗")
			fmt.Println("║   TPIX Master Node Initialized!          ║")
			fmt.Println("╚══════════════════════════════════════════╝")
			fmt.Printf("  Config:  %s\n", configPath)
			fmt.Printf("  Data:    %s\n", cfg.DataDir)
			fmt.Printf("  Tier:    %s\n", cfg.GetTier())
			fmt.Printf("  Wallet:  %s\n", cfg.WalletAddress)
			fmt.Println()
			fmt.Println("Next steps:")
			fmt.Println("  1. Edit config if needed:", configPath)
			fmt.Println("  2. Start your node: tpix-node --config", configPath)
			fmt.Println("  3. Open dashboard: http://localhost:3847")
		},
	}

	cmd.Flags().StringVar(&tier, "tier", "light", "Node tier: validator, sentinel, light")
	cmd.Flags().StringVar(&wallet, "wallet", "", "Your TPIX wallet address")
	cmd.Flags().StringVar(&name, "name", "", "Node display name")

	return cmd
}

func statusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show node status",
		Run: func(cmd *cobra.Command, args []string) {
			cfg, err := config.LoadConfig(cfgFile)
			if err != nil {
				log.Fatalf("Failed to load config: %v", err)
			}

			fmt.Println("╔══════════════════════════════════════════╗")
			fmt.Println("║   TPIX Master Node Status                ║")
			fmt.Println("╚══════════════════════════════════════════╝")
			fmt.Printf("  Name:     %s\n", cfg.NodeName)
			fmt.Printf("  Tier:     %s\n", cfg.GetTier())
			fmt.Printf("  Wallet:   %s\n", cfg.WalletAddress)
			fmt.Printf("  Chain:    TPIX (ID: %d)\n", cfg.ChainID)
			fmt.Printf("  RPC:      %s\n", cfg.ChainRPC)
			fmt.Printf("  OS:       %s/%s\n", runtime.GOOS, runtime.GOARCH)
		},
	}
}

func versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Show version info",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("TPIX Master Node v%s\n", Version)
			fmt.Printf("Build Date: %s\n", BuildDate)
			fmt.Printf("Go: %s\n", runtime.Version())
			fmt.Printf("OS/Arch: %s/%s\n", runtime.GOOS, runtime.GOARCH)
		},
	}
}

func dashboardCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "dashboard",
		Short: "Open the web dashboard in browser",
		Run: func(cmd *cobra.Command, args []string) {
			cfg, err := config.LoadConfig(cfgFile)
			if err != nil {
				log.Fatalf("Failed to load config: %v", err)
			}
			url := fmt.Sprintf("http://localhost:%d", cfg.DashboardPort)
			fmt.Printf("Opening dashboard: %s\n", url)
			openBrowser(url)
		},
	}
}

func setupLogger(cfg *config.Config) {
	level, err := logrus.ParseLevel(cfg.LogLevel)
	if err != nil {
		level = logrus.InfoLevel
	}
	log.SetLevel(level)
	log.SetFormatter(&logrus.TextFormatter{
		FullTimestamp:   true,
		TimestampFormat: "2006-01-02 15:04:05",
	})
}

func openBrowser(url string) {
	var cmd string
	var args []string

	switch runtime.GOOS {
	case "windows":
		cmd = "cmd"
		args = []string{"/c", "start", url}
	case "darwin":
		cmd = "open"
		args = []string{url}
	default:
		cmd = "xdg-open"
		args = []string{url}
	}

	proc := &os.ProcAttr{Files: []*os.File{os.Stdin, os.Stdout, os.Stderr}}
	p, err := os.StartProcess(cmd, append([]string{cmd}, args...), proc)
	if err == nil {
		p.Release()
	}
}
