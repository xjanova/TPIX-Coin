/// TPIX Wallet — ตรรกะของหน้า "กิจกรรม" (ไม่มี UI — เทสต์ได้ล้วน ๆ)
///
/// แถวประวัติในเครื่อง (TxRecord) ไม่ได้เก็บ "ชนิด" กับ "เชน" ไว้ — หน้านี้อนุมานจากข้อมูลที่มีจริงเท่านั้น
///   ชนิด:
///     1. บริดจ์   = tx hash อยู่ในรายการที่หน้าบริดจ์จดไว้ในเครื่อง (BridgeTracker)
///     2. แลก      = ส่งเข้าที่อยู่ router ของ DEX ที่แอปรู้จัก (ChainConfig.dexRouterAddress)
///     3. สัญญา    = มูลค่า 0 และไม่ใช่โทเค็น (เช่น approve) — ไม่ใช่ "ส่ง 0 BNB"
///     4. ส่ง / รับ = ตาม direction
///   เชน:
///     บริดจ์ → เชนต้นทางที่จดไว้ · แลก → เชนของ router · โทเค็น → เชนของสัญญาที่แอปรู้จัก
///     เหรียญหลัก → จากสัญลักษณ์ (TPIX/BNB/POL/ETH) · ไม่แน่ใจ = null (ไม่เดา ไม่โชว์เชนผิด)
///
/// Developed by Xman Studio
library;

import '../models/chain_config.dart';
import '../models/token_info.dart';
import '../models/tx_record.dart';
import '../services/bridge_rules.dart';

enum ActivityKind { send, receive, swap, bridge, contract }

/// ชิปตัวกรองบนหน้า (ทั้งหมด / ส่ง / รับ / แลก / บริดจ์)
enum ActivityFilter { all, send, receive, swap, bridge }

enum ActivityStatus { pending, confirmed, failed }

/// ที่เก็บรายการติดตามของหน้าบริดจ์ (ต้องตรงกับ BridgeTracker.storageKey — มีเทสต์ล็อกไว้)
const String activityUsdtBridgeKey = 'bridge_tracked_usdt_v1';
const String activityWtpixBridgeKey = 'bridge_tracked_wtpix_v1';

/// ข้อมูลจากรายการที่หน้าบริดจ์จดไว้
class ActivityBridgeHint {
  /// deposit / withdraw (USDT) · to_bsc / to_tpix (wTPIX)
  final String kind;

  /// เชนต้นทาง (ที่ธุรกรรมนี้อยู่)
  final int fromChainId;

  /// เชนปลายทาง — null = ไม่รู้ (ถอน USDT ที่ยังไม่ได้ระบุ)
  final int? toChainId;

  /// จำนวนบล็อกยืนยันที่เซิร์ฟเวอร์เห็นล่าสุด (ระหว่างรอ finality)
  final int? confirmations;

  /// สะพานจบงานแล้ว (จ่าย/คืน/ล้ม) — ไม่ใช่แค่ธุรกรรมต้นทางผ่าน
  final bool done;

  const ActivityBridgeHint({
    required this.kind,
    required this.fromChainId,
    required this.toChainId,
    this.confirmations,
    this.done = false,
  });

  bool get isWtpix => wtpixTrackKinds.contains(kind);

  /// เหรียญที่ข้ามสะพาน (ใช้ตั้งชื่อแถว)
  String get asset => isWtpix ? 'TPIX' : 'USDT';
}

