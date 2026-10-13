/// TPIX Wallet — แถบเมนูล่างของ "หน้าแท็บ" ในธีม Obsidian (กิจกรรม / ตั้งค่า)
///
/// mock ของกิจกรรมและตั้งค่ามีแถบเมนูล่างเหมือนหน้าแรก (แท็บของหน้านั้นสว่าง)
/// หน้าแรกเป็นเจ้าของการนำทางทั้งหมด (สแกนจ่าย/รับ · เปิดหน้า) — หน้าแท็บจึงแค่
/// "ปิดตัวเองพร้อมบอกว่าผู้ใช้กดแท็บไหน" แล้วหน้าแรกพาไปต่อ (ดู HomeScreen._obsOpen)
///   - กดแท็บของหน้าตัวเอง → เลื่อนกลับบนสุด (ไม่ปิด/เปิดซ้ำ)
///   - กระเป๋า → เปิดแผ่นรายการกระเป๋าทับหน้านี้ได้เลย (ไม่ต้องกลับหน้าแรก)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../widgets/obsidian/obsidian.dart';
import 'wallet_list_sheet.dart';

/// แท็บของแถบเมนูล่าง (ลำดับไม่ใช่ index ของแถบ — ดู [ObsidianTabBar])
enum ObsidianTab { home, activity, scan, wallet, settings }

class ObsidianTabBar extends StatelessWidget {
  /// แท็บของหน้าที่แถบนี้อยู่
  final ObsidianTab current;

  /// กดแท็บของหน้าตัวเองซ้ำ (เช่น เลื่อนกลับบนสุด)
  final VoidCallback? onReselect;

  const ObsidianTabBar({super.key, required this.current, this.onReselect});

  static int _index(ObsidianTab t) => switch (t) {
        ObsidianTab.home => 0,
        ObsidianTab.activity => 1,
        ObsidianTab.wallet => 2,
        ObsidianTab.settings => 3,
        ObsidianTab.scan => -1,
      };

  void _go(BuildContext context, ObsidianTab tab) {
    if (tab == current) {
      onReselect?.call();
      return;
    }
    if (tab == ObsidianTab.wallet) {
      WalletListSheet.show(context);
      return;
    }
    // ให้หน้าแรกพาไปต่อ — ถ้าหน้านี้ไม่ได้ถูกเปิดจากหน้าแรก (pop ไม่ได้) ก็ไม่ทำอะไร
    Navigator.of(context).maybePop(tab);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return NotchedNavBar(
      currentIndex: _index(current),
      scanLabel: l.t('nav.scan'),
      scanSemantics: l.t('obs.scanSemantics'),
      onScanTap: () => _go(context, ObsidianTab.scan),
      items: [
        NotchedNavItem(
          asset: ObsidianIcons.home,
          label: l.t('nav.home'),
          onTap: () => _go(context, ObsidianTab.home),
        ),
        NotchedNavItem(
          asset: ObsidianIcons.activity,
          label: l.t('nav.activity'),
          onTap: () => _go(context, ObsidianTab.activity),
        ),
        NotchedNavItem(
          asset: ObsidianIcons.wallet,
          label: l.t('nav.wallet'),
          onTap: () => _go(context, ObsidianTab.wallet),
        ),
        NotchedNavItem(
          asset: ObsidianIcons.settings,
          label: l.t('nav.settings'),
          onTap: () => _go(context, ObsidianTab.settings),
        ),
      ],
    );
  }
}
