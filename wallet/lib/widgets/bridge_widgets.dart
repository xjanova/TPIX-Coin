/// TPIX Wallet — ชิ้นส่วนหน้าจอที่สะพาน USDT และสะพาน wTPIX ใช้ร่วมกัน
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../providers/wallet_provider.dart';
import '../services/bridge_rules.dart';
import '../services/bridge_service.dart';
import '../services/synth_service.dart';
import '../services/wallet_service.dart';
import 'tx_auth.dart';

/// ส่วนที่หน้าสะพานทั้งสองใช้ร่วมกัน: กันกดซ้อน + ยืนยันตัวตน + เซ็น/ส่ง + ข้อความ error ที่อ่านรู้เรื่อง
mixin BridgeSendFlow<T extends StatefulWidget> on State<T> {
  /// กำลังทำรายการ (ตั้งแต่แตะปุ่มจนจบ รวมช่วงตรวจ/กล่องยืนยัน/PIN/ส่ง) — ทุกปุ่มส่งปิดหมด
  bool bridgeBusy = false;
  String? bridgeBusyLabel;

  void setBridgeBusyLabel(String? label) {
    if (mounted) setState(() => bridgeBusyLabel = label);
  }

  /// ห่อทุกปุ่มส่ง: กันแตะซ้ำตั้งแต่ครั้งแรก + แปลง error เป็นข้อความ (ห้าม Exception ดิบ)
  Future<void> bridgeGuard(Future<void> Function() flow) async {
    if (bridgeBusy) return;
    setState(() => bridgeBusy = true);
    try {
      await flow();
    } catch (e) {
      if (mounted) {
        SynthService.playError();
        final params = e is BridgeCheckException ? e.params : const <String, String>{};
        bridgeSnack(context, bridgeT(context.read<LocaleProvider>(), bridgeErrorKey(e), params), error: true);
      }
    } finally {
      bridgeBusy = false;
      if (mounted) setState(() => bridgeBusyLabel = null);
    }
  }

  /// ยืนยันตัวตน → ตรวจว่ากระเป๋ายังเป็นใบเดิม → เซ็น + ส่ง
  ///
  /// null = ผู้ใช้ยกเลิกที่ PIN (ยังไม่มีอะไรถูกเซ็นหรือส่ง)
  Future<String?> bridgeAuthorizeAndSend(
    BridgeTxPlan plan, {
    required String owner,
    TxHistoryOverride? historyAs,
  }) async {
    final l = context.read<LocaleProvider>();
    final authed = await authorizeTransaction(context, reason: l.t('bridge.authReason'));
    if (!authed || !mounted) return null;
    final wallet = context.read<WalletProvider>();
    // สลับกระเป๋าระหว่างกล่องยืนยัน/PIN = ยกเลิก (expectedFrom ข้างล่างกันซ้ำอีกชั้น)
    if (wallet.address?.toLowerCase() != owner.toLowerCase()) {
      throw const WalletChangedException();
    }
    setBridgeBusyLabel(l.t('bridge.sending'));
    SynthService.playSend();
    return wallet.sendEvmTransaction(
      rpcUrl: plan.rpcUrl,
      chainId: plan.chainId,
      toAddress: plan.to,
      value: plan.value > BigInt.zero ? plan.value : null,
      data: plan.data,
      maxGas: plan.gasLimit,
      // เชน TPIX ไม่มีค่าแก๊ส (0 เสมอ) · เชนอื่นอ่านราคาแก๊สสดตอนเซ็น + ตรวจยอดซ้ำในตัวส่ง
      gasPrice: plan.chainId == bridgeTpixChainId ? BigInt.zero : null,
      expectedFrom: owner,
      historyAs: historyAs,
    );
  }
}

