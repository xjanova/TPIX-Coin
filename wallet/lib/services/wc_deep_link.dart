/// TPIX Wallet — ลิงก์ tpixwallet://wc จากเว็บบนมือถือ + กติกา "พากลับเบราว์เซอร์"
///
/// สัญญากับเว็บ tpix.online (ฝั่งเว็บเขียนตามนี้เป๊ะ):
///   - `tpixwallet://wc?uri={wc: URI เข้ารหัส URL}` → จับคู่ (ทางเดียวที่ทำให้เกิดการจับคู่)
///   - `tpixwallet://wc?requestId={int}&sessionTopic={topic}`
///       sign-client ของเว็บเด้งมาหลังส่ง personal_sign / eth_sendTransaction
///       ไม่ใช่ URI จับคู่ — แค่พาแอปขึ้นหน้าจอ ตัวคำขอมาทาง relay ตามปกติ
///   - `tpixwallet://wc?sessionTopic={topic}`
///       ปุ่ม "เปิด TPIX Wallet เพื่อเซ็น" ของเว็บ (Chrome บล็อกการเด้งอัตโนมัติถ้าผู้ใช้ไม่ได้แตะ)
///   - `tpixwallet://wc` เปล่า ๆ → เปิดหน้าเชื่อมต่อ dApp
///   (Android Chrome อาจยิงเป็น `intent://wc?uri=...#Intent;scheme=tpixwallet;...` —
///    ระบบส่งเข้าแอปเป็น `tpixwallet://wc?uri=...` เหมือนกัน)
///
/// ทุกแบบที่ใช้ได้ = ผู้ใช้มาจากเบราว์เซอร์ → ตอบเสร็จแล้วพากลับเบราว์เซอร์ ([WcVisit])
///
/// 🔴 wc: URI มี symKey (กุญแจถอดรหัสช่องคุยกับเว็บ) — ห้าม log / ห้ามลง breadcrumb
///
/// Developed by Xman Studio
library;

final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

/// ประเภทของลิงก์ tpixwallet://wc
sealed class WcDeepLink {
  const WcDeepLink();

  /// แยกประเภท — null = ไม่ใช่ลิงก์ tpixwallet://wc (ให้ตัวจัดการลิงก์เดิมทำต่อ)
  ///
  /// path ไม่สนใจ: เว็บบางตัวเก็บ href เป็น tpixwallet://wc แล้ว sign-client ต่อท้าย /wc?... ให้อีกชั้น
  static WcDeepLink? classify(Uri uri) {
    if (uri.scheme.toLowerCase() != 'tpixwallet' || uri.host.toLowerCase() != 'wc') return null;

    final Map<String, String> query;
    try {
      query = uri.queryParameters;
    } catch (_) {
      // % เข้ารหัสเสีย — ไม่เดาว่าตั้งใจส่งอะไรมา
      return const WcInvalidLink();
    }

    // มี uri= = ลิงก์จับคู่เสมอ (ไม่ตีความเป็นแบบอื่นต่อให้มี requestId ติดมา)
    if (query.containsKey('uri')) {
      final wcUri = query['uri']!.trim();
      final topic = pairingTopicOf(wcUri);
      return topic == null ? const WcInvalidLink() : WcPairLink(uri: wcUri, pairingTopic: topic);
    }

    final requestId = _positiveInt(query['requestId']);
    final topic = _topicOrNull(query['sessionTopic']);
    if (requestId != null || topic != null) {
      return WcRequestLink(requestId: requestId, sessionTopic: topic);
    }
    return const WcOpenLink();
  }

