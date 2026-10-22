/// TPIX Wallet — ลิงก์ tpixwallet://wc จากเว็บบนมือถือ + กติกาพากลับเบราว์เซอร์
///
/// สิ่งที่ห้ามพัง:
///   - จับคู่ได้จาก ?uri=wc:… (ถอดรหัส URL แล้วมี symKey) เท่านั้น — ลิงก์ requestId/sessionTopic ห้ามจับคู่
///   - ลิงก์ขยะ / uri ที่ไม่ใช่ wc v2 → invalid (ไม่จับคู่ ไม่นับว่ามาจากเบราว์เซอร์)
///   - ตอบตัวที่ลิงก์รออยู่เสร็จ (และส่งถึง relay แล้ว) ถึงจะพากลับเบราว์เซอร์ — ครั้งเดียว ภายใน 3 นาที
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/services/wc_deep_link.dart';

final _topic = 'a1' * 32;
final _symKey = 'b2' * 32;
final _sessionTopic = 'c3' * 32;
final _wcUri = 'wc:$_topic@2?relay-protocol=irn&symKey=$_symKey&expiryTimestamp=1761130000';

Uri _link(String query) => Uri.parse('tpixwallet://wc$query');

WcDeepLink? _classify(String raw) => WcDeepLink.classify(Uri.parse(raw));

