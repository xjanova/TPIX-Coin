/// TPIX Wallet — Sign History Screen
///
/// แสดงประวัติการเซ็น cross-app ที่ผ่านมา — user จะเห็นว่าเคยเซ็นอะไรให้
/// แอพไหน เมื่อไหร่ สำเร็จ/ปฏิเสธ เพื่อ audit ตัวเอง
///
/// เข้าจาก Settings → "Sign History"
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/db_service.dart';

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
    final rows = await DbService.getSignHistory(slot);
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
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    final isThai = l.isThai;

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
      body: Container(
        decoration: c.screenBg,
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
            const SizedBox(height: 16),
            Text(
              isThai ? 'ยังไม่มีประวัติการเซ็น' : 'No sign history yet',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
            ),
            const SizedBox(height: 8),
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textSec.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
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
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 12, color: textSec),
              const SizedBox(width: 4),
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
