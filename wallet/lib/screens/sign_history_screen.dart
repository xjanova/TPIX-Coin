/// TPIX Wallet — Sign History Screen
///
/// แสดงประวัติการเซ็น cross-app ที่ผ่านมา — user จะเห็นว่าเคยเซ็นอะไรให้
/// แอพไหน เมื่อไหร่ สำเร็จ/ปฏิเสธ เพื่อ audit ตัวเอง
///
/// เข้าจาก Settings → "Sign History"
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/themes/tokens.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/theme_bundle.dart';
import '../core/themes/widgets/screen_background.dart';
import '../providers/wallet_provider.dart';
import '../services/db_service.dart';
import '../widgets/obsidian/obsidian.dart';
import '../widgets/obsidian/obsidian_page_header.dart';
import '../widgets/obsidian/obsidian_screen_dim.dart';

class SignHistoryScreen extends StatefulWidget {
  const SignHistoryScreen({super.key});

  @override
  State<SignHistoryScreen> createState() => _SignHistoryScreenState();
}

class _SignHistoryScreenState extends State<SignHistoryScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final slot = context.read<WalletProvider>().activeSlot;
    List<Map<String, dynamic>> rows;
    try {
      rows = await DbService.getSignHistory(slot);
    } catch (e) {
      // อ่านฐานข้อมูลไม่ได้ = โชว์ว่าง ไม่ใช่วงหมุนค้างตลอดไป
      debugPrint('sign history: ${e.runtimeType}');
      rows = const [];
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final l = context.read<LocaleProvider>();
    final isThai = l.isThai;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isThai ? 'ล้างประวัติทั้งหมด?' : 'Clear all history?'),
        content: Text(
          isThai
              ? 'ลบประวัติการเซ็นทั้งหมดถาวร — ไม่สามารถกู้คืนได้'
              : 'All sign history will be permanently deleted',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isThai ? 'ล้าง' : 'Clear',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final slot = context.read<WalletProvider>().activeSlot;
    await DbService.clearSignHistory(slot);
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    final isThai = l.isThai;
    if (TpixThemeExtension.of(context).themeId == ThemeId.obsidian) {
      return _buildObsidian(isThai);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isThai ? 'ประวัติการเซ็น' : 'Sign History'),
        actions: [
          if (_rows.isNotEmpty)
            IconButton(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: isThai ? 'ล้างทั้งหมด' : 'Clear all',
            ),
        ],
      ),
      body: TpixScreenBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? _EmptyState(isThai: isThai, textColor: c.text, textSec: c.textSec)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) => _SignHistoryRow(
                        row: _rows[i],
                        isThai: isThai,
                        textColor: c.text,
                        textSec: c.textSec,
                        surface: c.surface,
                      ),
                    ),
                  ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// ธีม Obsidian — ข้อมูล/การล้างเหมือนเดิม เปลี่ยนแค่หน้าตา
// ──────────────────────────────────────────────────────────────────────────

