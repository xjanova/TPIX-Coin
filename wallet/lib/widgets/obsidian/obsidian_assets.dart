/// TPIX Wallet — ที่อยู่ไฟล์ภาพของธีม Obsidian + ข้อมูลภาพประจำเชน
///
/// ★ โลโก้เชน/เหรียญทุกตัวเป็นของทางการเท่านั้น (Trust Wallet assets ชุดเดียวกับ
///   config/chains.php ของเว็บ) ห้ามวาดเลียนแบบ — เจ้าของย้ำเรื่องนี้ชัดเจน
///   TPIX ใช้ path เวกเตอร์ทางการ (ดู tpix_monogram.dart) ไม่ใช่ภาพ
///
/// Developed by Xman Studio
library;

import 'package:flutter/material.dart';

/// ไอคอน 3D (ChatGPT ตามที่เจ้าของอนุมัติ)
/// - ไทล์มีกรอบกระจก: send receive swap bridge node scan
/// - ไอคอนลอย (ไม่มีกรอบ): ที่เหลือ
/// - ตราระดับมาสเตอร์โหนด: tier*
abstract final class ObsidianIcons {
  static const _d = 'assets/obsidian/icons';

  // ── ไทล์มีกรอบ ──
  static const send = '$_d/ic_send.webp';
  static const receive = '$_d/ic_receive.webp';
  static const swap = '$_d/ic_swap.webp';
  static const bridge = '$_d/ic_bridge.webp';
  static const node = '$_d/ic_node.webp';
  static const scan = '$_d/ic_scan.webp';

  // ── ไอคอนลอย ──
  static const home = '$_d/ic_home.webp';
  static const activity = '$_d/ic_activity.webp';
  static const settings = '$_d/ic_settings.webp';
  static const link = '$_d/ic_link.webp';
  static const bell = '$_d/ic_bell.webp';
  static const shield = '$_d/ic_shield.webp';
  static const wallet = '$_d/ic_wallet.webp';
  static const addToken = '$_d/ic_addtoken.webp';
  static const contacts = '$_d/ic_contacts.webp';
  static const language = '$_d/ic_language.webp';
  static const theme = '$_d/ic_theme.webp';
  static const fingerprint = '$_d/ic_fingerprint.webp';
  static const backup = '$_d/ic_backup.webp';
  static const lock = '$_d/ic_lock.webp';
  static const signHistory = '$_d/ic_signhist.webp';
  static const bug = '$_d/ic_bug.webp';
  static const network = '$_d/ic_network.webp';
  static const update = '$_d/ic_update.webp';
  static const trash = '$_d/ic_trash.webp';
  static const coins = '$_d/ic_coins.webp';
  static const chart = '$_d/ic_chart.webp';
  static const info = '$_d/ic_info.webp';
  static const copy = '$_d/ic_copy.webp';
  static const share = '$_d/ic_share.webp';
  static const qr = '$_d/ic_qr.webp';

  // ── ตราระดับมาสเตอร์โหนด ──
  static const tierLight = '$_d/ic_tier_light.webp';
  static const tierSentinel = '$_d/ic_tier_sentinel.webp';
  static const tierGuardian = '$_d/ic_tier_guardian.webp';
  static const tierValidator = '$_d/ic_tier_validator.webp';
}

/// โลโก้สีทางการ (วงกลม) ของเชน/เหรียญ
abstract final class ObsidianLogos {
  static const _d = 'assets/obsidian/logos';
  static const bnb = '$_d/chip_bnb.webp';
  static const pol = '$_d/chip_pol.webp';
  static const eth = '$_d/chip_eth.webp';
  static const usdt = '$_d/chip_usdt.webp';
  static const usdc = '$_d/chip_usdc.webp';

  /// โลโก้ของเหรียญที่รู้จัก (ไม่ต้องรอโหลดจากเน็ต) — null = ไม่มีในชุด
  static String? forSymbol(String symbol) => switch (symbol.toUpperCase()) {
        'BNB' => bnb,
        'POL' || 'MATIC' => pol,
        'ETH' => eth,
        'USDT' => usdt,
        'USDC' => usdc,
        _ => null,
      };
}

