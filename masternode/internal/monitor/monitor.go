package monitor

import (
	"context"
	"runtime"
	"sync"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
	"github.com/sirupsen/logrus"
	"github.com/xjanova/tpix-masternode/config"
	"github.com/xjanova/tpix-masternode/internal/node"
)

// SystemMetrics holds server resource metrics
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
	GoRoutines    int     `json:"goroutines"`
	OS            string  `json:"os"`
	Arch          string  `json:"arch"`
	Uptime        int64   `json:"uptime_seconds"`
}

// Monitor handles system monitoring and health checks
type Monitor struct {
	cfg     *config.Config
	node    *node.Node
	log     *logrus.Logger
	metrics *SystemMetrics
	mu      sync.RWMutex
	started time.Time
}

// New creates a new Monitor
func New(cfg *config.Config, n *node.Node, log *logrus.Logger) *Monitor {
	return &Monitor{
		cfg:     cfg,
		node:    n,
		log:     log,
		metrics: &SystemMetrics{},
		started: time.Now(),
	}
}

// Start begins monitoring
func (m *Monitor) Start(ctx context.Context) {
	m.log.Info("System monitor started")
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	// Collect initial metrics
	m.collect()

	for {
		select {
		case <-ctx.Done():
			m.log.Info("Monitor stopped")
			return
		case <-ticker.C:
			m.collect()
		}
	}
}

// GetMetrics returns current system metrics
func (m *Monitor) GetMetrics() *SystemMetrics {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Update uptime
	metrics := *m.metrics
	metrics.Uptime = int64(time.Since(m.started).Seconds())
	return &metrics
}

func (m *Monitor) collect() {
	m.mu.Lock()
	defer m.mu.Unlock()

	// CPU
	cpuPercent, err := cpu.Percent(time.Second, false)
	if err == nil && len(cpuPercent) > 0 {
		m.metrics.CPUPercent = cpuPercent[0]
	}

	// Memory
	memInfo, err := mem.VirtualMemory()
	if err == nil {
		m.metrics.MemoryPercent = memInfo.UsedPercent
		m.metrics.MemoryUsedMB = memInfo.Used / 1024 / 1024
		m.metrics.MemoryTotalMB = memInfo.Total / 1024 / 1024
	}

	// Disk
	diskPath := "/"
	if runtime.GOOS == "windows" {
		diskPath = "C:"
	}
	diskInfo, err := disk.Usage(diskPath)
	if err == nil {
		m.metrics.DiskPercent = diskInfo.UsedPercent
		m.metrics.DiskUsedGB = diskInfo.Used / 1024 / 1024 / 1024
		m.metrics.DiskTotalGB = diskInfo.Total / 1024 / 1024 / 1024
	}

	// Network
	netIO, err := net.IOCounters(false)
	if err == nil && len(netIO) > 0 {
		m.metrics.NetworkInMB = float64(netIO[0].BytesRecv) / 1024 / 1024
		m.metrics.NetworkOutMB = float64(netIO[0].BytesSent) / 1024 / 1024
	}

	// Go runtime
	m.metrics.GoRoutines = runtime.NumGoroutine()
	m.metrics.OS = runtime.GOOS
	m.metrics.Arch = runtime.GOARCH
	m.metrics.Uptime = int64(time.Since(m.started).Seconds())
}
