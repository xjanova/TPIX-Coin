/// TPIX Wallet — เทสต์การแปลงจำนวนเงิน + calldata ของ ERC-20 transfer
///
/// ของเดิมแปลงผ่าน double: 0.1 TPIX กลายเป็น 100000000000000006 wei (ส่งเกิน)
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:tpix_wallet/utils/units.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

BigInt _pow10(int n) => BigInt.from(10).pow(n);

void main() {
  group('Units.parse — ไม่เสียความแม่นยำ', () {
    test('0.1 TPIX = 10^17 wei พอดี (double ให้ ...006)', () {
      expect(Units.parse('0.1', 18).value, _pow10(17));
    });

    test('USDT 6 ทศนิยม: 1.5 → 1,500,000', () {
      expect(Units.parse('1.5', 6).value, BigInt.from(1500000));
      expect(Units.parse('0.000001', 6).value, BigInt.one);
      expect(Units.parse('.5', 6).value, BigInt.from(500000));
      expect(Units.parse('2.', 6).value, BigInt.from(2000000));
    });

    test('จำนวนมากๆ ไม่ล้น', () {
      expect(Units.parse('7000000000', 18).value, BigInt.from(7000000000) * _pow10(18));
      expect(Units.parse('123456789.123456789123456789', 18).value,
          BigInt.parse('123456789123456789123456789'));
    });

    test('จุลภาคตัวเดียว = ทศนิยม (คีย์บอร์ดบางภาษา)', () {
      expect(Units.parse('1,5', 6).value, BigInt.from(1500000));
    });

    test('ทศนิยมเกินที่เหรียญรองรับ → แจ้ง ไม่ปัดทิ้งเงียบๆ', () {
      expect(Units.parse('1.1234567', 6).error, AmountError.tooManyDecimals);
      // ศูนย์ท้ายเกินมาไม่เปลี่ยนค่า → รับ
      expect(Units.parse('1.500000000', 6).value, BigInt.from(1500000));
    });

    test('ข้อความผิดรูป', () {
      expect(Units.parse('', 18).error, AmountError.empty);
      expect(Units.parse('   ', 18).error, AmountError.empty);
      expect(Units.parse('abc', 18).error, AmountError.invalid);
      expect(Units.parse('-1', 18).error, AmountError.invalid);
      expect(Units.parse('1e5', 18).error, AmountError.invalid);
      expect(Units.parse('1.2.3', 18).error, AmountError.invalid);
      expect(Units.parse('1,000.5', 18).error, AmountError.invalid,
          reason: 'มีทั้ง , และ . = กำกวม ไม่เดา');
      expect(Units.parse('.', 18).error, AmountError.invalid);
    });

    test('ศูนย์ → error zero', () {
      expect(Units.parse('0', 18).error, AmountError.zero);
      expect(Units.parse('0.000', 6).error, AmountError.zero);
    });

    test('decimals = 0', () {
      expect(Units.parse('42', 0).value, BigInt.from(42));
      expect(Units.parse('4.2', 0).error, AmountError.tooManyDecimals);
    });
  });

  group('Units.format', () {
    test('ตัดศูนย์ท้าย เก็บทุกหลักที่มีค่า', () {
      expect(Units.format(BigInt.from(1500000), 6), '1.5');
      expect(Units.format(_pow10(18), 18), '1');
      expect(Units.format(BigInt.one, 18), '0.000000000000000001');
      expect(Units.format(BigInt.zero, 6), '0');
    });

    test('parse(format(x)) == x (ปุ่ม MAX ได้ยอดเต็มจริง)', () {
      final x = BigInt.parse('123456789012345678901');
      expect(Units.parse(Units.format(x, 18), 18).value, x);
    });
  });

  group('ERC-20 transfer calldata', () {
    test('transfer(to, 1 USDT) เข้ารหัสถูกต้อง', () {
      const to = '0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7';
      final data = Units.encodeErc20Transfer(to, BigInt.from(1000000));
      expect(data.length, 4 + 32 + 32);
      expect(
        HEX.encode(data),
        'a9059cbb'
        '000000000000000000000000d2eab07809921fcb36c7ab72d7b5d8d2c12a67d7'
        '00000000000000000000000000000000000000000000000000000000000f4240',
      );
    });

    test('selector = keccak256("transfer(address,uint256)")[0..4]', () {
      final selector = keccakUtf8('transfer(address,uint256)').sublist(0, 4);
      final data = Units.encodeErc20Transfer(
          '0x0000000000000000000000000000000000000001', BigInt.one);
      expect(data.sublist(0, 4), selector);
    });

    test('ที่อยู่ผิด / จำนวนติดลบ / เกิน uint256 → ArgumentError', () {
      expect(() => Units.encodeErc20Transfer('0x1234', BigInt.one), throwsArgumentError);
      expect(
          () => Units.encodeErc20Transfer(
              '0x0000000000000000000000000000000000000001', BigInt.from(-1)),
          throwsArgumentError);
      expect(
          () => Units.encodeErc20Transfer(
              '0x0000000000000000000000000000000000000001', BigInt.two.pow(256)),
          throwsArgumentError);
    });
  });

  group('gas margin', () {
    test('โอนธรรมดา 21000 พอดี ไม่ต้องเผื่อ', () {
      expect(Units.addGasMargin(21000), 21000);
    });

    test('เรียกสัญญา → เผื่อ 20%', () {
      expect(Units.addGasMargin(50000), 60000);
      expect(Units.addGasMargin(44270), 44270 + 8854);
    });
  });

  group('ธุรกรรม legacy + EIP-155 บน TPIX Chain', () {
    test('เซ็นแบบ legacy (ไม่ใช่ 0x02) และ v ฝัง chainId 4289', () {
      final key = EthPrivateKey.fromHex(
          '4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318');
      final tx = Transaction(
        to: EthereumAddress.fromHex('0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1'),
        value: EtherAmount.zero(),
        data: Units.encodeErc20Transfer(
            '0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7', BigInt.from(1000000)),
        gasPrice: EtherAmount.zero(),
        maxGas: 60000,
        nonce: 0,
      );
      final raw = signTransactionRaw(tx, key, chainId: 4289);
      // legacy RLP เริ่มด้วย list prefix (>= 0xc0) ไม่ใช่ type byte 0x02
      expect(raw.first, greaterThanOrEqualTo(0xc0));
      // v = chainId * 2 + 35 หรือ +36 = 8613/8614 = 0x21a5/0x21a6 ฝังอยู่ใน RLP
      final hex = bytesToHex(raw);
      expect(hex.contains('8221a5') || hex.contains('8221a6'), isTrue,
          reason: 'v ต้องเป็นแบบ EIP-155 ของเชน 4289');
      expect(Uint8List.fromList(raw), isNotEmpty);
    });
  });
}
