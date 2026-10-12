/// TPIX Wallet — กติกาของสะพาน (ฟังก์ชันล้วน ไม่มี widget / เน็ต / เก็บข้อมูล) ทดสอบได้ตรงๆ
///
/// พอร์ตจากเว็บ ThaiXTrade:
///   resources/js/utils/bridge.js       — สะพาน USDT หลายเชน ⇄ USDT_TPIX (เชน 4289)
///   resources/js/utils/wtpixBridge.js  — สะพาน TPIX (4289) ⇄ wTPIX (BSC)
/// กติกาต้องตรงกับเว็บทุกข้อ — เว็บกับแอปตัดสิน "กดได้/ไม่ได้" ต่างกันไม่ได้
/// (เทสต์ใน test/bridge_rules_test.dart พอร์ตเคสมาจาก tests/js ของเว็บ)
///
/// กติกาเงิน: ทุกจำนวนเป็น BigInt หน่วยเล็กสุด — ห้ามผ่าน double
/// (1 USDT บน BSC = 1e18 · 0.1 + 0.2 ≠ 0.3 ในโลก float)
///
/// Developed by Xman Studio
library;

import 'dart:convert';

import '../utils/units.dart';
import 'rpc_client.dart';
import 'wallet_service.dart';

/// USDT_TPIX ใช้ 6 ทศนิยม — ฝั่ง mint ตัดเศษที่เกินนี้ทิ้งอยู่แล้ว จึงไม่ให้กรอกเกินตั้งแต่หน้าจอ
const int usdtTpixDecimals = 6;

/// TPIX (เนทีฟ) และ wTPIX ใช้ 18 ทศนิยมทั้งคู่ — ข้ามเชนไม่มีการแปลงหน่วย ไม่มีฝุ่น
const int tpixDecimals = 18;

/// เชน TPIX — ตรึงไว้ในแอป เซิร์ฟเวอร์บอกเลขอื่นมา = ไม่เปิดฟอร์ม
const int bridgeTpixChainId = 4289;

/// ทิศของสะพาน wTPIX
const String wtpixToBsc = 'to_bsc';
const String wtpixToTpix = 'to_tpix';

/// ชนิดรายการของสะพาน USDT
const String usdtDeposit = 'deposit';
const String usdtWithdraw = 'withdraw';

final _amountPattern = RegExp(r'^\d+(\.\d+)?$');
final _txHashPattern = RegExp(r'^0x[0-9a-fA-F]{64}$');
final _addressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');
final _zeroAddressPattern = RegExp(r'^0x0{40}$');
final _ten = BigInt.from(10);

/// ค่าจาก JSON → ข้อความ (เซิร์ฟเวอร์ส่งเป็นสตริงเสมอ แต่รับตัวเลขไว้ด้วย) — null/อย่างอื่น = null
String? _text(Object? v) => v is String ? v : (v is num ? v.toString() : null);

/// tx hash รูปแบบถูกต้อง (0x + 64 hex)
bool isTxHash(String? s) => s != null && _txHashPattern.hasMatch(s.trim());

// ════════════════════════════════════════════════════════════════
//  สะพาน USDT
// ════════════════════════════════════════════════════════════════

/// ข้อความจากช่องกรอก → BigInt หน่วยเล็กสุดของเหรียญ — null ถ้าไม่ใช่ตัวเลขที่รับได้
///
/// จำกัดทศนิยมไม่เกิน 6 ตำแหน่งเสมอ (แม้เหรียญต้นทางจะมี 18 เช่น USDT บน BSC) เพราะ USDT_TPIX มี 6
/// ตัวเลขที่เกินจะกลายเป็นฝุ่นค้างใน vault ที่ผู้ใช้ไม่ได้คืน
/// (จุลภาคถือเป็นตัวคั่นหลักพัน เหมือนเว็บ — ช่องกรอกในแอปแปลง , เป็น . ก่อนถึงตรงนี้)
BigInt? parseAmountToUnits(Object? input, int decimals) {
  final text = (input?.toString() ?? '').trim().replaceAll(',', '');
  if (!_amountPattern.hasMatch(text) || decimals < 0) return null;

  final parts = text.split('.');
  final whole = parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  final maxFrac = decimals < usdtTpixDecimals ? decimals : usdtTpixDecimals;
  if (frac.length > maxFrac) return null;

  final fracUnits = decimals == 0
      ? BigInt.zero
      : BigInt.parse(frac.padRight(decimals, '0').substring(0, decimals));
  return BigInt.parse(whole) * _ten.pow(decimals) + fracUnits;
}

