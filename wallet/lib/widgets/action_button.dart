/// TPIX Wallet — ปุ่มลัดหน้าหลัก (ส่ง / รับ / ประวัติ / แลก / …)
///
/// ทำไมต้องรื้อของเดิม: ปุ่มเดิมคือ "คราบสี" ไม่ใช่ปุ่ม
///   พื้นปุ่ม = สีแบรนด์ alpha 0.06–0.12, วงไอคอน = alpha 0.12–0.20
///   สองชั้นนี้ห่างกันไม่ถึง 10% ตาเลยแยกไม่ออกว่าอะไรคือปุ่ม อะไรคือพื้น
///   ไม่มีไฮไลต์ผิวบน ไม่มีเงาสัมผัส → แบนสนิท ไม่รู้ว่ากดได้
///
/// ตัวใหม่ยืมภาษาการออกแบบมาจากปุ่มสแกน 3D บนแถบเมนูล่าง (liquid_nav_bar)
/// เพื่อให้ทั้งแอปพูดภาษาเดียวกัน:
///   1. ไล่สีผิวโค้ง สว่างบน–เข้มล่าง (บอกว่าเป็นวัตถุนูน)
///   2. ไฮไลต์ผิวด้านบน — ตัวที่ทำให้ตาอ่านว่า "นูน" จริง ๆ
///   3. เงาสองชั้น: ฟุ้งไกล (ลอย) + สัมผัสใกล้ (มีน้ำหนัก)
///   4. วงไอคอนทึบอิ่มสี + ไอคอนขาว = คอนทราสต์สูงสุด อ่านออกแม้แดดจ้า
///   5. กดแล้วยุบ + เงาหด = ฟีดแบ็กว่ากดติด
///
/// อ่านสีจาก TpixThemeExtension ล้วน → ใช้ได้ครบทั้ง 4 ธีม
///
/// Developed by Xman Studio

import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import '../core/themes/theme_bundle.dart';

class TpixActionButton extends StatefulWidget {
  final IconData icon;

  /// ไอคอนเจลลี่ 3D (ถ้ามี ใช้แทนวงกลมสี+ไอคอนเวกเตอร์)
  /// รูปทรงเจลลี่เป็นตัวสื่อความหมายเอง ไม่ต้องมีจานสีมาแข่งสายตา
  final String? assetIcon;

  final String label;
  final String sublabel;

  /// สีประจำปุ่ม (เขียว=รับ, ฟ้า=ส่ง, ม่วง=ประวัติ …)
  final Color color;

  final VoidCallback onTap;

  /// ปุ่มเด่นพิเศษ — พื้นเป็นสีแบรนด์เต็ม ไม่ใช่พื้นการ์ด (ใช้กับปุ่มหลัก 1 ปุ่มพอ)
  final bool primary;