/// สร้างคำใบ้จากรายการของ BridgeTracker — เฉพาะของกระเป๋า [owner] (รายการไม่มีเจ้าของ = นับด้วย)
Map<String, ActivityBridgeHint> bridgeHintsFrom(Iterable<TrackedTransfer> entries, String? owner) {
  final me = owner?.toLowerCase();
  final out = <String, ActivityBridgeHint>{};
  for (final e in entries) {
    if (e.owner != null && me != null && e.owner != me) continue;
    final wtpix = wtpixTrackKinds.contains(e.kind);
    final s = e.status;
    final done = s != null && (wtpix ? wtpixStateBadge(s.state) : stateBadge(s.state)).done;
    final (from, to) = switch (e.kind) {
      usdtDeposit => (e.chainId, bridgeTpixChainId),
      usdtWithdraw => (e.chainId, e.targetChainId),
      wtpixToBsc => (e.chainId, 56),
      wtpixToTpix => (e.chainId, bridgeTpixChainId),
      _ => (e.chainId, e.targetChainId),
    };
    // รายการเดียวกันจดซ้ำได้ (กดเบิ้ล/ติดตามซ้ำ) — เก็บตัวแรก (ใหม่สุด)
    out.putIfAbsent(
      e.txHash,
      () => ActivityBridgeHint(
        kind: e.kind,
        fromChainId: from,
        toChainId: to,
        confirmations: s?.confirmations,
        done: done,
      ),
    );
  }
  return out;
}

/// ข้อมูลประกอบที่ใช้อนุมาน (สร้างครั้งเดียวต่อรอบโหลด)
class ActivityContext {
  /// สัญญาโทเค็น (ตัวเล็ก) → chainId
  final Map<String, int> tokenChains;

  /// router ของ DEX (ตัวเล็ก) → chainId
  final Map<String, int> routerChains;

  /// tx hash (ตัวเล็ก) → ข้อมูลบริดจ์
  final Map<String, ActivityBridgeHint> bridges;

  /// ที่อยู่ (ตัวเล็ก) → ชื่อที่ผู้ใช้ตั้ง (กระเป๋าตัวเอง / รายชื่อผู้ติดต่อ)
  final Map<String, String> names;

  const ActivityContext({
    this.tokenChains = const {},
    this.routerChains = const {},
    this.bridges = const {},
    this.names = const {},
  });

  /// รวมของที่แอปรู้จักอยู่แล้ว (เหรียญในตัวแอป + router ทุกเชน) กับของผู้ใช้
  factory ActivityContext.build({
    Iterable<TokenInfo> tokens = const [],
    Map<String, ActivityBridgeHint> bridges = const {},
    Map<String, String> names = const {},
  }) {
    final tokenChains = <String, int>{};
    final routers = <String, int>{};
    for (final c in ChainConfig.all) {
      for (final t in c.knownTokens) {
        tokenChains[t.address.toLowerCase()] = c.chainId;
      }
      final r = c.dexRouterAddress;
      if (r != null) routers[r.toLowerCase()] = c.chainId;
    }
    for (final t in tokens) {
      tokenChains[t.contractAddress.toLowerCase()] = t.chainId;
    }
    return ActivityContext(
      tokenChains: tokenChains,
      routerChains: routers,
      bridges: {for (final e in bridges.entries) e.key.toLowerCase(): e.value},
      names: {for (final e in names.entries) e.key.toLowerCase(): e.value},
    );
  }
}

/// หนึ่งแถวบนหน้า
class ActivityItem {
  final TxRecord tx;
  final ActivityKind kind;

  /// เชนที่อนุมานได้ — null = ไม่แน่ใจ
  final int? chainId;
  final DateTime time;

  /// ชื่อของอีกฝั่ง (ถ้าผู้ใช้ตั้งไว้)
  final String? counterpartyName;
  final ActivityBridgeHint? bridge;

  const ActivityItem({
    required this.tx,
    required this.kind,
    required this.chainId,
    required this.time,
    this.counterpartyName,
    this.bridge,
  });

  ActivityStatus get status => switch (tx.status) {
        'pending' => ActivityStatus.pending,
        'failed' => ActivityStatus.failed,
        _ => ActivityStatus.confirmed,
      };

  bool get isSent => tx.direction == 'sent';

  /// ที่อยู่ของอีกฝั่ง
  String get counterparty => isSent ? tx.toAddress : tx.fromAddress;

  /// ยังไม่จบ: ธุรกรรมรอเชน หรือสะพานยังไม่จ่ายปลายทาง (ธุรกรรมต้นทางล้ม = จบแล้ว)
  bool get inProgress =>
      status == ActivityStatus.pending ||
      (bridge != null && !bridge!.done && status != ActivityStatus.failed);