/// แปลข้อความ + แทนค่า {key} — คีย์ที่แอปรุ่นนี้ไม่รู้จัก (เช่น สถานะใหม่จากเซิร์ฟเวอร์)
/// ใช้ [fallbackKey] แทน ห้ามโชว์ชื่อคีย์ดิบ
String bridgeT(LocaleProvider l, String key, [Map<String, String> params = const {}, String? fallbackKey]) {
  var text = l.t(key);
  if (text == key && fallbackKey != null) text = l.t(fallbackKey);
  params.forEach((k, v) => text = text.replaceAll('{$k}', v));
  return text;
}

/// ที่อยู่/แฮชแบบย่อ — 0x12345678…abcdef
String bridgeShort(String? s, {int head = 10, int tail = 6}) {
  if (s == null || s.isEmpty) return '—';
  return s.length <= head + tail + 1 ? s : '${s.substring(0, head)}…${s.substring(s.length - tail)}';
}

Color bridgeToneColor(BridgeTone tone, AppColors c) => switch (tone) {
      BridgeTone.success => AppTheme.success,
      BridgeTone.info => AppTheme.primary,
      BridgeTone.warning => AppTheme.warm,
      BridgeTone.danger => AppTheme.danger,
      BridgeTone.muted => c.textMuted,
    };

void bridgeSnack(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.danger : AppTheme.success,
    ));
}

/// เปิดลิงก์ในเบราว์เซอร์ — https เท่านั้น (ลิงก์ส่วนใหญ่มาจากเซิร์ฟเวอร์)
Future<void> openBridgeUrl(BuildContext context, String? url) async {
  final safe = safeHttpsUrl(url);
  if (safe == null) return;
  try {
    final ok = await launchUrl(Uri.parse(safe), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      bridgeSnack(context, context.read<LocaleProvider>().t('common.browser_error'), error: true);
    }
  } catch (_) {
    if (context.mounted) {
      bridgeSnack(context, context.read<LocaleProvider>().t('common.browser_error'), error: true);
    }
  }
}

/// ช่องกรอกจำนวน: ตัวเลข + จุดทศนิยมเดียว · จุลภาค (คีย์บอร์ดบางภาษา) แปลงเป็นจุด
/// — กฎการแปลงยอดจริงอยู่ที่ bridge_rules (จุลภาคที่นั่นคือหลักพันแบบเว็บ)
final List<TextInputFormatter> bridgeAmountFormatters = [
  TextInputFormatter.withFunction((oldValue, newValue) {
    final text = newValue.text.replaceAll(',', '.');
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text);
  }),
];

class BridgeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const BridgeCard({super.key, required this.child, this.padding = const EdgeInsets.all(TpixGap.lg)});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: adaptiveGlassCard(context, borderRadius: TpixRadius.lg),
        child: child,
      );
}

class BridgeSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const BridgeSectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: TpixGap.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// แถบข้อความสี (ยังไม่เปิด / หยุดชั่วคราว / แจ้งเตือน)
class BridgeBanner extends StatelessWidget {
  final String? title;
  final String text;
  final Color color;
  final IconData icon;