/// BigInt หน่วยเล็กสุด → ข้อความ (ตัดศูนย์ท้าย ไม่มีคอมมา) — ใช้ตัวแปลงกลางของแอป
String formatUnitsPlain(BigInt units, int decimals) => Units.format(units, decimals);

/// ข้อความ USDT (เช่น '0.3' จาก API) → BigInt 6 ทศนิยม — อ่านไม่ออกถือเป็น 0
BigInt usdtToUnits(Object? text) => parseAmountToUnits(text, usdtTpixDecimals) ?? BigInt.zero;

/// ยอดที่ได้รับจริงเมื่อถอน = จำนวน − ค่าธรรมเนียม (หน่วย 6 ทศนิยม) — ไม่ติดลบ
BigInt withdrawReceiveUnits(BigInt amountUnits, Object? feeText) {
  final fee = usdtToUnits(feeText);
  return amountUnits > fee ? amountUnits - fee : BigInt.zero;
}

/// แปลงหน่วยของเหรียญต้นทาง → หน่วย 6 ทศนิยม (เทียบวงเงิน)
/// เชน 18 ทศนิยมหารลง — กรอกได้แค่ 6 ตำแหน่งอยู่แล้ว เศษจึงเป็นศูนย์เสมอ
BigInt toUsdt6(BigInt units, int decimals) {
  final diff = decimals - usdtTpixDecimals;
  return diff >= 0 ? units ~/ _ten.pow(diff) : units * _ten.pow(-diff);
}

/// ผลตรวจยอด — [error] = ห้ามกดส่ง · [warning] = ส่งได้แต่จะรอทีมงานตรวจ (ช้า)
/// ทั้งสองเป็นคีย์ข้อความ + ค่าที่ต้องแทนใน {..}
class AmountCheck {
  final String? error;
  final Map<String, String> params;
  final String? warning;
  final Map<String, String> warningParams;

  const AmountCheck({
    this.error,
    this.params = const {},
    this.warning,
    this.warningParams = const {},
  });

  static const ok = AmountCheck();

  bool get blocked => error != null;
}

/// ตรวจยอดฝากกับวงเงินจากเซิร์ฟเวอร์ (หน่วย 6 ทศนิยม)
///
/// ต่ำกว่าขั้นต่ำ = error (ไม่ถูก mint) · เกินวงเงินต่อครั้ง = warning (รอทีมงานตรวจ)
AmountCheck checkDepositAmount(BigInt? units, Map<String, dynamic>? limits) {
  if (units == null || units <= BigInt.zero) {
    return const AmountCheck(error: 'bridge.errAmountInvalid');
  }

  final minText = _text(limits?['min_deposit']) ?? '1';
  if (units < usdtToUnits(minText)) {
    return AmountCheck(error: 'bridge.errBelowMin', params: {'min': minText});
  }

  final maxText = _text(limits?['max_deposit_per_tx']) ?? '0';
  final max = usdtToUnits(maxText);
  if (max > BigInt.zero && units > max) {
    return AmountCheck(warning: 'bridge.errAboveMax', warningParams: {'max': maxText});
  }

  return AmountCheck.ok;
}

/// ตรวจยอดถอน (หน่วย 6 ทศนิยม) — ลำดับเดียวกับหน้าเว็บ
///
/// [balance] = ยอด USDT_TPIX ที่อ่านได้ (null = อ่านไม่ได้ ไม่บล็อกตรงนี้ — ด่านก่อนส่งอ่านใหม่อีกรอบ)
AmountCheck checkWithdrawAmount(
  BigInt? units, {
  required Object? fee,
  required Map<String, dynamic>? limits,
  BigInt? balance,
}) {
  if (units == null || units <= BigInt.zero) {
    return const AmountCheck(error: 'bridge.errAmountInvalid');
  }
  if (withdrawReceiveUnits(units, fee) <= BigInt.zero) {
    return const AmountCheck(error: 'bridge.errFeeTooHigh');
  }
  final minText = _text(limits?['min_withdraw']) ?? '0';
  if (units < usdtToUnits(minText)) {
    return AmountCheck(error: 'bridge.errBelowMinWithdraw', params: {'min': minText});
  }
  if (balance != null && units > balance) {
    return const AmountCheck(error: 'bridge.errInsufficient');
  }
  return AmountCheck.ok;
}