void main() {
  group('classify — แยกประเภทลิงก์', () {
    test('ไม่ใช่ tpixwallet://wc → null (ให้ตัวจัดการเดิมทำต่อ)', () {
      expect(_classify('tpixwallet://sign?message=hi'), isNull);
      expect(_classify('tpixwallet://connect'), isNull);
      expect(_classify('tpixwallet://open'), isNull);
      expect(_classify('ethereum:0x0A3dB168aF6b85e61D81CA78C608BDadAC832DFF@4289'), isNull);
      expect(_classify(_wcUri), isNull, reason: 'wc: ตรง ๆ จัดการทางเดิม');
      expect(_classify('https://tpix.online/wc?uri=x'), isNull);
    });

    test('ลิงก์เปล่า → open (ตัวพิมพ์ใหญ่/มี / ท้ายก็ได้)', () {
      expect(_classify('tpixwallet://wc'), isA<WcOpenLink>());
      expect(_classify('tpixwallet://wc/'), isA<WcOpenLink>());
      expect(_classify('TPIXWALLET://WC'), isA<WcOpenLink>());
      expect(_classify('tpixwallet://wc?foo=bar'), isA<WcOpenLink>());
    });

    test('?uri= เข้ารหัส URL ถูกต้อง → pair พร้อม wc: URI ที่ถอดแล้ว + pairing topic', () {
      final link = WcDeepLink.classify(_link('?uri=${Uri.encodeComponent(_wcUri)}'));
      expect(link, isA<WcPairLink>());
      link as WcPairLink;
      expect(link.uri, _wcUri);
      expect(link.uri, startsWith('wc:'));
      expect(link.pairingTopic, _topic);
    });

    test('intent:// ของ Chrome ถูกส่งเข้าแอปเป็น tpixwallet://wc?uri=… → pair', () {
      // Android แปลง intent://wc?uri=...#Intent;scheme=tpixwallet;... เป็นลิงก์นี้ก่อนส่งให้แอป
      final link = _classify('tpixwallet://wc?uri=${Uri.encodeQueryComponent(_wcUri)}');
      expect(link, isA<WcPairLink>());
    });

    test('★ uri ที่ไม่ได้เข้ารหัส (& แตก symKey ออกไปเป็นพารามิเตอร์ของเรา) → invalid ไม่เดา', () {
      expect(_classify('tpixwallet://wc?uri=$_wcUri'), isA<WcInvalidLink>());
    });

    test('uri ไม่ใช่ wc v2 / ไม่มี symKey / ผิดรูป → invalid', () {
      String q(String v) => '?uri=${Uri.encodeComponent(v)}';
      expect(WcDeepLink.classify(_link(q('https://evil.example/wc'))), isA<WcInvalidLink>());
      expect(WcDeepLink.classify(_link(q('wc:$_topic@1?bridge=x&key=y'))), isA<WcInvalidLink>());
      expect(WcDeepLink.classify(_link(q('wc:$_topic@2?relay-protocol=irn'))), isA<WcInvalidLink>());
      expect(WcDeepLink.classify(_link(q('wc:$_topic@2?symKey=$_symKey'))), isA<WcInvalidLink>());
      expect(WcDeepLink.classify(_link(q('wc:$_topic@2?relay-protocol=irn&symKey=abc'))), isA<WcInvalidLink>());
      expect(WcDeepLink.classify(_link(q('wc:xyz@2?relay-protocol=irn&symKey=$_symKey'))), isA<WcInvalidLink>());
      expect(WcDeepLink.classify(_link(q('wc%3A$_topic'))), isA<WcInvalidLink>(), reason: 'เข้ารหัสซ้ำสองชั้น');
      expect(_classify('tpixwallet://wc?uri='), isA<WcInvalidLink>());
      expect(_classify('tpixwallet://wc?uri=%E0%A4%A'), isA<WcInvalidLink>(), reason: '% เข้ารหัสเสีย');
    });

    test('มี uri= = ลิงก์จับคู่เสมอ ต่อให้มี requestId ติดมาด้วย', () {
      final link = WcDeepLink.classify(_link('?uri=${Uri.encodeComponent(_wcUri)}&requestId=123'));
      expect(link, isA<WcPairLink>());
    });

    test('★ requestId + sessionTopic (sign-client เด้งมาหลังส่งคำขอ) → request ไม่ใช่ pair', () {
      final link = _classify('tpixwallet://wc?requestId=1761130000123456&sessionTopic=$_sessionTopic');
      expect(link, isA<WcRequestLink>());
      link as WcRequestLink;
      expect(link.requestId, 1761130000123456);
      expect(link.sessionTopic, _sessionTopic);
    });

    test('sessionTopic อย่างเดียว (ปุ่ม "เปิด TPIX Wallet เพื่อเซ็น" ของเว็บ) → request ไม่มี id', () {
      final link = _classify('tpixwallet://wc?sessionTopic=$_sessionTopic') as WcRequestLink;
      expect(link.requestId, isNull);
      expect(link.sessionTopic, _sessionTopic);
    });

    test('requestId อย่างเดียว → request ไม่มี topic', () {
      final link = _classify('tpixwallet://wc?requestId=42') as WcRequestLink;
      expect(link.requestId, 42);
      expect(link.sessionTopic, isNull);
    });

    test('href ของเว็บเป็น tpixwallet://wc แล้ว sign-client ต่อ /wc ให้อีกชั้น → ยังอ่านได้', () {
      final link = _classify('tpixwallet://wc/wc?requestId=7&sessionTopic=$_sessionTopic');
      expect(link, isA<WcRequestLink>());
    });

    test('requestId / sessionTopic ขยะ → ทิ้งค่านั้น (ไม่มีอะไรเหลือ = open)', () {
      expect(_classify('tpixwallet://wc?requestId=abc'), isA<WcOpenLink>());
      expect(_classify('tpixwallet://wc?requestId=-5'), isA<WcOpenLink>());
      expect(_classify('tpixwallet://wc?requestId=0'), isA<WcOpenLink>());
      expect(_classify('tpixwallet://wc?sessionTopic=<script>'), isA<WcOpenLink>());
      final mixed = _classify('tpixwallet://wc?requestId=abc&sessionTopic=$_sessionTopic') as WcRequestLink;
      expect(mixed.requestId, isNull);
      expect(mixed.sessionTopic, _sessionTopic);
    });
  });

  group('pairingTopicOf — ตรวจ wc: URI', () {
    test('ถูกต้อง → topic ตัวเล็ก · ช่องว่างหัวท้ายตัดให้ · hex ตัวใหญ่ก็รับ', () {
      expect(WcDeepLink.pairingTopicOf(_wcUri), _topic);
      expect(WcDeepLink.pairingTopicOf('  $_wcUri \n'), _topic);
      final upper = 'wc:${_topic.toUpperCase()}@2?relay-protocol=irn&symKey=${_symKey.toUpperCase()}';
      expect(WcDeepLink.pairingTopicOf(upper), _topic);
    });

    test('ขยะ → null', () {
      for (final raw in ['', 'wc:', 'wc:@2', 'hello', 'wc:expired@2?relay-protocol=irn', 'WC2:$_topic@2']) {
        expect(WcDeepLink.pairingTopicOf(raw), isNull, reason: raw);
      }
    });
  });

  group('WcVisit — พากลับเบราว์เซอร์', () {
    final t0 = DateTime(2026, 10, 22, 10);
    final pairTopic = _topic;

    WcVisit visitOf(String query) => WcVisit.fromLink(WcDeepLink.classify(_link(query))!, t0)!;
    final pairVisit = WcVisit(kind: WcVisitKind.pair, startedAt: t0, topic: pairTopic);

    WcVisitStep step(
      WcVisit visit,
      WcAnswered answered, {
      bool delivered = true,
      bool notice = false,
      bool morePending = false,
      Duration after = const Duration(seconds: 5),
    }) =>
        visit.afterAnswer(answered, delivered: delivered, notice: notice, morePending: morePending, now: t0.add(after));

    WcAnswered proposal({String? topic}) =>
        WcAnswered(kind: WcAnswerKind.proposal, id: 1, topics: {topic ?? pairTopic});
    WcAnswered request(int id, {String? topic, bool auto = false}) =>
        WcAnswered(kind: WcAnswerKind.request, id: id, topics: {topic ?? _sessionTopic}, auto: auto);

    test('fromLink: pair / request / open — ลิงก์เสียไม่นับ', () {
      final pair = visitOf('?uri=${Uri.encodeComponent(_wcUri)}');
      expect(pair.kind, WcVisitKind.pair);
      expect(pair.topic, pairTopic);
      final req = visitOf('?requestId=9&sessionTopic=$_sessionTopic');
      expect(req.kind, WcVisitKind.request);
      expect(req.requestId, 9);
      expect(visitOf('').kind, WcVisitKind.open);
      expect(WcVisit.fromLink(const WcInvalidLink(), t0), isNull);
    });

    test('หมดอายุ 3 นาที · นาฬิกาเครื่องถอยหลัง = หมดอายุ', () {
      expect(pairVisit.isExpired(t0.add(const Duration(minutes: 2, seconds: 59))), isFalse);
      expect(pairVisit.isExpired(t0.add(WcVisit.ttl)), isTrue);
      expect(pairVisit.isExpired(t0.subtract(const Duration(seconds: 1))), isTrue);
    });

    test('pair: อนุมัติ/ปฏิเสธคำขอเชื่อมต่อจากการจับคู่นี้ → กลับครั้งเดียว แล้วจบ', () {
      final s = step(pairVisit, proposal());
      expect(s.moveBack, isTrue);
      expect(s.visit, isNull);
    });

    test('pair: คำขอเชื่อมต่อจากการจับคู่อื่น (สแกน QR บนคอม) → ไม่กลับ รอต่อ', () {
      final s = step(pairVisit, proposal(topic: 'ff' * 32));
      expect(s.moveBack, isFalse);
      expect(s.visit, same(pairVisit));
    });

    test('pair: ตอบคำขอเซ็นก่อนคำขอเชื่อมต่อมา → ไม่กลับ รอต่อ', () {
      final s = step(pairVisit, request(5, topic: pairTopic));
      expect(s.moveBack, isFalse);
      expect(s.visit, same(pairVisit));
    });

    test('requestId: ตอบตัวอื่น → ไม่กลับ · ตอบตัวนั้น → กลับ', () {
      final visit = visitOf('?requestId=77&sessionTopic=$_sessionTopic');
      expect(step(visit, request(76)).moveBack, isFalse);
      expect(step(visit, request(76)).visit, same(visit));
      final done = step(visit, request(77));
      expect(done.moveBack, isTrue);
      expect(done.visit, isNull);
    });

    test('requestId: ตัวนั้นถูกตอบอัตโนมัติ (เช่น สลับเชน) → กลับเลย ไม่ทิ้งผู้ใช้ไว้หน้าว่าง', () {
      final visit = visitOf('?requestId=77&sessionTopic=$_sessionTopic');
      expect(step(visit, request(77, auto: true)).moveBack, isTrue);
      expect(step(visit, request(78, auto: true)).moveBack, isFalse);
    });

    test('sessionTopic อย่างเดียว: ตอบคำขอของ session นั้น → กลับ · session อื่น / ตอบอัตโนมัติ → ไม่', () {
      final visit = visitOf('?sessionTopic=$_sessionTopic');
      expect(step(visit, request(1)).moveBack, isTrue);
      expect(step(visit, request(1, topic: 'dd' * 32)).moveBack, isFalse);
      expect(step(visit, request(1, auto: true)).moveBack, isFalse);
    });

    test('ลิงก์เปล่า: คำตอบถัดไปของผู้ใช้ (คำขอเชื่อมต่อหรือคำขอเซ็น) → กลับ · ตอบอัตโนมัติไม่นับ', () {
      final visit = visitOf('');
      expect(step(visit, proposal(topic: 'ee' * 32)).moveBack, isTrue);
      expect(step(visit, request(3, topic: 'ee' * 32)).moveBack, isTrue);
      expect(step(visit, request(3, auto: true)).moveBack, isFalse);
    });

    test('ส่งไม่ถึงเว็บ / มีข้อความให้อ่าน → อยู่ในแอป และจบรอบนี้', () {
      final failed = step(pairVisit, proposal(), delivered: false);
      expect(failed.moveBack, isFalse);
      expect(failed.visit, isNull);
      final notice = step(visitOf('?requestId=77'), request(77, auto: true), notice: true);
      expect(notice.moveBack, isFalse);
      expect(notice.visit, isNull);
    });

    test('ยังมีคำขอค้าง → อยู่ต่อให้ตอบให้หมด แล้วกลับตอนคำตอบถัดไปที่คิวว่าง', () {
      final visit = visitOf('?requestId=77&sessionTopic=$_sessionTopic');
      final first = step(visit, request(77), morePending: true);
      expect(first.moveBack, isFalse);
      expect(first.visit!.kind, WcVisitKind.open);
      expect(first.visit!.startedAt, t0, reason: 'อายุนับจากลิงก์เดิม ไม่ต่อเวลาให้');
      final last = step(first.visit!, request(80, topic: 'ab' * 32));
      expect(last.moveBack, isTrue);
      expect(last.visit, isNull);
    });

    test('หมดอายุแล้ว → ไม่กลับ และล้างทิ้ง', () {
      final s = step(pairVisit, proposal(), after: const Duration(minutes: 4));
      expect(s.moveBack, isFalse);
      expect(s.visit, isNull);
    });
  });
}
