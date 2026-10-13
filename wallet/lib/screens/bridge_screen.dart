/// TPIX Wallet — หน้าสะพานข้ามเชน (พอร์ตจากหน้า /bridge ของเว็บ)
///
/// สองสะพานในหน้าเดียว แยกกันทุกอย่าง (สวิตช์เปิดปิด · คิว · กุญแจฝั่งเซิร์ฟเวอร์):
///   USDT          — USDT หลายเชน ⇄ USDT บน TPIX Chain (bridge_usdt_panel.dart)
///   TPIX ⇄ wTPIX  — TPIX บนเชน 4289 ⇄ wTPIX บน BSC (bridge_wtpix_panel.dart)
///
/// สะพานรุ่นเก่าของแอป (โอนเหรียญเข้ากระเป๋าค่าธรรมเนียมแล้วยิง /bridge/fee + /bridge/initiate)
/// ถูกถอดจากเซิร์ฟเวอร์แล้ว — หน้านี้ไม่พึ่ง /api/v1/fees เลย
///
/// Developed by Xman Studio
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../core/themes/tokens.dart';
import '../core/themes/widgets/screen_background.dart';
import '../services/bridge_service.dart';
import '../widgets/bridge_obsidian.dart';
import '../widgets/bridge_widgets.dart';
import '../widgets/obsidian/obsidian.dart';
import 'bridge_usdt_panel.dart';
import 'bridge_wtpix_panel.dart';

enum BridgeAsset { usdt, tpix }

class BridgeScreen extends StatefulWidget {
  final BridgeAsset initialAsset;

  const BridgeScreen({super.key, this.initialAsset = BridgeAsset.usdt});

  @override
  State<BridgeScreen> createState() => _BridgeScreenState();
}

class _BridgeScreenState extends State<BridgeScreen> {
  late BridgeAsset _asset = widget.initialAsset;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    // ธีม Obsidian: หัวหน้า + แท็บสินทรัพย์แบบ mock — แผงสะพานทั้งสองตัวเดิม (แต่ละตัวมีหน้าตา Obsidian ของตัวเอง)
    if (bridgeIsObsidian(context)) return _buildObsidian(l);
    final c = AppColors.of(context);
    final tpix = _asset == BridgeAsset.tpix;

    return Scaffold(
      body: TpixScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(TpixGap.sm, TpixGap.lg, TpixGap.sm, TpixGap.sm),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios, color: c.text),
                    ),
                    const SizedBox(width: TpixGap.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tpix ? l.t('bridge.wtpix.title') : l.t('bridge.title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.text),
                          ),
                          Text(
                            tpix ? l.t('bridge.wtpix.subtitle') : l.t('bridge.subtitle'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l.t('bridge.reservesLink'),
                      onPressed: () => openBridgeUrl(
                        context,
                        tpix ? '${BridgeService.reservesUrl}?asset=tpix' : BridgeService.reservesUrl,
                      ),
                      icon: Icon(Icons.verified_user_outlined, color: c.textSec),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(TpixGap.lg, 0, TpixGap.lg, TpixGap.md),
                child: BridgeSegmented<BridgeAsset>(
                  options: [
                    (BridgeAsset.usdt, l.t('bridge.wtpix.assetUsdt')),
                    (BridgeAsset.tpix, l.t('bridge.wtpix.assetTpix')),
                  ],
                  value: _asset,
                  onChanged: (a) => setState(() => _asset = a),
                ),
              ),
              Expanded(
                // แต่ละสะพานมีสถานะ/ตัวติดตามของตัวเอง — สลับแล้วเริ่มใหม่ (รายการที่ติดตามอยู่ในเครื่อง)
                child: tpix
                    ? const WtpixBridgePanel(key: ValueKey('wtpix-panel'))
                    : const UsdtBridgePanel(key: ValueKey('usdt-panel')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObsidian(LocaleProvider l) {
    final tpix = _asset == BridgeAsset.tpix;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: ObsidianPageScrim()),
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(24, math.max(52.0, top + 8), 24, 14),
                child: Column(
                  children: [
                    ObsidianPageHeader(
                      title: l.t('obs.bridge.title'),
                      backLabel: l.t('obs.back'),
                      // ปุ่มขวา = ตรวจเงินหนุน (Proof of Reserves) เหมือนปุ่มเดิม
                      trailing: ObsidianHeaderTile(
                        asset: ObsidianIcons.shield,
                        label: l.t('bridge.reservesLink'),
                        onTap: () => openBridgeUrl(
                          context,
                          tpix ? '${BridgeService.reservesUrl}?asset=tpix' : BridgeService.reservesUrl,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ObsidianSegmented<BridgeAsset>(
                      options: [
                        ObsidianSegmentOption(BridgeAsset.usdt, l.t('bridge.wtpix.assetUsdt'), leading: bridgeUsdtLogo(22)),
                        ObsidianSegmentOption(BridgeAsset.tpix, l.t('bridge.wtpix.assetTpix'), leading: bridgeTpixLogo(22)),
                      ],
                      value: _asset,
                      onChanged: (a) => setState(() => _asset = a),
                    ),
                  ],
                ),
              ),
              Expanded(
                // แต่ละสะพานมีสถานะ/ตัวติดตามของตัวเอง — สลับแล้วเริ่มใหม่ (รายการที่ติดตามอยู่ในเครื่อง)
                child: tpix
                    ? const WtpixBridgePanel(key: ValueKey('wtpix-panel'))
                    : const UsdtBridgePanel(key: ValueKey('usdt-panel')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