/// ที่อยู่ EVM ใช้ได้ไหม — ตัวพิมพ์ผสมต้องตรง checksum (EIP-55) ไม่งั้นแปลว่าพิมพ์ผิด
/// ที่อยู่ศูนย์ล้วนใช้ไม่ได้ (เงินหาย) · ใช้ตัวตรวจ EIP-55 ตัวเดียวกับหน้าโอนเงิน
bool isValidEvmAddress(Object? address) {
  final text = (address?.toString() ?? '').trim();
  if (!_addressPattern.hasMatch(text)) return false;
  if (_zeroAddressPattern.hasMatch(text)) return false;
  return WalletService.isValidAddress(text);
}

/// โทนของป้ายสถานะ — ทุกจุดในหน้าใช้ชุดเดียวกัน
enum BridgeTone { success, info, warning, danger, muted }

class StateBadge {
  final String labelKey;
  final BridgeTone tone;

  /// จบแล้ว — เลิกถามเซิร์ฟเวอร์
  final bool done;

  const StateBadge(this.labelKey, this.tone, this.done);
}

/// สถานะที่จบแล้วของสะพาน USDT — เลิกถามเซิร์ฟเวอร์
const Set<String> usdtTerminalStates = {
  'minted', 'paid', 'rejected', 'failed', 'not_a_deposit', 'not_a_withdrawal',
  'ignored', 'below_fee', 'unsupported_chain',
};

const Map<String, BridgeTone> _usdtTones = {
  'minted': BridgeTone.success,
  'paid': BridgeTone.success,
  'confirming': BridgeTone.info,
  'queued': BridgeTone.info,
  'minting': BridgeTone.info,
  'sending': BridgeTone.info,
  'pending': BridgeTone.info,
  'review': BridgeTone.warning,
  'awaiting_liquidity': BridgeTone.warning,
  'unknown': BridgeTone.warning,
  'rejected': BridgeTone.danger,
  'failed': BridgeTone.danger,
  'not_found': BridgeTone.danger,
  'not_a_deposit': BridgeTone.danger,
  'not_a_withdrawal': BridgeTone.danger,
  'unsupported_chain': BridgeTone.danger,
  'ignored': BridgeTone.muted,
  'below_fee': BridgeTone.muted,
};

/// สถานะ → ป้าย + โทนสี (สะพาน USDT)
StateBadge stateBadge(String state) => StateBadge(
      'bridge.state.$state',
      _usdtTones[state] ?? BridgeTone.muted,
      usdtTerminalStates.contains(state),
    );

/// สถานะในตารางของประวัติ (ชื่อฝั่งฐานข้อมูล) → สถานะสาธารณะ — เหมือนที่หน้าเว็บแปลง
String usdtDepositRowState(String status) => switch (status) {
      'needs_review' => 'review',
      'confirmed' => 'queued',
      _ => status,
    };

String usdtWithdrawalRowState(String status) => switch (status) {
      'needs_review' => 'review',
      'pending' => 'queued',
      'ignored' => 'below_fee',
      _ => status,
    };

/// ลิงก์ธุรกรรมบน explorer (ตัด / ท้ายที่ซ้ำ) — ไม่มีข้อมูลครบ = null
String? explorerTx(String? explorer, String? hash) {
  if (explorer == null || explorer.isEmpty || hash == null || hash.isEmpty) return null;
  return '${explorer.replaceFirst(RegExp(r'/+$'), '')}/tx/$hash';
}

/// URL ที่ยอมเปิดในเบราว์เซอร์ — https เท่านั้น มีโฮสต์ ไม่มี user:pass (ค่ามาจากเซิร์ฟเวอร์)
String? safeHttpsUrl(Object? raw) {
  if (raw is! String || raw.length > 500) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  return uri.toString();
}

/// error ระหว่างส่ง → คีย์ข้อความ — ห้ามโชว์ exception ดิบให้ผู้ใช้
String bridgeErrorKey(Object error) {
  if (error is BridgeCheckException) return error.key;
  if (error is WalletChangedException) return 'send.errWalletChanged';
  if (error is InsufficientGasException) return 'bridge.errGas';
  if (error is RpcUnavailableException) return 'bridge.errNetwork';
  if (error is RpcException) {
    final m = error.message.toLowerCase();
    if (m.contains('insufficient')) return 'bridge.errInsufficient';
    if (m.contains('paused')) return 'bridge.errPausedOnChain';
    return 'bridge.errTxFailed';
  }
  return 'bridge.errTxFailed';
}

