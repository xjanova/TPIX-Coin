/// ป้ายเล็กๆ บอกความน่าเชื่อถือของโทเค็น (ยืนยันแล้ว / ชื่อเลียนแบบ)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../services/token_trust.dart';

/// ไอคอนท้ายสัญลักษณ์โทเค็น — ไม่ยืนยัน = ไม่แสดงอะไร (ไม่รกหน้าจอ)
class TokenTrustIcon extends StatelessWidget {
  final TokenTrust trust;
  final double size;

  const TokenTrustIcon({super.key, required this.trust, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    switch (trust) {
      case TokenTrust.verified:
        return Tooltip(
          message: l.t('token.verifiedHint'),
          child: Icon(Icons.verified, size: size, color: AppTheme.primary,
              semanticLabel: l.t('token.verified')),
        );
      case TokenTrust.lookalike:
        return Tooltip(
          message: l.t('token.lookalikeShort'),
          child: Icon(Icons.gpp_maybe_rounded, size: size, color: AppTheme.danger,
              semanticLabel: l.t('token.lookalikeTitle')),
        );
      case TokenTrust.unverified:
        return const SizedBox.shrink();
    }
  }
}

/// ป้าย "ยืนยันแล้ว" แบบมีข้อความ (หน้าเพิ่มโทเค็น)
class VerifiedTokenChip extends StatelessWidget {
  const VerifiedTokenChip({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return Tooltip(
      message: l.t('token.verifiedHint'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TpixRadius.xs),
          color: AppTheme.primary.withValues(alpha: 0.12),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, size: 13, color: AppTheme.primary),
            const SizedBox(width: TpixGap.xs),
            Text(
              l.t('token.verified'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