  const BridgeBanner({super.key, this.title, required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(TpixGap.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TpixRadius.sm),
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: TpixGap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(title!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                    const SizedBox(height: TpixGap.xs),
                  ],
                  Text(text, style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.of(context).textSec)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// กล่องคำเตือนตัวใหญ่ — ความผิดพลาดแบบนี้เรียกเงินคืนไม่ได้
class BridgeWarningBox extends StatelessWidget {
  final String title;
  final List<String> items;

  /// ข้อแรกเป็นตัวหนา (ข้อที่ร้ายแรงที่สุด)
  final bool emphasizeFirst;

  const BridgeWarningBox({super.key, required this.title, required this.items, this.emphasizeFirst = true});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(TpixGap.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.sm),
        color: AppTheme.danger.withValues(alpha: 0.06),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.40), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 18),
              const SizedBox(width: TpixGap.xs),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.danger)),
              ),
            ],
          ),
          const SizedBox(height: TpixGap.sm),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: TpixGap.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(fontSize: 12, color: c.textSec)),
                  Expanded(
                    child: Text(
                      items[i],
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: i == 0 && emphasizeFirst ? c.text : c.textSec,
                        fontWeight: i == 0 && emphasizeFirst ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// แถว ป้าย : ค่า
class BridgeKv extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  const BridgeKv(this.label, this.value, {super.key, this.valueColor, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: TextStyle(fontSize: 12.5, color: c.textMuted)),
          ),
          const SizedBox(width: TpixGap.sm),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? c.text,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ปุ่มเลือกแบบแท็บ
class BridgeSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T>? onChanged;

  const BridgeSegmented({super.key, required this.options, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(TpixGap.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.sm),
        color: c.glassColor,
        border: Border.all(color: c.glassBorder),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                selected: o.$1 == value,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(TpixRadius.xs),
                  onTap: onChanged == null || o.$1 == value ? null : () => onChanged!(o.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: TpixGap.xs),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(TpixRadius.xs),
                      color: o.$1 == value ? AppTheme.primary.withValues(alpha: 0.20) : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      o.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: o.$1 == value ? FontWeight.w700 : FontWeight.w500,
                        color: o.$1 == value ? AppTheme.primary : c.textSec,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ป้ายสถานะ
class BridgeStateChip extends StatelessWidget {
  final String label;
  final BridgeTone tone;

  const BridgeStateChip({super.key, required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final color = bridgeToneColor(tone, AppColors.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: TpixGap.sm, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.xs),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// ช่องติ๊กยอมรับ (ต้องติ๊กใหม่ทุกครั้งที่เปิดหน้า / สลับกระเป๋า)
class BridgeAckTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String text;

  const BridgeAckTile({super.key, required this.value, required this.onChanged, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(TpixRadius.xs),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TpixGap.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                activeColor: AppTheme.primary,
              ),
            ),
            const SizedBox(width: TpixGap.sm),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.45, color: c.textSec))),
          ],
        ),
      ),
    );
  }
}

/// ปุ่มหลัก — กำลังทำงาน = หมุน + กดไม่ได้
class BridgePrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;

  const BridgePrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.loadingLabel});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.sm)),
          ),
          child: loading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    if (loadingLabel != null) ...[
                      const SizedBox(width: TpixGap.sm),
                      Flexible(
                        child: Text(loadingLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                )
              : Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: onPressed == null ? Colors.white.withValues(alpha: 0.6) : Colors.white,
                  )),
        ),
      );
}

/// ช่องกรอก (จำนวน / ที่อยู่ / tx hash)
class BridgeInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool amount;
  final bool mono;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final String? warningText;
  final Widget? suffix;

  const BridgeInput({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.amount = false,
    this.mono = false,
    this.onChanged,
    this.errorText,
    this.warningText,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: TpixGap.md, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TpixRadius.sm),
            color: c.glassColor,
            border: Border.all(color: errorText != null ? AppTheme.danger.withValues(alpha: 0.6) : c.glassBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  onChanged: onChanged,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: amount ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  inputFormatters: amount ? bridgeAmountFormatters : null,
                  style: TextStyle(
                    fontSize: amount ? 22 : 13,
                    fontWeight: amount ? FontWeight.w700 : FontWeight.w500,
                    color: c.text,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              ?suffix,
            ],
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: TpixGap.xs),
            child: Text(errorText!, style: const TextStyle(fontSize: 12, color: AppTheme.danger)),
          )
        else if (warningText != null)
          Padding(
            padding: const EdgeInsets.only(top: TpixGap.xs),
            child: Text(warningText!, style: const TextStyle(fontSize: 12, color: AppTheme.warm)),
          ),
      ],
    );
  }
}

/// ตัวเลือกเชน (การ์ดเล็กเรียงเป็นตาราง)
class BridgeChainPicker extends StatelessWidget {
  final List<({int id, String title, String subtitle, bool enabled})> chains;
  final int? selected;
  final ValueChanged<int>? onSelect;