/// ด่านตรวจก่อนเซ็นไม่ผ่าน — [key] คือข้อความที่ผู้ใช้เห็น (ยังไม่มีอะไรถูกเซ็นหรือส่ง)
class BridgeCheckException implements Exception {
  final String key;
  final Map<String, String> params;

  const BridgeCheckException(this.key, [this.params = const {}]);

  @override
  String toString() => 'BridgeCheckException($key)';
}

// ════════════════════════════════════════════════════════════════
//  สะพาน TPIX ⇄ wTPIX
// ════════════════════════════════════════════════════════════════

/// ข้อความจากช่องกรอก → BigInt wei — null ถ้าไม่ใช่ตัวเลขที่รับได้ (ทศนิยมได้ไม่เกิน 18 ตำแหน่ง)
BigInt? parseTpixAmount(Object? input) {
  final text = (input?.toString() ?? '').trim().replaceAll(',', '');
  if (!_amountPattern.hasMatch(text)) return null;

  final parts = text.split('.');
  final whole = parts[0];
  final frac = parts.length > 1 ? parts[1] : '';
  if (frac.length > tpixDecimals || whole.length > 15) return null;

  return BigInt.parse(whole) * _ten.pow(tpixDecimals) +
      BigInt.parse(frac.padRight(tpixDecimals, '0'));
}

/// BigInt wei → ข้อความ (ตัดศูนย์ท้าย ไม่มีคอมมา)
String formatTpix(BigInt? wei) => Units.format(wei ?? BigInt.zero, tpixDecimals);

/// ข้อความ TPIX จาก API ('100000') → BigInt wei · อ่านไม่ออก/ไม่มีค่า = null
BigInt? tpixTextToWei(Object? text) {
  final s = _text(text);
  if (s == null || s.isEmpty) return null;
  return parseTpixAmount(s);
}

/// ยอดที่ได้จริงอีกฝั่ง = จำนวน − ค่าธรรมเนียม (ไม่ติดลบ)
BigInt receiveWei(BigInt amountWei, Object? feeText) {
  final fee = tpixTextToWei(feeText) ?? BigInt.zero;
  return amountWei > fee ? amountWei - fee : BigInt.zero;
}

Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : const {};

/// ตรวจยอดกับวงเงิน (เว็บ) + เพดานบนสัญญา — [info] คือ data ของ /api/v1/bridge/info?asset=tpix
///
/// error   = ห้ามกด (ต่ำกว่าขั้นต่ำ = ไม่ถูกทำ · เกินเพดานบนสัญญา = revert / ปล่อยไม่ได้)
/// warning = ทำได้ แต่จะรอทีมงานตรวจ (ช้า)
AmountCheck checkWtpixAmount(BigInt? wei, String direction, Map<String, dynamic>? info) {
  if (wei == null || wei <= BigInt.zero) {
    return const AmountCheck(error: 'bridge.wtpix.errAmountInvalid');
  }

  final toBsc = direction == wtpixToBsc;
  final side = toBsc ? 'lock' : 'burn';
  final limits = _map(info?['limits']);
  final vault = _map(info?['vault']);

  final feeText = _text(limits['${side}_fee']);
  final fee = tpixTextToWei(feeText) ?? BigInt.zero;
  if (wei <= fee) {
    return AmountCheck(error: 'bridge.wtpix.errFeeTooHigh', params: {'fee': feeText ?? '0'});
  }

  // ขั้นต่ำ = ค่าที่มากกว่าระหว่างวงเงินเว็บกับ minLock บนสัญญา (ล็อกต่ำกว่า minLock = revert)
  final minWeb = tpixTextToWei(limits['min_$side']) ?? BigInt.zero;
  final minChain = toBsc ? (tpixTextToWei(vault['min_lock']) ?? BigInt.zero) : BigInt.zero;
  final min = minWeb > minChain ? minWeb : minChain;
  if (wei < min) {
    return AmountCheck(error: 'bridge.wtpix.errBelowMin', params: {'min': formatTpix(min)});
  }

  // ล็อกเกิน maxLock บนสัญญา = revert แน่นอน ห้ามส่ง
  final maxLock = toBsc ? tpixTextToWei(vault['max_lock']) : null;
  if (maxLock != null && wei > maxLock) {
    return AmountCheck(
        error: 'bridge.wtpix.errAboveContractMax', params: {'max': formatTpix(maxLock)});
  }

  // เผาเกิน maxPerTx ของคลัง = ปล่อยครั้งเดียวไม่ได้ (depositId ใช้ได้ครั้งเดียว) → ต้องรอเจ้าของขยายเพดาน
  final vaultMax = toBsc ? null : tpixTextToWei(vault['max_per_tx']);
  if (vaultMax != null && wei > vaultMax) {
    return AmountCheck(
        error: 'bridge.wtpix.errAboveContractMax', params: {'max': formatTpix(vaultMax)});
  }

  final maxWebText = _text(limits['max_${side}_per_tx']);
  final maxWeb = tpixTextToWei(maxWebText);
  if (maxWeb != null && maxWeb > BigInt.zero && wei > maxWeb) {
    return AmountCheck(
        warning: 'bridge.wtpix.warnAboveMax', warningParams: {'max': maxWebText ?? ''});
  }

  return AmountCheck.ok;
}

