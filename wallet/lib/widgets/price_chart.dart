import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/price_service.dart';

/// Beautiful gradient area chart for TPIX price history
class PriceChartWidget extends StatefulWidget {
  final double currentPrice;
  final double balanceTPIX;

  const PriceChartWidget({
    super.key,
    required this.currentPrice,
    required this.balanceTPIX,
  });

  @override
  State<PriceChartWidget> createState() => _PriceChartWidgetState();
}

class _PriceChartWidgetState extends State<PriceChartWidget>
    with SingleTickerProviderStateMixin {
  List<PricePoint> _points = [];
  int _selectedDays = 7;
  bool _isLoading = true;
  double _changePercent = 0;
  late AnimationController _animController;
  late Animation<double> _animProgress;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animProgress = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final points = await PriceService.getPriceHistory(days: _selectedDays);
    final change = await PriceService.getPriceChange(days: _selectedDays);
    if (!mounted) return;
    setState(() {
      _points = points;
      _changePercent = change;
      _isLoading = false;
    });
    _animController.forward(from: 0);
  }

  void _changePeriod(int days) {
    if (_selectedDays == days) return;
    setState(() {
      _selectedDays = days;
      _isLoading = true;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = _changePercent >= 0;
    final changeColor = isPositive ? AppTheme.success : AppTheme.danger;
    final changeIcon = isPositive ? Icons.trending_up : Icons.trending_down;
    final portfolioValue = widget.balanceTPIX * widget.currentPrice;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0E2A47).withValues(alpha: 0.9),
            const Color(0xFF0A1628).withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border:
            Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.06),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Price + Change
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipOval(
                        child: Image.asset(
                          'assets/images/logowallet.png',
                          width: 20,
                          height: 20,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'TPIX/USD',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${widget.currentPrice.toStringAsFixed(4)}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Change badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: changeColor.withValues(alpha: 0.12),
                  border: Border.all(
                      color: changeColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(changeIcon, color: changeColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${isPositive ? '+' : ''}${_changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: changeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Portfolio value
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              'Portfolio: \$${_formatPortfolio(portfolioValue)}',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ),

          // Chart area
          SizedBox(
            height: 140,
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : _points.length < 2
                    ? Center(
                        child: Text(
                          'Loading chart data...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : AnimatedBuilder(
                        animation: _animProgress,
                        builder: (_, __) => CustomPaint(
                          size: const Size(double.infinity, 140),
                          painter: _ChartPainter(
                            points: _points,
                            progress: _animProgress.value,
                            isPositive: isPositive,
                          ),
                        ),
                      ),
          ),

          const SizedBox(height: 12),

          // Period selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _periodButton('24H', 1),
              const SizedBox(width: 8),
              _periodButton('7D', 7),
              const SizedBox(width: 8),
              _periodButton('30D', 30),
              const SizedBox(width: 8),
              _periodButton('90D', 90),
            ],
          ),
        ],
      ),
    );
  }

  Widget _periodButton(String label, int days) {
    final isSelected = _selectedDays == days;
    return GestureDetector(
      onTap: () => _changePeriod(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppTheme.primary : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  String _formatPortfolio(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
    return value.toStringAsFixed(2);
  }
}

/// Custom painter for gradient area chart
class _ChartPainter extends CustomPainter {
  final List<PricePoint> points;
  final double progress;
  final bool isPositive;

  _ChartPainter({
    required this.points,
    required this.progress,
    required this.isPositive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final prices = points.map((p) => p.price).toList();
    final minPrice = prices.reduce(min);
    final maxPrice = prices.reduce(max);
    final priceRange = maxPrice - minPrice;
    final effectiveRange = priceRange == 0 ? 1.0 : priceRange;

    // Padding
    const leftPad = 0.0;
    const rightPad = 0.0;
    const topPad = 8.0;
    const bottomPad = 20.0;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;

    // Generate points
    final chartPoints = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = leftPad + (i / (points.length - 1)) * chartWidth;
      final normalizedY = (points[i].price - minPrice) / effectiveRange;
      final y = topPad + chartHeight - (normalizedY * chartHeight);
      chartPoints.add(Offset(x, y));
    }

    // Limit drawn points based on animation progress
    final visibleCount = (chartPoints.length * progress).ceil().clamp(2, chartPoints.length);
    final visiblePoints = chartPoints.sublist(0, visibleCount);

    // Build smooth path using cubic bezier
    final path = Path();
    path.moveTo(visiblePoints[0].dx, visiblePoints[0].dy);

    for (int i = 1; i < visiblePoints.length; i++) {
      final p0 = visiblePoints[i - 1];
      final p1 = visiblePoints[i];
      final cpx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cpx, p0.dy, cpx, p1.dy, p1.dx, p1.dy);
    }

    // Draw gradient fill
    final fillPath = Path.from(path);
    fillPath.lineTo(visiblePoints.last.dx, size.height - bottomPad);
    fillPath.lineTo(visiblePoints.first.dx, size.height - bottomPad);
    fillPath.close();

    final gradientColor = isPositive ? AppTheme.success : AppTheme.danger;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          gradientColor.withValues(alpha: 0.25),
          gradientColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = gradientColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Draw glow on line
    final glowPaint = Paint()
      ..color = gradientColor.withValues(alpha: 0.3)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    // Draw current price dot (last visible point)
    if (progress >= 0.95) {
      final lastPoint = visiblePoints.last;
      // Outer glow
      canvas.drawCircle(
        lastPoint,
        8,
        Paint()..color = gradientColor.withValues(alpha: 0.2),
      );
      // Inner dot
      canvas.drawCircle(
        lastPoint,
        4,
        Paint()..color = gradientColor,
      );
      // White center
      canvas.drawCircle(
        lastPoint,
        2,
        Paint()..color = Colors.white,
      );
    }

    // Draw min/max labels
    if (progress >= 0.8) {
      final textOpacity = ((progress - 0.8) / 0.2).clamp(0.0, 1.0);

      // Max price label
      _drawPriceLabel(
        canvas,
        '\$${maxPrice.toStringAsFixed(4)}',
        Offset(size.width - 4, topPad),
        textOpacity,
      );
      // Min price label
      _drawPriceLabel(
        canvas,
        '\$${minPrice.toStringAsFixed(4)}',
        Offset(size.width - 4, size.height - bottomPad - 12),
        textOpacity,
      );
    }

    // Draw subtle grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 4; i++) {
      final y = topPad + (chartHeight / 4) * i;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
    }
  }

  void _drawPriceLabel(Canvas canvas, String text, Offset position, double opacity) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          color: AppTheme.textMuted.withValues(alpha: 0.6 * opacity),
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(position.dx - tp.width, position.dy));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.points.length != points.length ||
      oldDelegate.isPositive != isPositive;
}