/// ภาพ + สีประจำเชน (บัตรโลหะ / ตราในหลุมบัตร / ชิป / สีเรืองแสง)
@immutable
class ObsidianChainArt {
  final int chainId;

  /// หน้าบัตรโลหะเปล่า (มีหลุมวงกลมว่างที่ cx .806w, cy .476h, r .138w)
  final String card;

  /// หน้ากากขาวของตราเชนทางการ — null = TPIX (วาดจาก path เวกเตอร์)
  final String? mask;

  /// โลโก้สีวงกลม — null = TPIX (ใช้ TpixCoinLogo)
  final String? chip;

  /// สีประจำเชน (ขอบชิปที่เลือก / เรืองแสงรอบตรา)
  final Color accent;

  /// สีเรืองแสงใต้สำรับบัตร
  final Color glow;

  /// ไล่สีโลหะที่ปั๊มลงบนตรา (CSS linear-gradient 160deg)
  final List<Color> metal;
  final List<double> metalStops;

  /// ป้ายสั้นบนชิปเลือกเชน
  final String shortLabel;

  const ObsidianChainArt({
    required this.chainId,
    required this.card,
    required this.mask,
    required this.chip,
    required this.accent,
    required this.glow,
    required this.metal,
    required this.metalStops,
    required this.shortLabel,
  });

  bool get isTpix => mask == null;

  static const _c = 'assets/obsidian/cards';
  static const _l = 'assets/obsidian/logos';

  static const tpix = ObsidianChainArt(
    chainId: 4289,
    card: '$_c/card_tpix.jpg',
    mask: null,
    chip: null,
    accent: Color(0xFF8B5CF6),
    glow: Color(0x8C8B5CF6), // rgba(139,92,246,.55)
    metal: [],
    metalStops: [],
    shortLabel: 'TPIX',
  );

  static const bsc = ObsidianChainArt(
    chainId: 56,
    card: '$_c/card_bnb.jpg',
    mask: '$_l/mask_bnb.webp',
    chip: ObsidianLogos.bnb,
    accent: Color(0xFFF3BA2F),
    glow: Color(0x73F3BA2F), // .45
    metal: [Color(0xFFFFF6D2), Color(0xFFF3BA2F), Color(0xFFB7791F), Color(0xFFFFE7A3)],
    metalStops: [0, 0.42, 0.72, 1],
    shortLabel: 'BNB',
  );

  static const polygon = ObsidianChainArt(
    chainId: 137,
    card: '$_c/card_pol.jpg',
    mask: '$_l/mask_pol.webp',
    chip: ObsidianLogos.pol,
    accent: Color(0xFF8247E5),
    glow: Color(0x8C8247E5), // .55
    metal: [Color(0xFFF5EFFF), Color(0xFFB79BFF), Color(0xFF8247E5), Color(0xFFD8C7FF)],
    metalStops: [0, 0.38, 0.68, 1],
    shortLabel: 'Polygon',
  );

  static const ethereum = ObsidianChainArt(
    chainId: 1,
    card: '$_c/card_eth.jpg',
    mask: '$_l/mask_eth.webp',
    chip: ObsidianLogos.eth,
    accent: Color(0xFF627EEA),
    glow: Color(0x80627EEA), // .50
    metal: [Color(0xFFFFFFFF), Color(0xFFC7D2FE), Color(0xFF627EEA), Color(0xFFE0E7FF)],
    metalStops: [0, 0.36, 0.70, 1],
    shortLabel: 'ETH',
  );

  static const all = [tpix, bsc, polygon, ethereum];

  /// เชนที่ไม่มีภาพเฉพาะ → ใช้ชุดของ TPIX (แอปรองรับแค่ 4 เชนนี้อยู่แล้ว)
  static ObsidianChainArt of(int chainId) =>
      all.firstWhere((a) => a.chainId == chainId, orElse: () => tpix);
}
