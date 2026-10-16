/// TPIX Wallet — เทสต์ตัวอ่านคำขอชำระเงิน EIP-681 (ethereum: URI)
///
/// ร้านจับคู่การชำระด้วยยอดเป๊ะทุก wei — ยอดที่อ่านได้ต้องตรงทุกหลัก ห้ามผ่าน double
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/utils/eip681.dart';

const _shop = '0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1'; // checksum ถูก
const _lower = '0x8af94d36ea0c14c40cdaff5bdde017269a9ccc04';
const _token = '0x0A3dB168aF6b85e61D81CA78C608BDadAC832DFF';

PaymentRequest _ok(String uri) {
  final r = Eip681.parse(uri);
  expect(r.isOk, isTrue, reason: 'ต้องอ่านผ่าน: $uri (ได้ ${r.error})');
  return r.request!;
}

Eip681Error? _err(String uri) => Eip681.parse(uri).error;

void main() {
  group('โอนเหรียญหลัก', () {
    test('รูปที่ร้านใช้: ที่อยู่ + @4289 + value เป็น wei', () {
      final r = _ok('ethereum:$_shop@4289?value=12345678901234567890');
      expect(r.recipient, _shop);
      expect(r.chainId, 4289);
      expect(r.tokenAddress, isNull);
      expect(r.rawAmount, BigInt.parse('12345678901234567890'));
      expect(r.amountIn(18), BigInt.parse('12345678901234567890'));
    });

    test('ยอดมีแท็ก 8 ตำแหน่ง — ต่างกัน 1 wei ก็ต้องอ่านได้ตรงทุกหลัก', () {
      final r = _ok('ethereum:$_shop@4289?value=150000000123456781');
      expect(r.rawAmount, BigInt.parse('150000000123456781'));
    });

    test('value แบบวิทยาศาสตร์แปลงแบบแม่นยำ (ไม่ผ่าน double)', () {
      expect(_ok('ethereum:$_shop@4289?value=1.5e18').rawAmount, BigInt.parse('1500000000000000000'));
      expect(_ok('ethereum:$_shop@4289?value=1.5E18').rawAmount, BigInt.parse('1500000000000000000'));
      expect(_ok('ethereum:$_shop@4289?value=15e%2B17').rawAmount, BigInt.parse('1500000000000000000'));
      expect(_ok('ethereum:$_shop@4289?value=1.5e+18').rawAmount, BigInt.parse('1500000000000000000'));
      // double จะได้ 1.2345678901234568e+21 — ต้องได้ตรงทุกหลัก
      expect(_ok('ethereum:$_shop?value=1.234567890123456789012e21').rawAmount,
          BigInt.parse('1234567890123456789012'));
      expect(_ok('ethereum:$_shop?value=2000e-3').rawAmount, BigInt.two);
      expect(_err('ethereum:$_shop?value=2014e-3'), Eip681Error.badAmount);
    });

    test('ไม่มี chain / ไม่มียอด ก็อ่านได้', () {
      final r = _ok('ethereum:$_lower');
      expect(r.recipient, _lower);
      expect(r.chainId, isNull);
      expect(r.hasAmount, isFalse);
      expect(_ok('ethereum:$_shop@4289').hasAmount, isFalse);
    });

    test('pay- prefix และ scheme ตัวใหญ่', () {
      expect(_ok('ethereum:pay-$_shop@4289?value=1').rawAmount, BigInt.one);
      expect(_ok('ETHEREUM:$_shop@4289?value=1').recipient, _shop);
    });

    test('amount= (ทศนิยม TPIX) แปลงเป็น wei', () {
      expect(_ok('ethereum:$_shop@4289?amount=1.000000001234567812').rawAmount,
          BigInt.parse('1000000001234567812'));
      expect(_ok('ethereum:$_shop@4289?amount=2').rawAmount, BigInt.parse('2000000000000000000'));
    });

    test('value กับ amount ตรงกัน = ผ่าน, ไม่ตรง = ไม่รับ', () {
      expect(_ok('ethereum:$_shop@4289?value=1500000000000000000&amount=1.5').rawAmount,
          BigInt.parse('1500000000000000000'));
      expect(_err('ethereum:$_shop@4289?value=1500000000000000001&amount=1.5'),
          Eip681Error.conflictingAmount);
    });

    test('พารามิเตอร์อื่น (gas) ข้ามได้', () {
      expect(_ok('ethereum:$_shop@4289?value=5&gas=21000').rawAmount, BigInt.from(5));
    });

    test('Uri.parse → toString (เส้นทาง deep link) ยังอ่านได้ยอดเดิม', () {
      const raw = 'ethereum:$_shop@4289?value=1.5e+18';
      expect(_ok(Uri.parse(raw).toString()).rawAmount, BigInt.parse('1500000000000000000'));
    });
  });

  group('ไม่รับข้อมูลผิดรูป', () {
    test('ไม่ใช่ ethereum: → notEip681 (ให้ไปอ่านเป็นที่อยู่ล้วนต่อ)', () {
      expect(_err(_shop), Eip681Error.notEip681);
      expect(_err('wc:abc@2'), Eip681Error.notEip681);
      expect(_err(''), Eip681Error.notEip681);
    });

    test('ที่อยู่ผิด', () {
      expect(_err('ethereum:0x1234'), Eip681Error.badAddress);
      expect(_err('ethereum:${_shop}00@4289'), Eip681Error.badAddress);
      expect(_err('ethereum:shop.eth@4289?value=1'), Eip681Error.badAddress);
      // checksum พัง (สลับตัวพิมพ์ตัวแรก)
      expect(_err('ethereum:0x0a4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1@4289'), Eip681Error.badAddress);
    });

    test('chain id ผิด', () {
      expect(_err('ethereum:$_shop@?value=1'), Eip681Error.badChainId);
      expect(_err('ethereum:$_shop@0x10c1'), Eip681Error.badChainId);
      expect(_err('ethereum:$_shop@0'), Eip681Error.badChainId);
      expect(_err('ethereum:$_shop@42x'), Eip681Error.badChainId);
    });

    test('ยอดผิด: ติดลบ / ไม่ใช่จำนวนเต็ม / ตัวอักษร / เกิน uint256 / ว่าง', () {
      expect(_err('ethereum:$_shop@4289?value=-1'), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?value=1.5'), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?value=1e-1'), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?value=abc'), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?value=0x10'), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?value='), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?value=1e78'), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?value=1e999'), Eip681Error.badAmount);
      expect(_err('ethereum:$_shop@4289?amount=0.0000000000000000001'), Eip681Error.badAmount);
    });

    test('query เพี้ยน / คีย์ซ้ำ / ฟังก์ชันที่ไม่รองรับ', () {
      expect(_err('ethereum:$_shop@4289?value=1&value=2'), Eip681Error.badParam);
      expect(_err('ethereum:$_shop@4289?value'), Eip681Error.badParam);
      expect(_err('ethereum:$_shop@4289?value=%E0%A4%A'), Eip681Error.badParam);
      expect(_err('ethereum:$_shop@4289/approve?address=$_lower&uint256=1'),
          Eip681Error.unsupportedFunction);
      expect(_err('ethereum:$_shop#frag'), Eip681Error.badAddress);
    });

    test('ยาวเกินกำหนด', () {
      expect(_err('ethereum:$_shop?gas=${'1' * 3000}'), Eip681Error.badParam);
    });
  });

  group('ERC-20 transfer', () {
    test('address + uint256', () {
      final r = _ok('ethereum:$_token@4289/transfer?address=$_shop&uint256=1.5e6');
      expect(r.isToken, isTrue);
      expect(r.tokenAddress, _token);
      expect(r.recipient, _shop);
      expect(r.rawAmount, BigInt.from(1500000));
    });

    test('amount= ทศนิยม แปลงตามทศนิยมของโทเค็นตอนใช้', () {
      final r = _ok('ethereum:$_token@4289/transfer?address=$_shop&amount=1.25');
      expect(r.rawAmount, isNull);
      expect(r.amountIn(6), BigInt.from(1250000));
      expect(r.amountIn(1), isNull); // 1.25 ใส่ใน 1 ตำแหน่งไม่ได้ — ไม่ปัด
    });

    test('ไม่มีผู้รับ / ผู้รับผิด / แนบเหรียญหลัก / ยอดกำกวม = ไม่รับ', () {
      expect(_err('ethereum:$_token@4289/transfer?uint256=1'), Eip681Error.badParam);
      expect(_err('ethereum:$_token@4289/transfer?address=0x12&uint256=1'), Eip681Error.badParam);
      expect(_err('ethereum:$_token@4289/transfer?address=$_shop&uint256=1&value=5'), Eip681Error.badParam);
      expect(_err('ethereum:$_token@4289/transfer?address=$_shop&uint256=1&amount=1'),
          Eip681Error.conflictingAmount);
    });
  });

  group('parseScaled', () {
    test('ค่าขอบ', () {
      expect(Eip681.parseScaled('0', 18), BigInt.zero);
      expect(Eip681.parseScaled('0.0e5', 0), BigInt.zero);
      expect(Eip681.parseScaled('.5', 1), BigInt.from(5));
      expect(Eip681.parseScaled('+7', 0), BigInt.from(7));
      expect(Eip681.parseScaled('.', 0), isNull);
      expect(Eip681.parseScaled('1..2', 0), isNull);
      final max = (BigInt.one << 256) - BigInt.one;
      expect(Eip681.parseScaled(max.toString(), 0), max);
      expect(Eip681.parseScaled((max + BigInt.one).toString(), 0), isNull);
    });
  });
}