extension _ObsidianSignHistory on _SignHistoryScreenState {
  Widget _buildObsidian(bool isThai) {
    final st = ObsidianStyle.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final children = <Widget>[
      ObsidianPageHeader(
        title: isThai ? 'ประวัติการเซ็น' : 'Sign History',
        backSemantics: MaterialLocalizations.of(context).backButtonTooltip,
        trailing: _rows.isEmpty
            ? null
            : ObsidianHeaderTile(
                semanticLabel: isThai ? 'ล้างทั้งหมด' : 'Clear all',
                // ล้างถาวร — มีกล่องยืนยันใน _clearAll
                onTap: _clearAll,
                child: const Icon3D(ObsidianIcons.trash, size: 26),
              ),
      ),
      const SizedBox(height: 20),
    ];
    if (_loading) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: ObsidianColors.cyan),
          ),
        ),
      ));
    } else if (_rows.isEmpty) {
      children.add(ObsidianPanel(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          children: [
            const Icon3D(ObsidianIcons.signHistory, size: 72, shadows: [IconDropShadow.tile]),
            const SizedBox(height: 16),
            Text(
              isThai ? 'ยังไม่มีประวัติการเซ็น' : 'No sign history yet',
              textAlign: TextAlign.center,
              style: st.ui(fontSize: 17, fontWeight: FontWeight.w600, color: ObsidianColors.text),
            ),
            const SizedBox(height: 6),
            Text(
              isThai ? 'เมื่อแอพอื่นขอลายเซ็น จะแสดงที่นี่' : 'When peer apps request a signature, they appear here',
              textAlign: TextAlign.center,
              style: st.ui(fontSize: 13, height: 1.5, color: ObsidianColors.textSec),
            ),
          ],
        ),
      ));
    } else {
      for (final row in _rows) {
        children
          ..add(_ObsSignRow(row: row, isThai: isThai))
          ..add(const SizedBox(height: 10));
      }
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianScreenDim.node),
          RefreshIndicator(
            onRefresh: _load,
            color: ObsidianColors.cyan,
            backgroundColor: ObsidianColors.card,
            edgeOffset: top,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, math.max(52.0, top + 8), 24, 40),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _ObsSignRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isThai;

  const _ObsSignRow({required this.row, required this.isThai});

  @override
  Widget build(BuildContext context) {
    final st = ObsidianStyle.of(context);
    final dt = DateTime.fromMillisecondsSinceEpoch((row['timestamp'] as int) * 1000);
    final (color, label, icon) = switch (row['status'] as String) {
      'signed' => (ObsidianColors.successSoft, isThai ? 'เซ็นแล้ว' : 'Signed', Icons.check_circle_rounded),
      'rejected' => (ObsidianColors.dangerSoft, isThai ? 'ปฏิเสธ' : 'Rejected', Icons.cancel_rounded),
      'wallet_locked' => (ObsidianColors.warning, isThai ? 'กระเป๋าล็อก' : 'Locked', Icons.lock_rounded),
      _ => (ObsidianColors.warning, isThai ? 'ผิดพลาด' : 'Failed', Icons.error_outline_rounded),
    };
    return ObsidianPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row['source_app'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: st.ui(fontSize: 14.5, fontWeight: FontWeight.w600, color: ObsidianColors.text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(label, style: st.ui(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row['message'] as String,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: st.mono(fontSize: 12, color: ObsidianColors.textSoft, height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat(isThai ? 'd MMM yyyy HH:mm:ss' : 'MMM d, yyyy HH:mm:ss').format(dt),
            style: st.ui(fontSize: 11.5, color: ObsidianColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isThai;
  final Color textColor;
  final Color textSec;
  const _EmptyState({
    required this.isThai,
    required this.textColor,
    required this.textSec,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.draw_outlined, size: 56, color: textSec),
            const SizedBox(height: TpixGap.lg),
            Text(
              isThai ? 'ยังไม่มีประวัติการเซ็น' : 'No sign history yet',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
            ),
            const SizedBox(height: TpixGap.sm),
            Text(
              isThai
                  ? 'เมื่อแอพอื่นขอลายเซ็น จะแสดงที่นี่'
                  : 'When peer apps request a signature, they appear here',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: textSec),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignHistoryRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isThai;
  final Color textColor;
  final Color textSec;
  final Color surface;

  const _SignHistoryRow({
    required this.row,
    required this.isThai,
    required this.textColor,
    required this.textSec,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    final ts = row['timestamp'] as int;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final status = row['status'] as String;
    final (statusColor, statusLabel, statusIcon) = _statusInfo(status, isThai);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(TpixRadius.sm),
        border: Border.all(color: textSec.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: TpixGap.sm),
              Expanded(
                child: Text(
                  row['source_app'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: TpixGap.sm),
          Text(
            row['message'] as String,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.8),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: TpixGap.sm),
          Row(
            children: [
              Icon(Icons.schedule, size: 12, color: textSec),
              const SizedBox(width: TpixGap.xs),
              Text(
                DateFormat(isThai
                        ? 'd MMM yyyy HH:mm:ss'
                        : 'MMM d, yyyy HH:mm:ss')
                    .format(dt),
                style: TextStyle(fontSize: 11, color: textSec),
              ),
            ],
          ),
        ],
      ),
    );
  }

  (Color, String, IconData) _statusInfo(String status, bool th) {
    switch (status) {
      case 'signed':
        return (
          const Color(0xFF10B981),
          th ? 'เซ็นแล้ว' : 'SIGNED',
          Icons.check_circle,
        );
      case 'rejected':
        return (
          const Color(0xFFEF4444),
          th ? 'ปฏิเสธ' : 'REJECTED',
          Icons.cancel,
        );
      case 'wallet_locked':
        return (
          const Color(0xFFF59E0B),
          th ? 'กระเป๋าล็อก' : 'LOCKED',
          Icons.lock,
        );
      default:
        return (
          const Color(0xFFF59E0B),
          th ? 'ผิดพลาด' : 'FAILED',
          Icons.error_outline,
        );
    }
  }
}
