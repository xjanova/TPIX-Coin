/// TPIX Wallet — เทสต์ "เซ็นด้วยกระเป๋าใบที่ TPIX TRADE ผูกไว้เท่านั้น"
///
/// บั๊กเดิม: คำขอเซ็นจาก TRADE ถูกเซ็นด้วยกระเป๋าที่เปิดอยู่เสมอ
/// ผู้ใช้สลับกระเป๋าหลังเชื่อม TRADE → ลายเซ็น/ธุรกรรมออกจากกระเป๋าผิดใบ
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/models/wallet_info.dart';
import 'package:tpix_wallet/services/peer_sign_service.dart';

const _a = '0x0A3dB168aF6b85e61D81CA78C608BDadAC832DFF'; // checksum ถูก
const _b = '0x8aF94D36Ea0C14C40CDaff5bddE017269A9ccc04';
const _c = '0x94b1254acE355559611890D4EB2d07332eD1fB8A';

final _wallets = [
  WalletInfo(slot: 1, name: 'หลัก', address: _a),
  WalletInfo(slot: 2, name: 'เทรด', address: _b),
];

void main() {
  group('requestedAddress — อ่านที่อยู่จากคำขอ', () {
    test('ใช้พารามิเตอร์ address', () {
      final r = PeerSignService.requestedAddress({'address': _b, 'from': 'trade'});
      expect(r.invalid, isFalse);
      expect(r.address, _b);
    });

    test('from=trade (ชื่อแอป) ไม่ถือเป็นที่อยู่ → ไม่ระบุ (TRADE รุ่นเก่า)', () {
      final r = PeerSignService.requestedAddress({'from': 'trade'});
      expect(r.invalid, isFalse);
      expect(r.address, isNull);
    });

    test('★ from ของ URL ไม่ใช่ที่อยู่ — ต่อให้หน้าตาเป็น 0x… ก็ไม่ใช้ (ตามที่ตกลงกับ TRADE)', () {
      final r = PeerSignService.requestedAddress({'from': _a.toLowerCase()});
      expect(r.address, isNull);
      expect(r.invalid, isFalse);
    });

    test('sign-tx: address + tx.from ตรงกัน → ผ่าน', () {
      final r = PeerSignService.requestedAddress(
          {'address': _a, 'from': 'trade'}, tx: {'from': _a, 'to': _c});
      expect(r.invalid, isFalse);
      expect(r.address, _a);
    });

    test('sign-tx: มีแต่ tx.from (ไม่มี address) → ใช้ tx.from', () {
      final r = PeerSignService.requestedAddress({}, tx: {'from': _a, 'to': _c});
      expect(r.address, _a);
    });

    test('address ว่างเปล่า → invalid (ไม่ใช่ "ไม่ได้ระบุ")', () {
      expect(PeerSignService.requestedAddress({'address': ''}).invalid, isTrue);
    });

    test('ระบุหลายที่แต่ไม่ตรงกัน → invalid (ไม่เดาว่าตัวไหนถูก)', () {
      final r = PeerSignService.requestedAddress({'address': _a}, tx: {'from': _b});
      expect(r.invalid, isTrue);
    });

    test('ระบุหลายที่ ตัวพิมพ์ต่างกันแต่เป็นที่อยู่เดียวกัน → ผ่าน', () {
      final r = PeerSignService.requestedAddress({'address': _a},
          tx: {'from': _a.toLowerCase()});
      expect(r.invalid, isFalse);
    });

    test('รูปแบบผิด / checksum ผิด → invalid', () {
      expect(PeerSignService.requestedAddress({'address': '0x1234'}).invalid, isTrue);
      final badChecksum = '0x0a3dB168aF6b85e61D81CA78C608BDadAC832DFF'; // a ตัวแรกพิมพ์เล็ก
      expect(PeerSignService.requestedAddress({'address': badChecksum}).invalid, isTrue);
      expect(PeerSignService.requestedAddress({}, tx: {'from': 123}).invalid, isTrue);
    });
  });

  group('matchSigner — จับคู่กับกระเป๋าในแอป', () {
    test('ไม่ระบุที่อยู่ → noAddress (ยังเซ็นได้ แต่โชว์ที่อยู่ให้ตรวจ)', () {
      final m = PeerSignService.matchSigner(
          requested: null, activeAddress: _a, wallets: _wallets);
      expect(m.kind, SignerMatchKind.noAddress);
    });

    test('ตรงกับใบที่เปิดอยู่ (ไม่สนตัวพิมพ์) → active', () {
      final m = PeerSignService.matchSigner(
          requested: _a.toLowerCase(), activeAddress: _a, wallets: _wallets);
      expect(m.kind, SignerMatchKind.active);
    });

    test('ตรงกับอีกใบในแอป → otherWallet พร้อมบอกว่าใบไหน (ให้ถามผู้ใช้สลับ)', () {
      final m = PeerSignService.matchSigner(
          requested: _b, activeAddress: _a, wallets: _wallets);
      expect(m.kind, SignerMatchKind.otherWallet);
      expect(m.wallet!.slot, 2);
      expect(m.wallet!.name, 'เทรด');
    });

    test('ไม่ตรงกับใบไหนเลย → notFound (ปฏิเสธ ไม่เซ็นด้วยใบที่เปิดอยู่แทน)', () {
      final m = PeerSignService.matchSigner(
          requested: _c, activeAddress: _a, wallets: _wallets);
      expect(m.kind, SignerMatchKind.notFound);
    });
  });
}