  /// ตรวจ wc: URI แบบ WalletConnect v2 — คืน topic ของการจับคู่ถ้าใช้ได้, null = ห้ามจับคู่
  ///
  /// รูปแบบ: `wc:{topic 64 hex}@2?relay-protocol={...}&symKey={64 hex}[&...]`
  static String? pairingTopicOf(String raw) {
    try {
      final u = Uri.parse(raw.trim());
      if (u.scheme.toLowerCase() != 'wc') return null;
      final parts = u.path.split('@');
      if (parts.length != 2 || parts[1] != '2') return null;
      final topic = parts[0];
      if (!_hex64.hasMatch(topic)) return null;
      final query = u.queryParameters;
      if (!_hex64.hasMatch(query['symKey'] ?? '')) return null;
      if ((query['relay-protocol'] ?? '').trim().isEmpty) return null;
      return topic.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  static int? _positiveInt(String? raw) {
    final n = int.tryParse((raw ?? '').trim());
    return n != null && n > 0 ? n : null;
  }

  /// topic ของ WalletConnect = 32 ไบต์ hex — ค่าอื่นทิ้ง (ใช้แค่จับคู่ "มาจากเว็บไหน" ไม่ใช่ความลับ)
  static String? _topicOrNull(String? raw) {
    final t = (raw ?? '').trim();
    return _hex64.hasMatch(t) ? t.toLowerCase() : null;
  }
}

/// จับคู่กับเว็บ — [uri] คือ wc: URI ที่ถอดรหัส URL แล้วและผ่านการตรวจรูปแบบแล้ว
final class WcPairLink extends WcDeepLink {
  final String uri;

  /// topic ของการจับคู่ — ใช้ดูว่าคำขอเชื่อมต่อที่เข้ามาเป็นของลิงก์นี้
  final String pairingTopic;

  const WcPairLink({required this.uri, required this.pairingTopic});
}

/// เว็บเพิ่งส่งคำขอ (sign-client เด้งมา / ปุ่มเปิดกระเป๋าเพื่อเซ็น) — ไม่จับคู่ แค่เปิดหน้าให้เห็นคำขอ
final class WcRequestLink extends WcDeepLink {
  final int? requestId;
  final String? sessionTopic;

  const WcRequestLink({this.requestId, this.sessionTopic});
}

/// tpixwallet://wc เปล่า ๆ — เปิดหน้าเชื่อมต่อ dApp
final class WcOpenLink extends WcDeepLink {
  const WcOpenLink();
}

/// มี uri= แต่ไม่ใช่ wc: URI ที่ใช้ได้ (ไม่มี symKey / ไม่ใช่ v2 / เข้ารหัสผิด) — ห้ามจับคู่
final class WcInvalidLink extends WcDeepLink {
  const WcInvalidLink();
}

// ================================================================
//  "มาจากเบราว์เซอร์" — ตอบเสร็จแล้วพากลับไปหน้าเว็บ
// ================================================================

enum WcVisitKind {
  /// ?uri= — รอคำขอเชื่อมต่อ (proposal) จากการจับคู่นี้
  pair,

  /// ?requestId= / ?sessionTopic= — รอคำขอเซ็น/ส่งธุรกรรมจากเว็บ
  request,

  /// ลิงก์เปล่า (หรือรอบที่ตอบตัวที่รอไปแล้วแต่ยังมีคำขออื่นค้าง) — คำตอบถัดไปของผู้ใช้
  open,
}

enum WcAnswerKind { proposal, request }

/// คำตอบที่เพิ่งส่งให้เว็บ
class WcAnswered {
  final WcAnswerKind kind;

  /// id ของ proposal / request
  final int id;

  /// proposal: pairing topic · request: session topic (+ pairing topic ของ session นั้น)
  final Set<String> topics;

  /// ระบบตอบเองโดยไม่ถามผู้ใช้ (เปลี่ยนเชน / คำขอรูปแบบผิด / เมธอดที่ไม่รองรับ)
  final bool auto;

  const WcAnswered({required this.kind, required this.id, this.topics = const {}, this.auto = false});
}

/// ผลหลังตอบ: ย้ายแอปไปข้างหลังเลยไหม + การมาเยือนที่เหลืออยู่ (null = จบแล้ว)
typedef WcVisitStep = ({bool moveBack, WcVisit? visit});

/// แอปถูกเปิดขึ้นมาจากลิงก์ tpixwallet://wc ของเบราว์เซอร์ (หมดอายุใน [ttl])
///
/// กติกา: ตอบตัวที่ลิงก์นั้นรออยู่เสร็จ (ส่งถึง relay แล้ว) และไม่มีคำขออื่นค้าง → ย้ายแอปไปข้างหลังครั้งเดียว
/// เบราว์เซอร์ที่เปิดลิงก์มาจะกลับขึ้นมาเอง — flow อื่น (สแกน QR บนคอม / ปุ่มในแอป / TPIX Trade) ไม่เคยมี visit
class WcVisit {
  /// ตอบช้ากว่านี้ = ผู้ใช้น่าจะทำอย่างอื่นไปแล้ว ไม่พากลับ
  static const ttl = Duration(minutes: 3);

  final WcVisitKind kind;
  final DateTime startedAt;

  /// request id ที่ sign-client บอกมา — มีค่า = รอคำขอตัวนี้ตัวเดียว
  final int? requestId;

  /// pair: pairing topic · request: session topic
  final String? topic;

  const WcVisit({required this.kind, required this.startedAt, this.requestId, this.topic});

  /// ลิงก์เสียไม่นับ — ไม่มีอะไรให้ตอบ (ผู้ใช้ต้องอ่านข้อความผิดพลาดในแอป)
  static WcVisit? fromLink(WcDeepLink link, DateTime now) => switch (link) {
        WcPairLink(:final pairingTopic) => WcVisit(kind: WcVisitKind.pair, startedAt: now, topic: pairingTopic),
        WcRequestLink(:final requestId, :final sessionTopic) =>
          WcVisit(kind: WcVisitKind.request, startedAt: now, requestId: requestId, topic: sessionTopic),
        WcOpenLink() => WcVisit(kind: WcVisitKind.open, startedAt: now),
        WcInvalidLink() => null,
      };

  /// นาฬิกาเครื่องถอยหลัง (ผู้ใช้ตั้งเวลาเอง) = ถือว่าหมดอายุ ไม่ค้างตลอดไป
  bool isExpired(DateTime now) => now.isBefore(startedAt) || now.difference(startedAt) >= ttl;

  /// คำตอบนี้คือตัวที่ลิงก์รออยู่ไหม
  bool matches(WcAnswered a) {
    final rid = requestId;
    // sign-client บอก id มาแล้ว = รอตัวนี้ตัวเดียว (ตอบเองอัตโนมัติก็นับ เช่น เปลี่ยนเชน)
    if (rid != null) return a.kind == WcAnswerKind.request && a.id == rid;
    if (a.auto) return false;
    if (kind == WcVisitKind.pair && a.kind != WcAnswerKind.proposal) return false;
    final t = topic;
    return t == null || a.topics.contains(t);
  }

  /// [delivered] = SDK ส่งคำตอบถึง relay แล้ว · [notice] = แอปกำลังโชว์ข้อความที่ผู้ใช้ต้องอ่าน
  /// [morePending] = ยังมีคำขอ/คำขอเชื่อมต่อรอในคิว (หลังเอาตัวที่เพิ่งตอบออกแล้ว)
  WcVisitStep afterAnswer(
    WcAnswered answered, {
    required bool delivered,
    required bool notice,
    required bool morePending,
    required DateTime now,
  }) {
    if (isExpired(now)) return (moveBack: false, visit: null);
    if (!matches(answered)) return (moveBack: false, visit: this);
    // ส่งไม่ถึงเว็บ / มีข้อความต้องอ่าน → อยู่ในแอปให้ผู้ใช้เห็น (เว็บไม่ได้รอแล้ว — จบรอบนี้)
    if (!delivered || notice) return (moveBack: false, visit: null);
    // ยังมีคำขออื่นค้าง → อยู่ต่อให้ตอบให้หมด แล้วค่อยกลับตอนคิวว่าง (คำตอบถัดไปของผู้ใช้)
    if (morePending) {
      return (moveBack: false, visit: WcVisit(kind: WcVisitKind.open, startedAt: startedAt));
    }
    return (moveBack: true, visit: null);
  }
}