  const TpixActionButton({
    super.key,
    required this.icon,
    this.assetIcon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  @override
  State<TpixActionButton> createState() => _TpixActionButtonState();
}

class _TpixActionButtonState extends State<TpixActionButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = TpixThemeExtension.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      // opaque = กดตรงช่องว่างในปุ่มก็ติด ไม่ใช่เฉพาะพิกเซลที่มีสี
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.955 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TpixRadius.lg),
            gradient: _surfaceGradient(t, isDark),
            border: Border.all(color: _borderColor(t, isDark), width: 1.2),
            boxShadow: _pressed ? _pressedShadow(t, isDark) : _restShadow(t, isDark),
          ),
          child: Stack(
            // ต้องระบุ center เอง — ลูกที่ไม่ Positioned ใน Stack
            // จะถูกจัดไปมุมบนซ้ายตามค่าเริ่มต้น ทำให้ไอคอนกับป้ายเบียดซ้าย
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // ไฮไลต์ผิวด้านบน — จุดที่ทำให้ปุ่มดูนูนแทนที่จะเป็นสี่เหลี่ยมทาสี
              Positioned(
                top: -18,
                left: -8,
                right: -8,
                child: IgnorePointer(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(TpixRadius.lg),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: isDark ? 0.10 : 0.85),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _iconDisc(t, isDark),
                  const SizedBox(height: TpixGap.md),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.primary && !isDark
                          ? Colors.white
                          : t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: TpixGap.hair),
                  Text(
                    widget.sublabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: widget.primary && !isDark
                          ? Colors.white.withValues(alpha: 0.85)
                          : t.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── วงไอคอนทึบ + เรืองแสง ──
  // ของเดิมเป็นวงสีจาง 15% ไอคอนสีเดียวกับพื้น → จมหายไปกับปุ่ม
  // ของใหม่ทึบเต็มสี ไอคอนขาว = คอนทราสต์สูงสุด เห็นชัดทั้งกลางแดดและกลางคืน
  Widget _iconDisc(TpixThemeExtension t, bool isDark) {
    final c = widget.color;

    // มีไอคอนเจลลี่ → ใช้ตัวมันเลย พร้อมแสงสีประจำปุ่มเรืองอยู่ข้างหลัง
    // (ไม่วางบนจานสีทึบ เพราะสีของจานจะตีกับสีในตัวเจลลี่จนขุ่น)
    if (widget.assetIcon != null) {
      return SizedBox(
        width: 54,
        height: 54,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // แสงเรืองด้านหลัง — ต้องฟุ้งจริง ไม่ใช่จานสีทึบ
            // ค่าเดิม (alpha .38 blur 18 spread -2) จับตัวเป็นวงกลมสีชัด
            // แล้วไปตีกับสีมินต์/ลาเวนเดอร์ในตัวไอคอนจนขุ่น
            // จางลง + ฟุ้งกว้างขึ้น = ได้แสงรอบตัวไอคอน ยังบอกรหัสสีประจำปุ่มได้
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: t.useGlow ? 0.34 : 0.22),
                    blurRadius: 26,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            Image.asset(
              widget.assetIcon!,
              width: 46,
              height: 46,
              // ถอดรหัสที่ขนาดวาดจริง (46 x 3 dpr) ไม่ใช่ไฟล์เต็ม
              cacheWidth: 138,
              cacheHeight: 138,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) =>
                  Icon(widget.icon, color: Colors.white, size: 26),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(c, Colors.white, 0.32)!,
            c,
            Color.lerp(c, Colors.black, 0.14)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        boxShadow: [
          // เงาสีตัวเอง = ให้ความรู้สึกว่าไอคอนเรืองแสงลอยเหนือปุ่ม
          BoxShadow(
            color: c.withValues(alpha: t.useGlow ? 0.62 : 0.42),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ไฮไลต์ผิวบนของวงกลม — ตัวเดียวกับที่ใช้ในปุ่มสแกน
          Positioned(
            top: 5,
            child: IgnorePointer(
              child: Container(
                width: 30,
                height: 15,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
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
          ),
          Icon(widget.icon, color: Colors.white, size: 24),
        ],
      ),
    );
  }

  // ── ผิวปุ่ม ──
  LinearGradient _surfaceGradient(TpixThemeExtension t, bool isDark) {
    final c = widget.color;
    if (widget.primary) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(c, Colors.white, 0.18)!, c, Color.lerp(c, Colors.black, 0.16)!],
        stops: const [0.0, 0.45, 1.0],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              // ยกพื้นการ์ดเข้าหาสีแบรนด์ให้พอ "เห็นว่าเป็นปุ่ม" แล้วไล่เข้มลงล่าง
              Color.lerp(Color.lerp(t.card, c, 0.16)!, Colors.white, 0.06)!,
              Color.lerp(t.card, Colors.black, 0.10)!,
            ]
          : [
              Colors.white,
              Color.lerp(Colors.white, c, 0.14)!,
            ],
    );
  }

  Color _borderColor(TpixThemeExtension t, bool isDark) {
    final c = widget.color;
    if (widget.primary) return Color.lerp(c, Colors.white, 0.35)!;
    if (t.useGlow) return c.withValues(alpha: 0.55);
    return isDark
        ? Color.lerp(c, Colors.white, 0.18)!.withValues(alpha: 0.34)
        : c.withValues(alpha: 0.22);
  }

  // เงาตอนปกติ: ฟุ้งไกล (ลอย) + สัมผัสใกล้ (มีน้ำหนัก)
  List<BoxShadow> _restShadow(TpixThemeExtension t, bool isDark) {
    final c = widget.color;
    return [
      BoxShadow(
        color: t.useGlow
            ? c.withValues(alpha: 0.32 * t.glowIntensity + 0.16)
            : (isDark
                ? Colors.black.withValues(alpha: 0.50)
                : c.withValues(alpha: 0.20)),
        blurRadius: 20,
        offset: const Offset(0, 9),
      ),
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.34)
            : Colors.black.withValues(alpha: 0.07),
        blurRadius: 5,
        offset: const Offset(0, 2),
      ),
    ];
  }

  // กดแล้วเงาหด = ปุ่มยุบลงไปติดพื้น
  List<BoxShadow> _pressedShadow(TpixThemeExtension t, bool isDark) {
    final c = widget.color;
    return [
      BoxShadow(
        color: t.useGlow
            ? c.withValues(alpha: 0.22)
            : (isDark
                ? Colors.black.withValues(alpha: 0.34)
                : c.withValues(alpha: 0.13)),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ];
  }
}
