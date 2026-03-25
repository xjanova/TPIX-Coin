import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';
import 'send_screen.dart';
import 'receive_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _balanceController;
  late AnimationController _orbController;
  late Animation<double> _balanceScale;

  @override
  void initState() {
    super.initState();
    _balanceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _balanceScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _balanceController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _balanceController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<WalletProvider>(
        builder: (context, wallet, _) => Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.5),
              radius: 1.5,
              colors: [Color(0xFF0C1929), AppTheme.bgDark],
            ),
          ),
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: wallet.refreshBalance,
              color: AppTheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildHeader(wallet),
                    const SizedBox(height: 24),
                    _buildBalanceCard(wallet),
                    const SizedBox(height: 24),
                    _buildActionButtons(context),
                    const SizedBox(height: 24),
                    _buildInfoCards(),
                    const SizedBox(height: 24),
                    _buildQuickLinks(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(WalletProvider wallet) {
    return Row(
      children: [
        // Avatar with glow
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12),
            ],
          ),
          child: ClipOval(
            child: Image.asset('assets/images/tpixlogo.webp', fit: BoxFit.contain),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TPIX Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            GestureDetector(
              onTap: () {
                if (wallet.address != null) {
                  Clipboard.setData(ClipboardData(text: wallet.address!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกที่อยู่แล้ว!'), backgroundColor: AppTheme.success, duration: Duration(seconds: 1)),
                  );
                }
              },
              child: Row(
                children: [
                  Text(wallet.shortAddress, style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 12, color: AppTheme.textMuted),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        // Network badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppTheme.success.withValues(alpha: 0.1),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 6, color: AppTheme.success),
              SizedBox(width: 4),
              Text('TPIX Chain', style: TextStyle(fontSize: 11, color: AppTheme.success, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(WalletProvider wallet) {
    return AnimatedBuilder(
      animation: _balanceScale,
      builder: (_, child) => Transform.scale(scale: _balanceScale.value, child: child),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF0E2A47), Color(0xFF0A1628)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(color: AppTheme.primary.withValues(alpha: 0.1), blurRadius: 40, spreadRadius: 5),
          ],
        ),
        child: Stack(
          children: [
            // Orbiting decoration
            Positioned(
              right: -10,
              top: -10,
              child: AnimatedBuilder(
                animation: _orbController,
                builder: (_, __) => Transform.rotate(
                  angle: _orbController.value * 2 * pi,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: CustomPaint(painter: _OrbPainter()),
                  ),
                ),
              ),
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ยอดคงเหลือ', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      wallet.formattedBalance,
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('TPIX', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '≈ \$${(wallet.balance * 0.18).toStringAsFixed(2)} USD',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildActionBtn(
          icon: Icons.arrow_upward_rounded,
          label: 'ส่ง',
          sublabel: 'Send',
          color: AppTheme.primary,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendScreen())),
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildActionBtn(
          icon: Icons.arrow_downward_rounded,
          label: 'รับ',
          sublabel: 'Receive',
          color: AppTheme.success,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiveScreen())),
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildActionBtn(
          icon: Icons.swap_horiz_rounded,
          label: 'แลก',
          sublabel: 'Swap',
          color: AppTheme.accent,
          onTap: () {}, // TODO: Swap screen
        )),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
              Text(sublabel, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCards() {
    return Column(
      children: [
        _buildInfoRow(Icons.speed, 'Block Time', '2 วินาที', AppTheme.success),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.local_gas_station, 'Gas Fee', 'ฟรี!', AppTheme.warm),
        const SizedBox(height: 10),
        _buildInfoRow(Icons.shield, 'Consensus', 'IBFT 2.0', AppTheme.accent),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: glassCard(borderRadius: 16),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildQuickLinks() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(borderRadius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ลิงก์', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          _buildLink('🌐', 'TPIX TRADE', 'https://tpix.online'),
          _buildLink('🔍', 'Explorer', TpixChain.explorerUrl),
          _buildLink('📖', 'Whitepaper', 'https://tpix.online/whitepaper'),
          _buildLink('📥', 'Master Node', 'https://tpix.online/masternode'),
        ],
      ),
    );
  }

  Widget _buildLink(String emoji, String label, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const Spacer(),
          Icon(Icons.open_in_new, size: 16, color: AppTheme.textMuted.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);

    final dotPaint = Paint()..color = AppTheme.primary.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(size.width / 2, 0), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