/// สถานะที่จบแล้วของสะพาน wTPIX — เลิกถามเซิร์ฟเวอร์
const Set<String> wtpixTerminalStates = {
  'minted', 'released', 'rejected', 'failed', 'not_a_lock', 'not_a_burn',
  'ignored', 'below_fee', 'unsupported_chain',
};

const Map<String, BridgeTone> _wtpixTones = {
  'minted': BridgeTone.success,
  'released': BridgeTone.success,
  'confirming': BridgeTone.info,
  'queued': BridgeTone.info,
  'minting': BridgeTone.info,
  'releasing': BridgeTone.info,
  'pending': BridgeTone.info,
  'review': BridgeTone.warning,
  'awaiting_liquidity': BridgeTone.warning,
  'unknown': BridgeTone.warning,
  'rejected': BridgeTone.danger,
  'failed': BridgeTone.danger,
  'not_found': BridgeTone.danger,
  'not_a_lock': BridgeTone.danger,
  'not_a_burn': BridgeTone.danger,
  'unsupported_chain': BridgeTone.danger,
  'ignored': BridgeTone.muted,
  'below_fee': BridgeTone.muted,
};

/// สถานะ → ป้าย + โทนสี (ข้อความแยกจากสะพาน USDT — "minted" ของที่นี่คือ wTPIX บน BSC)
StateBadge wtpixStateBadge(String state) => StateBadge(
      'bridge.wtpix.state.$state',
      _wtpixTones[state] ?? BridgeTone.muted,
      wtpixTerminalStates.contains(state),
    );

// ════════════════════════════════════════════════════════════════
//  สถานะจากเซิร์ฟเวอร์ (/status, /withdrawals) — ตรวจทุกช่องก่อนใช้
// ════════════════════════════════════════════════════════════════

final _statePattern = RegExp(r'^[a-z_]{1,40}$');
final _amountTextPattern = RegExp(r'^\d{1,30}(\.\d{1,18})?$');

String? _amountText(Object? v) {
  final s = _text(v);
  return s != null && _amountTextPattern.hasMatch(s) ? s : null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is String && RegExp(r'^\d{1,12}$').hasMatch(v)) return int.parse(v);
  return null;
}

/// หนึ่งแถวในผลสถานะ (หนึ่ง log ในธุรกรรม) — เก็บเฉพาะที่หน้าจอใช้
class BridgeStatusRow {
  /// ยอดที่ได้/จ่ายอีกฝั่ง (mint_amount · payout_amount · receive_amount)
  final String? amount;

  /// ลิงก์ธุรกรรมปลายทาง (mint_url · payout_url · dest_url) — https เท่านั้น
  final String? url;

  /// ถอน USDT: ที่อยู่ + เชนปลายทาง
  final String? targetAddress;
  final int? targetChainId;

  /// wTPIX: ทิศของแถวนี้
  final String? direction;

  const BridgeStatusRow({
    this.amount,
    this.url,
    this.targetAddress,
    this.targetChainId,
    this.direction,
  });

