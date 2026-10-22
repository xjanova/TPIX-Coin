/// TPIX Wallet — WalletConnectService: พากลับเบราว์เซอร์หลังตอบ (ไม่ต้องมี SDK / relay จริง)
///
/// สิ่งที่ห้ามพัง:
///   - มาจากลิงก์ของเบราว์เซอร์ → ตอบตัวที่ลิงก์รอเสร็จแล้วย้ายแอปไปข้างหลัง "ครั้งเดียว"
///   - flow อื่น (สแกน QR บนคอม / ปุ่มในแอป) → ไม่เคยย้ายแอปไปข้างหลัง
///   - relay ส่งคำขอมาก่อนลิงก์ requestId แล้วตอบเองไปแล้ว → ลิงก์มาทีหลังพากลับทันที ไม่ค้างหน้า "กำลังรอ…"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/services/walletconnect_service.dart';
import 'package:tpix_wallet/services/wc_deep_link.dart';

final _pairTopic = 'a1' * 32;
final _sessionTopic = 'c3' * 32;
final _wcUri = 'wc:$_pairTopic@2?relay-protocol=irn&symKey=${'b2' * 32}';

WcDeepLink _link(String query) => WcDeepLink.classify(Uri.parse('tpixwallet://wc$query'))!;

WcAnswered _proposal({String? topic}) =>
    WcAnswered(kind: WcAnswerKind.proposal, id: 1, topics: {topic ?? _pairTopic});

WcAnswered _request(int id, {bool auto = false}) =>
    WcAnswered(kind: WcAnswerKind.request, id: id, topics: {_sessionTopic}, auto: auto);

void main() {
  late int moves;
  late WalletConnectService wc;

  setUp(() {
    moves = 0;
    wc = WalletConnectService(moveToBack: () async {
      moves++;
      return true;
    });
  });

  tearDown(() => wc.dispose());

  test('★ ลิงก์จับคู่ → ตอบคำขอเชื่อมต่อของการจับคู่นั้นเสร็จ → ย้ายไปข้างหลังครั้งเดียว', () async {
    wc.beginBrowserVisit(_link('?uri=${Uri.encodeComponent(_wcUri)}'));
    expect(wc.awaitingBrowserProposal, isTrue);

    await wc.debugAfterAnswer(_proposal());
    expect(moves, 1);
    expect(wc.awaitingBrowserProposal, isFalse);

    await wc.debugAfterAnswer(_proposal());
    expect(moves, 1, reason: 'กลับครั้งเดียว — คำตอบถัดไปไม่ย้ายแอปอีก');
  });

  test('★ ส่งคำตอบไม่ถึงเว็บ → อยู่ในแอป (ให้เห็นข้อความผิดพลาด)', () async {
    wc.beginBrowserVisit(_link('?uri=${Uri.encodeComponent(_wcUri)}'));
    await wc.debugAfterAnswer(_proposal(), delivered: false, notice: true);
    expect(moves, 0);
  });

  test('★ ลิงก์ requestId → ตอบตัวอื่นไม่กลับ · ตอบตัวนั้นถึงกลับ', () async {
    wc.beginBrowserVisit(_link('?requestId=7&sessionTopic=$_sessionTopic'));
    expect(wc.awaitingBrowserRequest, isTrue);
    await wc.debugAfterAnswer(_request(6));
    expect(moves, 0);
    await wc.debugAfterAnswer(_request(7));
    expect(moves, 1);
  });

  test('★ ไม่ได้มาจากเบราว์เซอร์ (สแกน QR บนคอม / ปุ่มในแอป) → ไม่ย้ายแอปไปข้างหลังเลย', () async {
    await wc.debugAfterAnswer(_proposal());
    await wc.debugAfterAnswer(_request(3));
    expect(moves, 0);

    wc.beginBrowserVisit(_link(''));
    wc.endBrowserVisit(); // ผู้ใช้กดสแกน QR เองในแอป
    await wc.debugAfterAnswer(_proposal());
    expect(moves, 0);
  });

  test('★ relay มาก่อนลิงก์: คำขอถูกตอบเองไปแล้ว → ลิงก์ requestId ของตัวนั้นพากลับทันที ไม่ค้างรอ', () async {
    await wc.debugAfterAnswer(_request(9, auto: true)); // เช่น สลับเชน — ยังไม่มีลิงก์ตอนตอบ
    expect(moves, 0);

    wc.beginBrowserVisit(_link('?requestId=9&sessionTopic=$_sessionTopic'));
    await Future<void>.delayed(Duration.zero);
    expect(moves, 1);
    expect(wc.awaitingBrowserRequest, isFalse);
  });

  test('relay มาก่อนลิงก์ แต่คำตอบนั้นมีข้อความให้อ่าน (เว็บขอกระเป๋าอื่น) → อยู่ในแอป ไม่โชว์ "กำลังรอ…"', () async {
    await wc.debugAfterAnswer(_request(10, auto: true), notice: true);
    wc.beginBrowserVisit(_link('?requestId=10'));
    await Future<void>.delayed(Duration.zero);
    expect(moves, 0);
    expect(wc.awaitingBrowserRequest, isFalse);
  });

  test('ลิงก์ใหม่แทนรอบเดิมเสมอ · ลิงก์เสียล้างรอบเดิม', () async {
    wc.beginBrowserVisit(_link('?requestId=7'));
    wc.beginBrowserVisit(const WcInvalidLink());
    await wc.debugAfterAnswer(_request(7));
    expect(moves, 0);
  });
}
