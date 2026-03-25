// TPIX Master Node - Wails Frontend
// ===================================

// Tab switching
function showTab(name) {
    ['dashboard', 'network', 'rewards', 'settings'].forEach(t => {
        document.getElementById('page-' + t).style.display = t === name ? 'block' : 'none';
        document.getElementById('tab-' + t).classList.toggle('active', t === name);
    });
}

// Start/Stop node
async function startNode() {
    try {
        const result = await window.go.main.App.StartNode();
        if (result.startsWith('Error')) {
            alert(result);
            return;
        }
        document.getElementById('btn-start').style.display = 'none';
        document.getElementById('btn-stop').style.display = 'inline-flex';
        updateStatusBadge(true);
    } catch (e) {
        alert('Failed to start: ' + e);
    }
}

async function stopNode() {
    try {
        await window.go.main.App.StopNode();
        document.getElementById('btn-start').style.display = 'inline-flex';
        document.getElementById('btn-stop').style.display = 'none';
        updateStatusBadge(false);
    } catch (e) {
        alert('Failed to stop: ' + e);
    }
}

// Save settings
async function saveConfig() {
    const cfg = {
        node_name: document.getElementById('cfg-name').value,
        wallet_address: document.getElementById('cfg-wallet').value,
        tier: document.getElementById('cfg-tier').value,
        chain_rpc: document.getElementById('cfg-rpc').value,
        chain_id: 4289,
        dashboard_port: 3847,
        p2p_port: 30303,
        max_peers: 50,
        log_level: 'info',
        auto_update: true,
    };

    try {
        const result = await window.go.main.App.SaveConfig(cfg);
        alert(result);
        loadConfig();
    } catch (e) {
        alert('Error: ' + e);
    }
}

// Load config into form
async function loadConfig() {
    try {
        const cfg = await window.go.main.App.GetConfig();
        document.getElementById('cfg-name').value = cfg.node_name || '';
        document.getElementById('cfg-wallet').value = cfg.wallet_address || '';
        document.getElementById('cfg-tier').value = cfg.tier || 'Light';
        document.getElementById('cfg-rpc').value = cfg.chain_rpc || 'https://rpc.tpix.online';

        document.getElementById('node-name-h').textContent = cfg.node_name || 'TPIX Master Node';
        document.getElementById('node-tier-sub').textContent = (cfg.tier || 'Light') + ' Node \u00b7 Chain ' + (cfg.chain_id || 4289);
    } catch (e) {
        console.error('Failed to load config:', e);
    }
}

// Update status badge
function updateStatusBadge(running) {
    const badge = document.getElementById('status-mini');
    const dot = document.getElementById('status-dot-mini');
    const text = document.getElementById('status-text-mini');

    if (running) {
        badge.className = 'status-badge online';
        dot.className = 'status-dot on';
        text.textContent = 'Running';
    } else {
        badge.className = 'status-badge offline';
        dot.className = 'status-dot off';
        text.textContent = 'Stopped';
    }
}

// Format helpers
function fmt(n) { return n != null ? Number(n).toLocaleString() : '—'; }
function fmtDur(s) {
    if (!s) return '—';
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    if (d > 0) return d + 'd ' + h + 'h ' + m + 'm';
    if (h > 0) return h + 'h ' + m + 'm';
    return m + 'm ' + (s % 60) + 's';
}

// Poll for updates (fallback if events not working)
async function pollUpdates() {
    try {
        const status = await window.go.main.App.GetNodeStatus();
        const metrics = await window.go.main.App.GetSystemMetrics();
        const network = await window.go.main.App.GetNetworkInfo();
        applyUpdate(status, metrics, network);
    } catch (e) { /* silent */ }
}

function applyUpdate(s, m, n) {
    if (!s) return;

    // Status
    updateStatusBadge(s.running);
    document.getElementById('staked').textContent = s.staked_amount || '0.0000';
    document.getElementById('pending').textContent = s.pending_reward || '0.0000';
    document.getElementById('earned').textContent = s.total_rewards || '0.0000';
    document.getElementById('uptime').textContent = (s.uptime_percent || 0).toFixed(1) + '%';
    document.getElementById('uptime-dur').textContent = fmtDur(s.uptime_seconds);
    document.getElementById('block-height').textContent = fmt(s.block_height);
    document.getElementById('peers').textContent = s.connected_peers || 0;
    document.getElementById('sync').textContent = s.running ? (s.sync_progress || 100) + '%' : '—';
    document.getElementById('version').textContent = s.version || '1.0.0';

    // Buttons
    document.getElementById('btn-start').style.display = s.running ? 'none' : 'inline-flex';
    document.getElementById('btn-stop').style.display = s.running ? 'inline-flex' : 'none';

    // Metrics
    if (m) {
        document.getElementById('cpu').textContent = (m.cpu_percent || 0).toFixed(1) + '%';
        document.getElementById('cpu-bar').style.width = Math.min(m.cpu_percent || 0, 100) + '%';
        document.getElementById('mem').textContent = (m.memory_used_mb || 0) + 'MB / ' + (m.memory_total_mb || 0) + 'MB';
        document.getElementById('mem-bar').style.width = Math.min(m.memory_percent || 0, 100) + '%';
        document.getElementById('disk').textContent = (m.disk_used_gb || 0) + 'GB / ' + (m.disk_total_gb || 0) + 'GB';
        document.getElementById('disk-bar').style.width = Math.min(m.disk_percent || 0, 100) + '%';
        document.getElementById('os-info').textContent = (m.os || '—') + ' / ' + (m.arch || '—');
    }

    // Network
    if (n) {
        document.getElementById('n-total').textContent = n.total_nodes || 0;
        document.getElementById('n-val').textContent = n.validator_nodes || 0;
        document.getElementById('n-sent').textContent = n.sentinel_nodes || 0;
        document.getElementById('n-light').textContent = n.light_nodes || 0;
        document.getElementById('n-staked').textContent = n.total_staked || '0';
        document.getElementById('n-distrib').textContent = n.total_distributed || '0';
        document.getElementById('reward-year').textContent = 'Year ' + (n.current_year || 1);
        document.getElementById('block-reward').textContent = (n.block_reward || '25.5') + ' TPIX';
    }
}

// Listen for Wails events (real-time push from Go)
if (window.runtime) {
    window.runtime.EventsOn('node:update', (data) => {
        applyUpdate(data.status, data.metrics, data.network);
    });
    window.runtime.EventsOn('node:started', () => updateStatusBadge(true));
    window.runtime.EventsOn('node:stopped', () => updateStatusBadge(false));
}

// Initial load
loadConfig();
setInterval(pollUpdates, 3000);