  Map<String, dynamic> toJson() => {
        if (amount != null) 'amount': amount,
        if (url != null) 'url': url,
        if (targetAddress != null) 'targetAddress': targetAddress,
        if (targetChainId != null) 'targetChainId': targetChainId,
        if (direction != null) 'direction': direction,
      };

  static BridgeStatusRow? fromStored(Object? json) {
    if (json is! Map) return null;
    final target = json['targetAddress'];
    final dir = json['direction'];
    return BridgeStatusRow(
      amount: _amountText(json['amount']),
      url: safeHttpsUrl(json['url']),
      targetAddress: isValidEvmAddress(target) ? target as String : null,
      targetChainId: _int(json['targetChainId']),
      direction: dir == wtpixToBsc || dir == wtpixToTpix ? dir as String : null,
    );
  }
}

/// สถานะของธุรกรรมต้นทางหนึ่งรายการ (รวมแบบที่หน้าจอใช้)
class BridgeStatusView {
  final String state;

  /// ขณะรอ finality: ยอดที่เห็นบนเชน (ข้อความจากเซิร์ฟเวอร์) + จำนวนบล็อกยืนยัน
  final String? amount;
  final int? confirmations;
  final bool isFinal;
  final List<BridgeStatusRow> rows;

  const BridgeStatusView({
    required this.state,
    this.amount,
    this.confirmations,
    this.isFinal = false,
    this.rows = const [],
  });

