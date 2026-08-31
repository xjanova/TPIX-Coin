/// TPIX Wallet — Liquid Nav Bar
/// แถบเมนูล่างลอยได้ สไตล์ 3D soft-body: มีมิติจากเงาซ้อนชั้น + ไฮไลต์ผิวบน
/// ตรงกลางเป็นปุ่มสแกนวงกลมใหญ่ยกนูนขึ้นมา (รับ/จ่าย)
///
/// อ่านสีจาก TpixThemeExtension ทั้งหมด → ใช้ได้กับทุกธีม
/// (คลาสสิก/ลิควิด/ซินธ์เวฟ/เทอร์มินัล) โดยไม่ต้องแก้อะไร
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import '../core/themes/theme_bundle.dart';
import '../core/themes/widgets/luxe_texture.dart';

/// รายการเมนูหนึ่งช่อง
class LiquidNavItem {
  final IconData icon;
  final IconData activeIcon;

  /// ไอคอนเจลลี่ 3D — ถ้ามี ใช้แทนไอคอนเวกเตอร์
  /// วัดแล้วอ่านออกตั้งแต่ 28px ขึ้นไป ต่ำกว่านั้นกลายเป็นก้อนเบลอ
  final String? assetIcon;

  final String label;
  final VoidCallback onTap;

  const LiquidNavItem({
    required this.icon,
    required this.activeIcon,
    this.assetIcon,
    required this.label,
    required this.onTap,
  });
}

class LiquidNavBar extends StatefulWidget {
  /// กุญแจถาวรของปุ่มสแกนกลาง — ใช้ค้นในเทสต์
  /// อย่าค้นด้วยไอคอน เพราะไอคอนเปลี่ยนได้ (เคยเปลี่ยนจาก Material icon เป็นไฟล์ภาพมาแล้ว)
  static const Key scanButtonKey = Key('nav-scan-button');

  /// ต้องมี 4 ช่อง (ซ้าย 2 / ขวา 2) — ปุ่มสแกนแทรกตรงกลางเอง
  final List<LiquidNavItem> items;

  /// index ของช่องที่ active (-1 = ไม่มี)
  final int currentIndex;

  /// กดปุ่มสแกนตรงกลาง
  final VoidCallback onScanTap;

  /// ป้ายใต้ปุ่มกลาง (เช่น "สแกน")
  final String scanLabel;

  const LiquidNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onScanTap,
    required this.scanLabel,
  });

  static const double barHeight = 64;
  static const double scanSize = 66;

  /// ปุ่มสแกนจมลงไปในแถบเท่าไร (สัดส่วนของขนาดปุ่ม)
  /// ค่าเดิม 0.42 ทำให้วงกลมโผล่พ้นแถบ 60 จาก 66px = 91% ของใบ
  /// ซึ่งไม่ใช่ "คร่อมแถบ" แต่เป็น "ลอยอยู่เหนือแถบ"
  /// 0.82 = โผล่ราวครึ่งใบ ซึ่งเป็นสัดส่วนของปุ่มกลางที่คุ้นตา
  static const double scanSink = 0.82;

  /// ความสูงที่แถบนี้กินจริง (ไม่รวม safe-area ล่าง)
  /// ใช้เว้นที่ว่างท้ายเนื้อหาในหน้าที่ตั้ง `extendBody: true`
  /// ไม่งั้นรายการสุดท้ายจะถูกแถบบัง — และยิ่งผู้ใช้ตั้งตัวอักษรใหญ่ยิ่งบังมาก
  static double heightFor(BuildContext context) {
    final labelHeight = MediaQuery.textScalerOf(context).scale(10) * 1.35;
    return barHeight - scanSize * scanSink + (scanSize + 26) + 1 + labelHeight;
  }

  @override
  State<LiquidNavBar> createState() => _LiquidNavBarState();
}