  const BridgeChainPicker({super.key, required this.chains, required this.selected, this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Wrap(
      spacing: TpixGap.sm,
      runSpacing: TpixGap.sm,
      children: [
        for (final ch in chains)
          Opacity(
            opacity: ch.enabled ? 1 : 0.45,
            child: InkWell(
              borderRadius: BorderRadius.circular(TpixRadius.sm),
              onTap: !ch.enabled || onSelect == null ? null : () => onSelect!(ch.id),
              child: Container(
                width: 150,
                padding: const EdgeInsets.symmetric(horizontal: TpixGap.md, vertical: TpixGap.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TpixRadius.sm),
                  color: ch.id == selected ? AppTheme.primary.withValues(alpha: 0.12) : c.glassColor,
                  border: Border.all(
                    color: ch.id == selected ? AppTheme.primary.withValues(alpha: 0.6) : c.glassBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ch.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: TpixGap.hair),
                    Text(ch.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: c.textMuted)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// ที่อยู่เต็ม + ปุ่มคัดลอก (ผู้ใช้ต้องตรวจได้ทุกตัวอักษร ห้ามตัดเป็น …)
class BridgeAddressLine extends StatelessWidget {
  final String label;
  final String address;

  const BridgeAddressLine({super.key, required this.label, required this.address});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.watch<LocaleProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.textMuted)),
        const SizedBox(height: TpixGap.hair),
        Row(
          children: [
            Expanded(
              child: SelectableText(address,
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: c.text, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: l.t('bridge.copy'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_rounded, size: 16, color: c.textMuted),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) bridgeSnack(context, l.t('bridge.copied'));
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// หนึ่งรายการที่กำลังติดตาม
class BridgeTrackedTile extends StatelessWidget {
  final String title;
  final String txHash;
  final String? explorerUrl;
  final StateBadge? badge;
  final String? badgeLabel;
  final List<Widget> details;
  final VoidCallback onRemove;

  const BridgeTrackedTile({
    super.key,
    required this.title,
    required this.txHash,
    required this.explorerUrl,
    required this.badge,
    required this.badgeLabel,
    required this.details,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final l = context.watch<LocaleProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: TpixGap.sm),
      padding: const EdgeInsets.all(TpixGap.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TpixRadius.sm),
        color: c.glassColor,
        border: Border.all(color: c.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: TpixGap.hair),
                    InkWell(
                      onTap: explorerUrl == null ? null : () => openBridgeUrl(context, explorerUrl),
                      child: Text(bridgeShort(txHash),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: explorerUrl == null ? c.textMuted : AppTheme.primary,
                          )),
                    ),
                  ],
                ),
              ),
              if (badge != null && badgeLabel != null) ...[
                const SizedBox(width: TpixGap.sm),
                Flexible(child: BridgeStateChip(label: badgeLabel!, tone: badge!.tone)),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 2, left: TpixGap.sm),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                ),
              IconButton(
                tooltip: l.t('bridge.remove'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: c.textMuted),
                onPressed: onRemove,
              ),
            ],
          ),
          ...details,
        ],
      ),
    );
  }
}

/// ลิงก์เล็ก (เปิดเบราว์เซอร์)
class BridgeLink extends StatelessWidget {
  final String label;
  final String? url;

  const BridgeLink({super.key, required this.label, required this.url});

  @override
  Widget build(BuildContext context) => url == null
      ? const SizedBox.shrink()
      : InkWell(
          onTap: () => openBridgeUrl(context, url),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: TpixGap.xs),
                const Icon(Icons.open_in_new_rounded, size: 13, color: AppTheme.primary),
              ],
            ),
          ),
        );
}

