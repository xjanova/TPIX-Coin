/// TPIX Wallet — แผ่น "รายงานปัญหา" ให้ผู้ใช้ส่งเองทันทีที่เจอ
///
/// ส่งข้อความของผู้ใช้ + สภาพแอปตอนนั้น + breadcrumb ล่าสุด เข้าระบบรายงานบั๊กกลาง
/// (ไม่มีข้อมูลลับ — mnemonic/กุญแจไม่เคยเข้าใกล้ตัวรายงาน และมีตัวล้างกันเหนียวอีกชั้น)
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../services/bug_reporter.dart';

Future<void> showBugReportSheet(BuildContext context, {required bool isThai}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BugReportSheet(isThai: isThai),
  );
}

class _BugReportSheet extends StatefulWidget {
  final bool isThai;
  const _BugReportSheet({required this.isThai});

  @override
  State<_BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<_BugReportSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _text.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);

    await BugReporter.I.report(
      title: message.length > 80 ? '${message.substring(0, 80)}…' : message,
      description: message,
      type: 'bug',
      severity: 'moderate',
      priority: 'medium',
      metadata: const {'source': 'user', 'category': 'user-report'},
      dedupe: false,
    );

    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.isThai;
    final c = AppColors.of(context);
    final crumbs = BugReporter.I.breadcrumbs;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.lg)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.textSec.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: TpixGap.xl),
          Text(
            th ? 'รายงานปัญหา' : 'Report a problem',
            style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: TpixGap.sm),
          Text(
            th
                ? 'เล่าสั้นๆ ว่ากดอะไรแล้วเกิดอะไร ระบบจะแนบสภาพแอปตอนนี้และเหตุการณ์ ${crumbs.length} รายการล่าสุดไปให้ทีมงานเอง (ไม่มีข้อมูลลับ)'
                : 'Briefly describe what you did and what happened. The app state and the last ${crumbs.length} events are attached automatically (no secrets).',
            style: TextStyle(color: c.textSec, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: TpixGap.md),
          TextField(
            controller: _text,
            maxLines: 5,
            minLines: 3,
            maxLength: 2000,
            style: TextStyle(color: c.text, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.textSec.withValues(alpha: 0.08),
              counterText: '',
              hintText: th ? 'เช่น เซ็นให้ TPIX Trade แล้วแอปเด้งออก' : 'e.g. Signed for TPIX Trade and the app jumped away',
              hintStyle: TextStyle(color: c.textSec.withValues(alpha: 0.6), fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.textSec.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TpixRadius.md),
                borderSide: BorderSide(color: c.textSec.withValues(alpha: 0.2)),
              ),
            ),
          ),
          const SizedBox(height: TpixGap.sm),
          if (crumbs.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 110),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.textSec.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(TpixRadius.sm),
              ),
              child: SingleChildScrollView(
                child: Text(
                  crumbs.reversed.take(8).join('\n'),
                  style: TextStyle(fontSize: 10, color: c.textSec, height: 1.4, fontFamily: 'monospace'),
                ),
              ),
            ),
          const SizedBox(height: TpixGap.md),
          FilledButton.icon(
            onPressed: _sending || _sent ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.md)),
            ),
            icon: Icon(_sent ? Icons.check_rounded : Icons.send_rounded, size: 18),
            label: Text(
              _sent
                  ? (th ? 'ส่งแล้ว ขอบคุณ' : 'Sent — thank you')
                  : _sending
                      ? (th ? 'กำลังส่ง…' : 'Sending…')
                      : (th ? 'ส่งรายงาน' : 'Send report'),
            ),
          ),
        ],
      ),
    );
  }
}