class _LiquidNavBarState extends State<LiquidNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _scanPressed = false;

  static const double _barHeight = LiquidNavBar.barHeight;
  static const double _scanSize = LiquidNavBar.scanSize;

  @override
  void initState() {
    super.initState();
    // วงแหวนรอบปุ่มสแกนหายใจช้าๆ — บอกใบ้ว่านี่คือปุ่มหลัก
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.items.length == 4, 'LiquidNavBar ต้องมี 4 ช่องพอดี');
    final t = TpixThemeExtension.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // ── แถบเมนู (พื้นหลัง 3D) ── วาดก่อน = อยู่ชั้นล่าง
          Positioned(
            left: 14,
            right: 14,
            bottom: 6,
            child: _buildBar(t, isDark),
          ),

          // ── ปุ่มสแกนตรงกลาง (ยกนูนคร่อมแถบ) ──
          // จงใจไม่ใช้ Positioned: Stack วัดความสูงตัวเองจากลูกที่ไม่ Positioned
          // → กรอบของแถบเมนูครอบปุ่มทั้งใบเสมอ แม้ผู้ใช้ตั้งขนาดตัวอักษรใหญ่
          //
          // 🔴 ห้ามเปลี่ยนกลับไปเป็น SizedBox(height: ค่าคงที่) + Positioned
          // Flutter ไม่ hit-test ส่วนที่ล้นนอกกรอบพ่อ (Clip.none วาดให้เห็นก็จริง แต่กดไม่ติด)
          // ของเดิมกรอบสูง 110px ปุ่มต้องการ 142px → ยอดปุ่มที่โผล่พ้นแถบกดไม่ติดทั้งแถบ
          Padding(
            padding: EdgeInsets.only(bottom: _barHeight - _scanSize * LiquidNavBar.scanSink),
            child: _buildScanButton(t, isDark),
          ),
        ],
      ),
    );
  }

  // ── แถบพื้นหลัง + 4 ช่องเมนู ──
  Widget _buildBar(TpixThemeExtension t, bool isDark) {
    return Container(
      height: _barHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_barHeight / 2),
        // ไล่สีบน→ล่าง สร้างมิติผิวโค้ง (สว่างด้านบน เข้มด้านล่าง)
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  Color.lerp(t.card, Colors.white, 0.10)!,
                  Color.lerp(t.card, Colors.black, 0.12)!,
                ]
              : [
                  // ธีมสว่างใช้แคปซูล "สีเข้มลอยบนพื้นสว่าง" ไม่ใช่แคปซูลขาว
                  // เพราะไอคอนเจลลี่เป็นโทนพาสเทล วางบนขาวยังไงก็คอนทราสต์ต่ำ
                  // ด็อกเข้มลอยอยู่เหนือหน้าเป็นแพตเทิร์นที่ทั้งอ่านง่ายและดูพรีเมียม
                  Color.lerp(t.textPrimary, t.brandPrimary, 0.16)!,
                  Color.lerp(t.textPrimary, Colors.black, 0.14)!,
                ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.16),
          width: 1.2,
        ),
        boxShadow: [
          // เงาลึก — ทำให้แถบดูลอยเหนือพื้น
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.55)
                : t.brandPrimary.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          // เงาสัมผัสใกล้ — ขอบล่างคมขึ้น ให้รู้สึกเป็นวัตถุแข็ง
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // ClipRRect — ลายต้องถูกตัดตามทรงแคปซูล ไม่งั้นเส้นทะลุออกนอกแถบ
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_barHeight / 2),
        child: Stack(
          children: [
            // ลายเส้นสานบนผิวแถบ — ให้รู้สึกเป็นวัสดุ ไม่ใช่พลาสติกทาสี
            Positioned.fill(
              child: LuxeTexture(
                // แคปซูลเป็นสีเข้มทั้งสองธีม ลายจึงต้องเป็นเส้นสีอ่อนเสมอ
                isDark: true,
                lineColor: Colors.white,
                scale: LuxeTextureScale.card,
              ),
            ),
            // ประกายผิวโค้งด้านบน — ทำให้แคปซูลดูเป็นวัตถุนูนจริง
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _barHeight * 0.5,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.07 : 0.10),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: _navSlot(t, 0)),
                Expanded(child: _navSlot(t, 1)),
                // ช่องว่างตรงกลางไว้ให้ปุ่มสแกน
                SizedBox(width: _scanSize + 16),
                Expanded(child: _navSlot(t, 2)),
                Expanded(child: _navSlot(t, 3)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── ช่องเมนูหนึ่งช่อง ──
  Widget _navSlot(TpixThemeExtension t, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.items[index];
    final active = widget.currentIndex == index;
    // แคปซูลเป็นสีเข้มทั้งสองธีม ป้ายจึงใช้ชุดสีเดียวกันได้
    final color = active ? t.brandPrimary : Colors.white.withValues(alpha: 0.62);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        customBorder: const StadiumBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TpixRadius.lg),
            color: active
                ? t.brandPrimary.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.assetIcon != null)
                // ตัวที่ไม่ได้เลือกหรี่ลง ให้ตัวที่เลือกเด่นขึ้นมาเอง
                Opacity(
                  // ธีมสว่างหรี่ได้น้อยกว่า เพราะไอคอนพาสเทลบนพื้นสว่างคอนทราสต์ต่ำอยู่แล้ว
                  opacity: active ? 1.0 : 0.62,
                  child: Image.asset(
                    item.assetIcon!,
                    width: 28,
                    height: 28,
                    cacheWidth: 84,
                    cacheHeight: 84,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => Icon(
                        active ? item.activeIcon : item.icon,
                        size: 21,
                        color: color),
                  ),
                )
              else
                Icon(active ? item.activeIcon : item.icon, size: 21, color: color),
              const SizedBox(height: TpixGap.hair),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ปุ่มสแกนวงกลมใหญ่ (3D) ──
  Widget _buildScanButton(TpixThemeExtension t, bool isDark) {
    return GestureDetector(
      key: LiquidNavBar.scanButtonKey,
      // opaque = กดที่ช่องว่างรอบวงกลม/ป้ายก็ติด (ค่าเริ่มต้น deferToChild
      // จะรับเฉพาะพิกเซลที่ลูกวาดจริง → ขอบปุ่มกดไม่ติด)
      behavior: HitTestBehavior.opaque,
      onTap: widget.onScanTap,
      onTapDown: (_) => setState(() => _scanPressed = true),
      onTapUp: (_) => setState(() => _scanPressed = false),
      onTapCancel: () => setState(() => _scanPressed = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              // วงแหวนหายใจ: ขยาย 1.0 → 1.14 พร้อมจางลง
              final p = Curves.easeInOut.transform(_pulse.value);
              return SizedBox(
                width: _scanSize + 26,
                height: _scanSize + 26,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // วงแหวนเรืองแสงรอบนอก
                    Transform.scale(
                      scale: 1.0 + p * 0.14,
                      child: Container(
                        width: _scanSize,
                        height: _scanSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: t.brandPrimary
                                .withValues(alpha: 0.30 * (1 - p)),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    child!,
                  ],
                ),
              );
            },
            child: AnimatedScale(
              // กดแล้วยุบลงเล็กน้อย = ฟีลปุ่มจริง
              scale: _scanPressed ? 0.92 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: _scanCircle(t, isDark),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            widget.scanLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: t.brandPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanCircle(TpixThemeExtension t, bool isDark) {
    return Container(
      width: _scanSize,
      height: _scanSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(t.brandPrimary, Colors.white, 0.28)!,
            t.brandPrimary,
            Color.lerp(t.brandSecondary, Colors.black, 0.10)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          // เงาสีแบรนด์ฟุ้ง — ทำให้ปุ่มเหมือนเรืองแสงลอยอยู่
          BoxShadow(
            color: t.brandPrimary.withValues(alpha: isDark ? 0.55 : 0.42),
            blurRadius: 22,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
          // เงาแข็งใต้ปุ่ม — ให้ความรู้สึกมีน้ำหนักจริง
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ไฮไลต์ผิวด้านบน — จุดที่ทำให้ดูเป็นทรงกลม 3D จริงๆ
          Positioned(
            top: 6,
            child: Container(
              width: _scanSize * 0.62,
              height: _scanSize * 0.34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_scanSize),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // เงาโค้งด้านล่างในตัวปุ่ม (ambient occlusion อ่อนๆ)
          Positioned(
            bottom: 0,
            child: Container(
              width: _scanSize * 0.8,
              height: _scanSize * 0.3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_scanSize),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Image.asset(
            'assets/images/icons/scan.png',
            width: 32,
            height: 32,
            cacheWidth: 96,
            cacheHeight: 96,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}

/// แผ่นตัวเลือก "รับ / จ่าย" ที่เด้งขึ้นเมื่อกดปุ่มสแกน
/// คืน [ScanSheetAction] ที่ผู้ใช้เลือก (null = ปิดไปเฉยๆ)
enum ScanSheetAction { scanToPay, showMyQr }

Future<ScanSheetAction?> showScanActionSheet(
  BuildContext context, {
  required String title,
  required String scanLabel,
  required String scanSub,
  required String receiveLabel,
  required String receiveSub,
}) {
  final t = TpixThemeExtension.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<ScanSheetAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: isDark ? t.card : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.sheet)),
        border: Border.all(color: t.glassBorder, width: 1.2),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: t.textMuted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: TpixGap.lg),
              // ภาพประกอบเจลลี่ — เฉพาะธีมลิควิด (สไตล์ภาพผูกกับธีมนี้)
              if (t.themeId == ThemeId.liquid) ...[
                Image.asset(
                  'assets/images/liquid_scan.png',
                  width: 96,
                  height: 96,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                const SizedBox(height: TpixGap.sm),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: TpixGap.lg),
              Row(
                children: [
                  Expanded(
                    child: _ScanChoiceCard(
                      icon: Icons.qr_code_scanner_rounded,
                      color: t.brandPrimary,
                      label: scanLabel,
                      sub: scanSub,
                      onTap: () =>
                          Navigator.pop(ctx, ScanSheetAction.scanToPay),
                    ),
                  ),
                  const SizedBox(width: TpixGap.md),
                  Expanded(
                    child: _ScanChoiceCard(
                      icon: Icons.qr_code_2_rounded,
                      color: t.brandSecondary,
                      label: receiveLabel,
                      sub: receiveSub,
                      onTap: () =>
                          Navigator.pop(ctx, ScanSheetAction.showMyQr),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ScanChoiceCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sub;
  final VoidCallback onTap;

  const _ScanChoiceCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = TpixThemeExtension.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TpixRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TpixRadius.lg),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.16),
                color.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(color, Colors.white, 0.25)!,
                      color,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: TpixGap.md),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: TpixGap.hair),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