/// กล่องยืนยันก่อนเซ็น — คืน true เมื่อกดยืนยันเท่านั้น (ปัดทิ้ง/ยกเลิก = false)
Future<bool> showBridgeConfirmSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> rows,
  List<String> notes = const [],
  required String confirmLabel,
  bool danger = false,
}) async {
  final l = context.read<LocaleProvider>();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final c = AppColors.of(sheetCtx);
      final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.sm));
      return Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.9),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(TpixRadius.sheet)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TpixGap.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: c.textMuted.withValues(alpha: 0.3)),
                  ),
                ),
                const SizedBox(height: TpixGap.xl),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: TpixGap.lg),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: Text(r.$1, style: TextStyle(fontSize: 13.5, color: c.textMuted))),
                        const SizedBox(width: TpixGap.md),
                        // ที่อยู่ยาว — ตัดบรรทัดได้ ห้ามตัดเป็น … (ผู้ใช้ต้องตรวจได้ทุกตัวอักษร)
                        Expanded(
                          flex: 6,
                          child: SelectableText(
                            r.$2,
                            textAlign: TextAlign.end,
                            style: TextStyle(fontSize: 13.5, color: c.text, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final n in notes)
                  Padding(
                    padding: const EdgeInsets.only(top: TpixGap.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 16, color: c.brandWarm),
                        const SizedBox(width: TpixGap.xs),
                        Expanded(child: Text(n, style: TextStyle(fontSize: 12, height: 1.4, color: c.brandWarm))),
                      ],
                    ),
                  ),
                const SizedBox(height: TpixGap.xl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: c.glassBorder),
                          shape: shape,
                        ),
                        child: Text(l.t('send.cancel'), style: TextStyle(color: c.textSec)),
                      ),
                    ),
                    const SizedBox(width: TpixGap.md),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        key: const ValueKey('bridge-confirm'),
                        onPressed: () => Navigator.pop(sheetCtx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: danger ? AppTheme.danger : AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: shape,
                        ),
                        child: Text(confirmLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}

/// ถามก่อนลบรายการที่ติดตาม (ลบแค่ในเครื่อง แต่ผู้ใช้อาจต้องใช้ tx hash ติดต่อซัพพอร์ต)
Future<bool> confirmRemoveTracked(BuildContext context) async {
  final l = context.read<LocaleProvider>();
  final c = AppColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TpixRadius.lg)),
      title: Text(l.t('bridge.removeTitle'), style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text(l.t('bridge.removeBody'), style: TextStyle(color: c.textSec, fontSize: 13, height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.t('send.cancel'), style: TextStyle(color: c.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.t('bridge.remove'), style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// โหลดสถานะสะพานไม่สำเร็จ (ยังไม่มีข้อมูลเดิม) — ข้อความ + ปุ่มลองใหม่
class BridgeLoadFailed extends StatelessWidget {
  final VoidCallback onRetry;

  const BridgeLoadFailed({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(TpixGap.xxl),
      children: [
        const SizedBox(height: TpixGap.xxxl),
        BridgeCard(
          padding: const EdgeInsets.all(TpixGap.xxl),
          child: Column(
            children: [
              const Icon(Icons.cloud_off_rounded, color: AppTheme.danger, size: 44),
              const SizedBox(height: TpixGap.lg),
              Text(l.t('bridge.loadFailed'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: TpixGap.xl),
              BridgePrimaryButton(label: l.t('bridge.retry'), onPressed: onRetry),
            ],
          ),
        ),
      ],
    );
  }
}

/// ขั้นตอนการทำงาน (เลขลำดับ + ข้อความ)
class BridgeHowItWorks extends StatelessWidget {
  final String title;
  final List<String> steps;

  const BridgeHowItWorks({super.key, required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BridgeSectionTitle(title),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: TpixGap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.primary.withValues(alpha: 0.18)),
                    child: Text('${i + 1}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  ),
                  const SizedBox(width: TpixGap.sm),
                  Expanded(child: Text(steps[i], style: TextStyle(fontSize: 12, height: 1.45, color: c.textSec))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