  /// data ของ /status หรือ /withdrawals → มุมมองของหน้าจอ (ช่องที่ผิดรูปถูกทิ้ง ไม่เดา)
  factory BridgeStatusView.fromServer(Map<String, dynamic> data) {
    final rawState = data['state'];
    final state = rawState is String && _statePattern.hasMatch(rawState) ? rawState : 'unknown';
    final rows = <BridgeStatusRow>[];

    for (final d in (data['deposits'] is List ? data['deposits'] as List : const [])) {
      if (d is Map) rows.add(BridgeStatusRow(amount: _amountText(d['mint_amount']), url: safeHttpsUrl(d['mint_url'])));
    }
    for (final w in (data['withdrawals'] is List ? data['withdrawals'] as List : const [])) {
      if (w is! Map) continue;
      final target = w['target_address'];
      rows.add(BridgeStatusRow(
        amount: _amountText(w['payout_amount']),
        url: safeHttpsUrl(w['payout_url']),
        targetAddress: isValidEvmAddress(target) ? (target as String).trim() : null,
        targetChainId: _int(w['target_chain_id']),
      ));
    }
    for (final t in (data['transfers'] is List ? data['transfers'] as List : const [])) {
      if (t is! Map) continue;
      final dir = t['direction'];
      rows.add(BridgeStatusRow(
        amount: _amountText(t['receive_amount']),
        url: safeHttpsUrl(t['dest_url']),
        direction: dir == wtpixToBsc || dir == wtpixToTpix ? dir as String : null,
      ));
    }

    return BridgeStatusView(
      state: state,
      amount: _amountText(data['amount']),
      confirmations: _int(data['confirmations']),
      isFinal: data['final'] == true,
      rows: rows.take(10).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'state': state,
        if (amount != null) 'amount': amount,
        if (confirmations != null) 'confirmations': confirmations,
        if (isFinal) 'final': true,
        if (rows.isNotEmpty) 'rows': [for (final r in rows) r.toJson()],
      };

  static BridgeStatusView? fromStored(Object? json) {
    if (json is! Map) return null;
    final state = json['state'];
    if (state is! String || !_statePattern.hasMatch(state)) return null;
    return BridgeStatusView(
      state: state,
      amount: _amountText(json['amount']),
      confirmations: _int(json['confirmations']),
      isFinal: json['final'] == true,
      rows: [
        for (final r in (json['rows'] is List ? json['rows'] as List : const []))
          ?BridgeStatusRow.fromStored(r),
      ].take(10).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  รายการที่กำลังติดตาม (เก็บในเครื่อง — สะดวกต่อผู้ใช้เท่านั้น แหล่งความจริงคือเชน)
// ════════════════════════════════════════════════════════════════

const int trackLimit = 20;

/// หนึ่งรายการที่ติดตาม
class TrackedTransfer {
  /// USDT: 'deposit' | 'withdraw' · wTPIX: 'to_bsc' | 'to_tpix'
  final String kind;

  /// เชนต้นทางของธุรกรรม (ที่ใช้ถามสถานะ)
  final int chainId;

  /// ตัวเล็กเสมอ
  final String txHash;

  /// ถอน USDT: เชนปลายทาง (ไว้โชว์ก่อนเซิร์ฟเวอร์เห็นรายการ)
  final int? targetChainId;

  /// กระเป๋าที่รายการนี้เป็นของมัน (ตัวเล็ก) — สลับกระเป๋าแล้วไม่โชว์ของใบอื่น
  final String? owner;

  /// ส่งจากแอปนี้ → มีแถวในประวัติธุรกรรมให้อัปเดตสถานะ
  final bool sentHere;

  final int addedAt;

  /// สถานะล่าสุดที่รู้ — เก็บไว้ให้ปิดแอปแล้วกลับมาเห็น และไม่ถามซ้ำเมื่อจบแล้ว
  final BridgeStatusView? status;

  TrackedTransfer({
    required this.kind,
    required this.chainId,
    required String txHash,
    this.targetChainId,
    String? owner,
    this.sentHere = false,
    int? addedAt,
    this.status,
  })  : txHash = txHash.trim().toLowerCase(),
        owner = owner?.toLowerCase(),
        addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// คีย์กันซ้ำ — ธุรกรรมเดียวกันติดตามซ้ำ/กดเบิ้ล = แถวเดิม
  String get key => '$kind:$chainId:$txHash';

  TrackedTransfer withStatus(BridgeStatusView? next) => TrackedTransfer(
        kind: kind,
        chainId: chainId,
        txHash: txHash,
        targetChainId: targetChainId,
        owner: owner,
        sentHere: sentHere,
        addedAt: addedAt,
        status: next,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'chainId': chainId,
        'txHash': txHash,
        if (targetChainId != null) 'targetChainId': targetChainId,
        if (owner != null) 'owner': owner,
        if (sentHere) 'sentHere': true,
        'addedAt': addedAt,
        if (status != null) 'status': status!.toJson(),
      };

  /// null = แถวผิดรูป (ข้าม ไม่เดา)
  static TrackedTransfer? fromJson(Object? json, Set<String> kinds) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final chainId = json['chainId'];
    final hash = json['txHash'];
    if (kind is! String || !kinds.contains(kind)) return null;
    if (chainId is! int || chainId <= 0) return null;
    if (hash is! String || !_txHashPattern.hasMatch(hash)) return null;
    final owner = json['owner'];
    final added = json['addedAt'];
    return TrackedTransfer(
      kind: kind,
      chainId: chainId,
      txHash: hash,
      targetChainId: _int(json['targetChainId']),
      owner: owner is String && _addressPattern.hasMatch(owner) ? owner : null,
      sentHere: json['sentHere'] == true,
      addedAt: added is int ? added : 0,
      status: BridgeStatusView.fromStored(json['status']),
    );
  }
}

/// ชนิดรายการของแต่ละสะพาน
const Set<String> usdtTrackKinds = {usdtDeposit, usdtWithdraw};
const Set<String> wtpixTrackKinds = {wtpixToBsc, wtpixToTpix};

/// อ่านรายการที่ติดตาม — ข้อมูลเสีย/ไม่ใช่ JSON = รายการว่าง ไม่พัง
List<TrackedTransfer> decodeTracked(String? raw, Set<String> kinds) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! List) return [];
    return [
      for (final e in parsed) ?TrackedTransfer.fromJson(e, kinds),
    ].take(trackLimit).toList();
  } on FormatException {
    return [];
  }
}

String encodeTracked(List<TrackedTransfer> list) =>
    jsonEncode([for (final e in list.take(trackLimit)) e.toJson()]);

/// เพิ่มรายการ (ซ้ำ = ย้ายขึ้นบนสุด ไม่เพิ่มแถวใหม่ · เก็บสถานะเดิมไว้ถ้าแถวใหม่ยังไม่มี)
List<TrackedTransfer> addTracked(List<TrackedTransfer> list, TrackedTransfer entry) {
  TrackedTransfer? previous;
  for (final e in list) {
    if (e.key == entry.key) previous = e;
  }
  final next = entry.status == null && previous?.status != null
      ? entry.withStatus(previous!.status)
      : entry;
  return [next, ...list.where((e) => e.key != next.key)].take(trackLimit).toList();
}
