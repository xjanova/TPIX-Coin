/// TPIX Wallet — เทสต์ตัวตรวจที่อยู่ (EIP-55)
///
/// บั๊กเดิม: ตัวตรวจ checksum ใช้ sha256 แทน keccak256 → ที่อยู่ที่ checksum
/// ถูกต้องที่ก๊อปมาจาก MetaMask / explorer โดนหน้าโอนตีกลับว่า "ที่อยู่ไม่ถูกต้อง"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/services/wallet_service.dart';
import 'package:web3dart/web3dart.dart';

/// สัญญาบน TPIX Chain หลัง re-genesis — เขียนแบบ checksum ตามที่ explorer แสดง
const _tpixContracts = {
  'WTPIX': '0x0A3dB168aF6b85e61D81CA78C608BDadAC832DFF',
  'USDT_TPIX': '0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1',
  'Factory': '0x94b1254acE355559611890D4EB2d07332eD1fB8A',
  'Router': '0x8aF94D36Ea0C14C40CDaff5bddE017269A9ccc04',
};

/// สลับตัวพิมพ์ของ "ตัวอักษร" ตัวแรกหลัง 0x (ข้ามตัวเลข) → checksum ต้องพัง
String _flipFirstLetter(String address) {
  final chars = address.split('');
  for (var i = 2; i < chars.length; i++) {
    final ch = chars[i];
    if (ch.toUpperCase() == ch.toLowerCase()) continue;
    chars[i] = ch == ch.toUpperCase() ? ch.toLowerCase() : ch.toUpperCase();
    return chars.join();
  }
  throw StateError('ไม่มีตัวอักษรให้สลับ');
}

void main() {
  group('WalletService.isValidAddress', () {
    for (final entry in _tpixContracts.entries) {
      test('${entry.key} (checksum ถูก) ต้องผ่าน', () {
        expect(WalletService.isValidAddress(entry.value), isTrue);
        // ตัวเทียบอิสระ: web3dart ตรวจ EIP-55 ด้วย keccak เหมือนกัน
        expect(
          () => EthereumAddress.fromHex(entry.value, enforceEip55: true),
          returnsNormally,
        );
      });
    }

    test('ตัวอย่างมาตรฐานจากสเปก EIP-55 ต้องผ่าน', () {
      expect(
          WalletService.isValidAddress(
              '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'),
          isTrue);
      expect(
          WalletService.isValidAddress(
              '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359'),
          isTrue);
    });

    test('ตัวเล็กล้วน (ไม่มี checksum) ต้องผ่าน', () {
      for (final a in _tpixContracts.values) {
        expect(WalletService.isValidAddress(a.toLowerCase()), isTrue);
      }
    });

    test('ตัวใหญ่ล้วน (ไม่มี checksum) ต้องผ่าน', () {
      const a = '0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1';
      expect(WalletService.isValidAddress('0x${a.substring(2).toUpperCase()}'),
          isTrue);
    });

    test('ตัวพิมพ์ผสมที่ผิดไปตัวเดียว ต้องตก', () {
      for (final a in _tpixContracts.values) {
        final broken = _flipFirstLetter(a);
        expect(broken.toLowerCase(), a.toLowerCase(),
            reason: 'ต้องเป็นที่อยู่เดียวกัน ต่างแค่ตัวพิมพ์');
        expect(WalletService.isValidAddress(broken), isFalse,
            reason: '$broken สลับตัวพิมพ์แล้ว checksum ต้องไม่ผ่าน');
      }
    });

    test('ความยาวผิด / ไม่มี 0x / ตัวอักษรนอกฐาน 16 ต้องตก', () {
      const ok = '0x0a4ee87551ef041f3eecfbbfdcffc1b46a4878f1';
      expect(WalletService.isValidAddress(ok.substring(0, 41)), isFalse);
      expect(WalletService.isValidAddress('${ok}0'), isFalse);
      expect(WalletService.isValidAddress(ok.substring(2)), isFalse);
      expect(WalletService.isValidAddress(''), isFalse);
      expect(WalletService.isValidAddress('0x'), isFalse);
      expect(
          WalletService.isValidAddress(
              '0xg0a4ee87551ef041f3eecfbbfdcffc1b46a4878f'),
          isFalse);
      expect(WalletService.isValidAddress(' $ok'), isFalse,
          reason: 'ช่องว่างหน้า/หลังต้องให้ผู้เรียก trim ก่อน');
    });
  });
}