  /// มีจำนวนให้โชว์ไหม (แลกแบบโทเค็น→x บันทึกมูลค่า 0 ไว้ — ไม่โชว์ "−0 BNB")
  bool get hasAmount {
    try {
      return BigInt.parse(tx.value) > BigInt.zero;
    } catch (_) {
      return false;
    }
  }
}

/// เชนของเหรียญหลักจากสัญลักษณ์ (ใช้กับธุรกรรมที่ไม่ใช่โทเค็นเท่านั้น)
int? nativeChainForSymbol(String symbol) => switch (symbol.toUpperCase()) {
      'TPIX' => ChainConfig.tpix.chainId,
      'BNB' => ChainConfig.bsc.chainId,
      'POL' || 'MATIC' => ChainConfig.polygon.chainId,
      'ETH' => ChainConfig.ethereum.chainId,
      _ => null,
    };

/// เวลาของธุรกรรม (บล็อก > เวลาที่บันทึกในเครื่อง) เป็นเวลาท้องถิ่น
DateTime activityTime(TxRecord tx) {
  if (tx.timestamp != null) {
    return DateTime.fromMillisecondsSinceEpoch(tx.timestamp! * 1000);
  }
  return (DateTime.tryParse(tx.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal();
}

bool _isZero(String v) {
  try {
    return BigInt.parse(v) == BigInt.zero;
  } catch (_) {
    return true;
  }
}

ActivityItem describeActivity(TxRecord tx, ActivityContext ctx) {
  final hash = tx.txHash.toLowerCase();
  final to = tx.toAddress.toLowerCase();
  final bridge = ctx.bridges[hash];

  final ActivityKind kind;
  int? chain;
  if (bridge != null) {
    kind = ActivityKind.bridge;
    chain = bridge.fromChainId;
  } else if (tx.direction == 'sent' && ctx.routerChains.containsKey(to)) {
    kind = ActivityKind.swap;
    chain = ctx.routerChains[to];
  } else if (tx.tokenAddress == null && _isZero(tx.value)) {
    kind = ActivityKind.contract;
  } else {
    kind = tx.direction == 'sent' ? ActivityKind.send : ActivityKind.receive;
  }

  chain ??= tx.tokenAddress != null
      ? ctx.tokenChains[tx.tokenAddress!.toLowerCase()]
      : nativeChainForSymbol(tx.symbol);

  final other = (tx.direction == 'sent' ? tx.toAddress : tx.fromAddress).toLowerCase();
  return ActivityItem(
    tx: tx,
    kind: kind,
    chainId: chain,
    time: activityTime(tx),
    counterpartyName: ctx.names[other],
    bridge: bridge,
  );
}

/// ทุกแถว ใหม่สุดก่อน
List<ActivityItem> buildActivityFeed(Iterable<TxRecord> txs, ActivityContext ctx) {
  final list = [for (final t in txs) describeActivity(t, ctx)];
  // sort เสถียร: เวลาเท่ากันคงลำดับเดิม
  final indexed = list.asMap().entries.toList()
    ..sort((a, b) {
      final c = b.value.time.compareTo(a.value.time);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// ผ่านตัวกรองชนิด + เชนไหม ([chainId] null = ทุกเชน)
/// เลือกเชนแล้ว: แถวที่ไม่รู้เชนไม่ผ่าน (ไม่เดาว่าอยู่เชนนั้น)
bool activityMatches(ActivityItem item, ActivityFilter filter, int? chainId) {
  if (chainId != null && item.chainId != chainId) return false;
  return switch (filter) {
    ActivityFilter.all => true,
    ActivityFilter.send => item.kind == ActivityKind.send,
    ActivityFilter.receive => item.kind == ActivityKind.receive,
    ActivityFilter.swap => item.kind == ActivityKind.swap,
    ActivityFilter.bridge => item.kind == ActivityKind.bridge,
  };
}

/// แถวของหนึ่งวัน
class ActivityDay {
  /// เที่ยงคืนของวันนั้น (เวลาท้องถิ่น)
  final DateTime day;
  final List<ActivityItem> items;

  const ActivityDay(this.day, this.items);
}

/// แบ่งเป็นวัน (ลำดับตาม [items] ซึ่งเรียงใหม่สุดก่อนแล้ว)
List<ActivityDay> groupActivityByDay(List<ActivityItem> items) {
  final out = <ActivityDay>[];
  for (final it in items) {
    final local = it.time.toLocal();
    final d = DateTime(local.year, local.month, local.day);
    if (out.isNotEmpty && out.last.day == d) {
      out.last.items.add(it);
    } else {
      out.add(ActivityDay(d, [it]));
    }
  }
  return out;
}

const _thMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const _enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// หัวกลุ่มวัน: วันนี้ / เมื่อวาน / 12 ต.ค. (ปีอื่นต่อท้ายปี — ไทยเป็น พ.ศ.)
/// [today]/[yesterday] = ข้อความที่แปลแล้ว
String activityDayLabel(
  DateTime day,
  DateTime now, {
  required bool thai,
  required String today,
  required String yesterday,
}) {
  final n = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final diff = DateTime.utc(n.year, n.month, n.day).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (diff == 0) return today;
  if (diff == 1) return yesterday;
  final sameYear = d.year == n.year;
  if (thai) {
    final base = '${d.day} ${_thMonths[d.month - 1]}';
    return sameYear ? base : '$base ${d.year + 543}';
  }
  final base = '${_enMonths[d.month - 1]} ${d.day}';
  return sameYear ? base : '$base, ${d.year}';
}

/// HH:mm (ไม่ขึ้นกับภาษาเครื่อง)
String activityClock(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// จำนวนจากหน่วยย่อย (BigInt) → ข้อความมีคั่นหลักพัน — ไม่ผ่าน double
///
/// ≥ 1 แสดงทศนิยมไม่เกิน 4 · < 1 ไม่เกิน 6 · ตัดเศษทิ้ง (ไม่ปัดขึ้นให้ดูมากกว่าจริง)
/// เล็กกว่าทศนิยมที่แสดงได้ = "<0.000001"
String formatActivityAmount(BigInt raw, int decimals) {
  final neg = raw.isNegative;
  final abs = raw.abs();
  if (abs == BigInt.zero) return '0';
  final base = BigInt.from(10).pow(decimals);
  final whole = abs ~/ base;
  final maxFrac = whole > BigInt.zero ? 4 : 6;
  var frac = decimals == 0 ? '' : (abs % base).toString().padLeft(decimals, '0');
  if (frac.length > maxFrac) frac = frac.substring(0, maxFrac);
  frac = frac.replaceFirst(RegExp(r'0+$'), '');
  if (whole == BigInt.zero && frac.isEmpty) {
    return '${neg ? '-' : ''}<0.${'0' * (maxFrac - 1)}1';
  }
  final grouped = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final body = frac.isEmpty ? grouped : '$grouped.$frac';
  return neg ? '-$body' : body;
}

/// จำนวนของแถว (ตามทศนิยมของเหรียญนั้น)
String activityAmountText(ActivityItem item) {
  BigInt raw;
  try {
    raw = BigInt.parse(item.tx.value);
  } catch (_) {
    raw = BigInt.zero;
  }
  return formatActivityAmount(raw, item.tx.decimals);
}

/// ลิงก์ explorer ของธุรกรรม — ใช้ explorer ของเชนที่อนุมานได้
/// ไม่รู้เชน = explorer ของ TPIX Chain (พฤติกรรมเดิมของแอป)
String activityExplorerUrl(ActivityItem item) {
  final chain = item.chainId == null ? ChainConfig.tpix : ChainConfig.byId(item.chainId!);
  return '${chain.explorerUrl}/tx/${item.tx.txHash}';
}

/// ที่อยู่ย่อ 0x8f3C…C2d5
String activityShortAddress(String a) =>
    a.length < 12 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';
