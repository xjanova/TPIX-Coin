import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/themes/tokens.dart';
import '../core/theme.dart';
import '../core/themes/theme_bundle.dart';
import '../services/price_service.dart';
import 'tpix_coin_logo.dart';

/// Beautiful gradient area chart for TPIX price history
///
/// ข้อมูลกราฟมาจาก API แท่งเทียนของ TPIX DEX เท่านั้น — ดึงไม่ได้ = บอกว่า "ไม่พร้อมใช้งาน"
/// ไม่มีการสุ่ม/เติมจุดราคาเองอีกต่อไป (ของเดิมสุ่มกราฟ 7 วันขึ้นมาเองตอนติดตั้ง)
class PriceChartWidget extends StatefulWidget {
  /// ราคาปัจจุบัน — null = ยังไม่เคยได้ราคาจริง
  final double? currentPrice;

  /// ราคาที่โชว์เป็นราคาเก่า (ดึงล่าสุดไม่สำเร็จ)
  final bool isPriceStale;

  /// ยอด TPIX — null = ยังไม่รู้ยอด (ไม่คำนวณมูลค่าพอร์ต)
  final double? balanceTPIX;

  const PriceChartWidget({
    super.key,
    required this.currentPrice,
    required this.balanceTPIX,
    this.isPriceStale = false,
  });

  @override
  State<PriceChartWidget> createState() => _PriceChartWidgetState();
}

class _PriceChartWidgetState extends State<PriceChartWidget>
    with SingleTickerProviderStateMixin {
  List<PricePoint> _points = [];
  int _selectedDays = 7;
  bool _isLoading = true;
  bool _unavailable = false;
  double? _changePercent;
  int _requestId = 0; // กันผลของช่วงเก่ามาทับช่วงใหม่เมื่อกดสลับเร็วๆ
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
    final request = ++_requestId;
    final points =
        await PriceService.fetchChart(ChartRange.fromDays(_selectedDays));
    if (!mounted || request != _requestId) return;
    setState(() {
      _unavailable = points == null;
      _points = points ?? const [];
      _changePercent =
          points == null ? null : PriceService.changePercent(points);
      _isLoading = false;
    });
    if (_points.length >= 2) _animController.forward(from: 0);
  }

  void _changePeriod(int days) {
    if (_selectedDays == days) return;
    setState(() {
      _selectedDays = days;
      _isLoading = true;
    });
    _loadData();
  }

  void _retry() {
    setState(() => _isLoading = true);
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final change = _changePercent;
    final isPositive = (change ?? 0) >= 0;
    final changeColor = isPositive ? AppTheme.success : AppTheme.danger;
    final changeIcon = isPositive ? Icons.trending_up : Icons.trending_down;
    final price = widget.currentPrice;
    final balance = widget.balanceTPIX;
    final portfolioValue =
        (price != null && balance != null) ? balance * price : null;

    // สีการ์ดเดิมฮาร์ดโค้ดกรมท่าเข้ม ไม่สนธีม → บนธีมสว่างกลายเป็นการ์ดดำบนพื้นขาว
    // ต้องอ่านจากธีมปัจจุบันเสมอ
    final c = AppColors.of(context);
    final t = TpixThemeExtension.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.cardRadius),
        gradient: LinearGradient(
          colors: isDark
              ? [
                  Color.lerp(t.card, c.brandPrimary, 0.10)!,
                  Color.lerp(t.card, Colors.black, 0.12)!,
                ]
              : [
                  Colors.white,
                  Color.lerp(Colors.white, c.brandPrimary, 0.10)!,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
            color: c.brandPrimary.withValues(alpha: isDark ? 0.22 : 0.18)),
        boxShadow: [
          BoxShadow(
            color: c.brandPrimary.withValues(alpha: isDark ? 0.10 : 0.14),
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
              // Expanded — ราคา/เปอร์เซ็นต์ยาวขึ้นตามค่าจริง ต้องไม่ดันป้ายขวาตกขอบ
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        TpixCoinLogo(size: 20),
                        SizedBox(width: TpixGap.sm),
                        Text(
                          'TPIX/USD',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TpixGap.xs),
                    Text(
                      price != null ? '\$${formatUsdPrice(price)}' : '—',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    // ไม่มีราคา / ราคาเก่า — บอกตรงๆ ไม่ปล่อยให้เข้าใจว่าเป็นราคาสด
                    if (price == null || widget.isPriceStale)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 12, color: AppTheme.warm),
                            const SizedBox(width: TpixGap.xs),
                            Flexible(
                              child: Text(
                                l.t(price == null
                                    ? 'price.unavailable'
                                    : 'price.stale'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.warm),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: TpixGap.sm),
              // Change badge — มีเฉพาะเมื่อกราฟมีข้อมูลจริงพอคำนวณ
              if (change != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TpixRadius.sm),
                    color: changeColor.withValues(alpha: 0.12),
                    border: Border.all(
                        color: changeColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(changeIcon, color: changeColor, size: 14),
                      const SizedBox(width: TpixGap.xs),
                      Text(
                        '${isPositive ? '+' : ''}${change.toStringAsFixed(2)}%',
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
              'Portfolio: ${portfolioValue != null ? '\$${_formatPortfolio(portfolioValue)}' : '—'}',
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
                : _unavailable
                    ? _buildChartMessage(
                        l.t('price.chartUnavailable'),
                        onRetry: _retry,
                        retryLabel: l.t('price.retry'),
                      )
                    : _points.length < 2
                        ? _buildChartMessage(l.t('price.notEnoughData'))
                        : AnimatedBuilder(
                            animation: _animProgress,
                            builder: (_, _) => CustomPaint(
                              size: const Size(double.infinity, 140),
                              painter: _ChartPainter(
                                points: _points,
                                progress: _animProgress.value,
                                isPositive: isPositive,
                              ),
                            ),
                          ),
          ),

          const SizedBox(height: TpixGap.md),

          // Period selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _periodButton('24H', 1),
              const SizedBox(width: TpixGap.sm),
              _periodButton('7D', 7),
              const SizedBox(width: TpixGap.sm),
              _periodButton('30D', 30),
              const SizedBox(width: TpixGap.sm),
              _periodButton('90D', 90),
            ],
          ),
        ],
      ),
    );
  }

  /// ข้อความแทนกราฟ (ดึงไม่ได้ / ข้อมูลยังไม่พอ) — ไม่วาดเส้นปลอมแทน
  Widget _buildChartMessage(String text,
      {VoidCallback? onRetry, String? retryLabel}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted.withValues(alpha: 0.7),
            ),
          ),
          if (onRetry != null && retryLabel != null)
            TextButton(
              onPressed: onRetry,
              child: Text(retryLabel,
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.primary)),
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
          borderRadius: BorderRadius.circular(TpixRadius.sm),
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

/// ราคาต่ำกว่า 1 เซนต์ต้องโชว์ทศนิยมมากขึ้น ไม่งั้นกลายเป็น $0.0000
String formatUsdPrice(double price) =>
    price >= 0.01 ? price.toStringAsFixed(4) : price.toStringAsPrecision(4);
