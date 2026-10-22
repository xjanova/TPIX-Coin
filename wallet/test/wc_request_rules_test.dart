/// TPIX Wallet — กติกาของคำขอ WalletConnect
///
/// สิ่งที่ห้ามพัง:
///   - personal_sign: [ข้อความ, ที่อยู่] และแบบสลับ · ข้อความ 0x-hex = ไบต์ดิบ (ไบต์ที่ไม่ใช่ UTF-8 ห้ามเพี้ยน)
///   - ลายเซ็น EIP-191 ที่เซิร์ฟเวอร์ ecrecover ได้ และ v = 27/28 เสมอ
///   - เว็บขอให้กระเป๋าอื่นเซ็น → ไม่เซ็น ตอบ 4100 wallet_changed (ไม่เผยที่อยู่ของใบที่เปิดอยู่)
///   - สลับ/เพิ่มเชน: ตอบเองไม่ขึ้นการ์ด · เชนที่ไม่รองรับ = 4902
///   - ที่มาของเว็บ (Verify): INVALID / SCAM / โดเมนไม่ตรง = เตือนแดง · UNKNOWN = โน้ตกลาง ๆ
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reown_walletkit/reown_walletkit.dart' show Validation, VerifyContext;
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/services/wallet_service.dart';
import 'package:tpix_wallet/services/wc_request_rules.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart' show EthPrivateKey;

// กุญแจตัวอย่างในเอกสาร web3.js (web3.eth.accounts.sign) — ห้ามใช้กับเงินจริง
const _pk = '4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318';
const _pkAddress = '0x2c7536e3605d9c16a7a3d7b1898e529396a65c23';
const _other = '0x8aF94D36Ea0C14C40CDaff5bddE017269A9ccc04';

/// ข้อความล็อกอินของ TPIX TRADE ตามที่เว็บส่ง (ethers v6: [0x<UTF-8 hex>, <ที่อยู่ตัวเล็ก>])
const _loginMessage = 'TPIX TRADE: Sign this message to verify your wallet.\n\n'
    'Nonce: 9f1c2e7a5b\nTimestamp: 2026-10-22T10:00:00.000Z';

String _hexOf(List<int> bytes) => bytesToHex(bytes, include0x: true);

/// ecrecover แบบเดียวกับเซิร์ฟเวอร์: keccak256("\x19Ethereum Signed Message:\n" + len + ไบต์)
String _recover(Uint8List message, String signatureHex) {
  final sig = hexToBytes(signatureHex);
  expect(sig.length, 65);
  final prefix = ascii.encode('\u0019Ethereum Signed Message:\n${message.length}');
  final hash = keccak256(Uint8List.fromList([...prefix, ...message]));
  final pub = ecRecover(
    hash,
    MsgSignature(bytesToUnsignedInt(sig.sublist(0, 32)), bytesToUnsignedInt(sig.sublist(32, 64)), sig[64]),
  );
  return _hexOf(publicKeyToAddress(pub));
}

void main() {
  group('WcSignParams.parse — personal_sign / eth_sign', () {
    final loginHex = _hexOf(utf8.encode(_loginMessage));

    test('★ ethers v6: [0x-hex ของ UTF-8, ที่อยู่ตัวเล็ก] → ไบต์ตรงกับข้อความเดิม', () {
      final p = WcSignParams.parse('personal_sign', [loginHex, _pkAddress])!;
      expect(p.message, utf8.encode(_loginMessage));
      expect(p.address, _pkAddress);
      expect(p.displayText, _loginMessage, reason: 'โชว์ข้อความให้คนอ่าน มีขึ้นบรรทัดครบ');
    });

    test('★ สลับลำดับมา [ที่อยู่, ข้อความ] → ยังอ่านถูก', () {
      final p = WcSignParams.parse('personal_sign', [_pkAddress, loginHex])!;
      expect(p.message, utf8.encode(_loginMessage));
      expect(p.address, _pkAddress);
    });

    test('eth_sign ลำดับมาตรฐาน [ที่อยู่, ข้อความ]', () {
      final p = WcSignParams.parse('eth_sign', [_pkAddress, '0xdeadbeef'])!;
      expect(p.message, [0xde, 0xad, 0xbe, 0xef]);
      expect(p.address, _pkAddress);
    });

    test('ข้อความหน้าตาเป็นที่อยู่ทั้งคู่ → ยึดลำดับมาตรฐานของเมธอด', () {
      final personal = WcSignParams.parse('personal_sign', [_other, _pkAddress])!;
      expect(personal.address, _pkAddress);
      expect(personal.message, hexToBytes(_other));
      final ethSign = WcSignParams.parse('eth_sign', [_pkAddress, _other])!;
      expect(ethSign.address, _pkAddress);
      expect(ethSign.message, hexToBytes(_other));
    });

    test('ข้อความธรรมดา (ไม่ใช่ hex) → ไบต์ UTF-8 ตามตัวอักษร (รวมภาษาไทย)', () {
      final p = WcSignParams.parse('personal_sign', ['สวัสดี TPIX', _pkAddress])!;
      expect(p.message, utf8.encode('สวัสดี TPIX'));
      expect(p.displayText, 'สวัสดี TPIX');
    });

    test('★ ไบต์ที่ไม่ใช่ UTF-8 → ส่งต่อไปเซ็นตามจริง ไม่ถูกแทนด้วย U+FFFD', () {
      final raw = [0xff, 0xfe, 0x00, 0x80, 0xc3, 0x28];
      final p = WcSignParams.parse('personal_sign', [_hexOf(raw), _pkAddress])!;
      expect(p.message, raw);
      expect(p.displayText, _hexOf(raw), reason: 'ถอดไม่ได้ → โชว์ hex ไม่เดาตัวอักษร');
    });

    test('hex ความยาวคี่ / 0X ตัวใหญ่ → ถือเป็นข้อความตามตัวอักษร · "0x" เปล่า = ไบต์ว่าง', () {
      expect(WcSignParams.parse('personal_sign', ['0xabc', _pkAddress])!.message, utf8.encode('0xabc'));
      expect(WcSignParams.parse('personal_sign', ['0XAB', _pkAddress])!.message, utf8.encode('0XAB'));
      expect(WcSignParams.parse('personal_sign', ['0x', _pkAddress])!.message, isEmpty);
    });

    test('ตัวควบคุมแปลก ๆ ในข้อความ → โชว์ hex (กันซ่อนข้อความหลอกตา)', () {
      final p = WcSignParams.parse('personal_sign', [_hexOf([0x41, 0x07, 0x42]), _pkAddress])!;
      expect(p.displayText, '0x410742');
    });

    test('มีพารามิเตอร์เดียว → ข้อความล้วน ไม่ระบุที่อยู่', () {
      final p = WcSignParams.parse('personal_sign', ['0x68656c6c6f'])!;
      expect(p.message, utf8.encode('hello'));
      expect(p.address, isNull);
    });

    test('รูปแบบเสีย → null (ตอบ invalid params)', () {
      expect(WcSignParams.parse('personal_sign', null), isNull);
      expect(WcSignParams.parse('personal_sign', 'hello'), isNull);
      expect(WcSignParams.parse('personal_sign', []), isNull);
      expect(WcSignParams.parse('personal_sign', [123, _pkAddress]), isNull);
      expect(WcSignParams.parse('personal_sign', ['hello', 42]), isNull);
      expect(WcSignParams.parse('personal_sign', ['hello', 'world']), isNull, reason: 'ไม่มีตัวไหนเป็นที่อยู่');
      expect(WcSignParams.parse('personal_sign', ['hello', '0x1234']), isNull);
    });
  });

  group('signPersonalBytesWith — EIP-191', () {
    final key = EthPrivateKey.fromHex(_pk);

    test('ตรงกับเวกเตอร์ของ web3.js (deterministic RFC6979) และ v = 28', () {
      final sig = WalletService.signPersonalBytesWith(key, Uint8List.fromList(utf8.encode('Some data')));
      expect(
        sig,
        '0xb91467e570a6466aa9e9876cbcd013baba02900b8979d43fe208a4a4f339f5fd'
        '6007e74cd82e037b800186422fc2da167c747ef045e5d18a5f5d4300f8e1a0291c',
      );
    });

    test('★ ข้อความล็อกอินแบบ hex → เซ็นไบต์เดียวกับข้อความเดิม · ecrecover ได้ที่อยู่ผู้เซ็น · v 27/28', () {
      final parsed = WcSignParams.parse('personal_sign', [_hexOf(utf8.encode(_loginMessage)), _pkAddress])!;
      final viaHex = WalletService.signPersonalBytesWith(key, parsed.message);
      final viaText = WalletService.signPersonalBytesWith(key, Uint8List.fromList(utf8.encode(_loginMessage)));
      expect(viaHex, viaText);
      expect(_recover(parsed.message, viaHex), _pkAddress);
      expect(hexToBytes(viaHex).last, anyOf(27, 28));
    });

    test('★ ไบต์ที่ไม่ใช่ UTF-8 → เซ็นไบต์ดิบ ecrecover ผ่าน (ของเดิมถอด UTF-8 แล้วเข้ารหัสกลับ = ลายเซ็นผิด)', () {
      final raw = Uint8List.fromList([0xff, 0xfe, 0x00, 0x80, 0xc3, 0x28, 0x01]);
      final parsed = WcSignParams.parse('personal_sign', [_hexOf(raw), _pkAddress])!;
      final sig = WalletService.signPersonalBytesWith(key, parsed.message);
      expect(_recover(raw, sig), _pkAddress);
      final corrupted = Uint8List.fromList(utf8.encode(utf8.decode(raw, allowMalformed: true)));
      expect(_recover(corrupted, sig), isNot(_pkAddress));
    });
  });

  group('requestedAddress / walletChangedExpected', () {
    test('personal_sign · eth_sendTransaction (tx.from) · typed data', () {
      expect(WcRequestRules.requestedAddress('personal_sign', ['0x00', _other]).address, _other);
      expect(WcRequestRules.requestedAddress('eth_sendTransaction', [
        {'from': _other, 'to': _pkAddress},
      ]).address, _other);
      expect(WcRequestRules.requestedAddress('eth_sendTransaction', [
        {'to': _pkAddress},
      ]).address, isNull);
      expect(WcRequestRules.requestedAddress('eth_signTypedData_v4', [_other, '{}']).address, _other);
    });

    test('ผิดรูป → invalid', () {
      expect(WcRequestRules.requestedAddress('personal_sign', ['a', 'b']).invalid, isTrue);
      expect(WcRequestRules.requestedAddress('eth_sendTransaction', []).invalid, isTrue);
      expect(WcRequestRules.requestedAddress('eth_sendTransaction', [
        {'from': '0x1234'},
      ]).invalid, isTrue);
      expect(WcRequestRules.requestedAddress('eth_sendTransaction', 'x').invalid, isTrue);
    });

    test('เทียบแบบไม่สนตัวพิมพ์ · ไม่ระบุ = ผ่าน · ไม่มีกระเป๋าเปิดอยู่ = ไม่ผ่าน', () {
      expect(WcRequestRules.walletChangedExpected(requested: _pkAddress, active: _pkAddress.toUpperCase().replaceFirst('0X', '0x')), isNull);
      expect(WcRequestRules.walletChangedExpected(requested: _other, active: _pkAddress), _other);
      expect(WcRequestRules.walletChangedExpected(requested: null, active: _pkAddress), isNull);
      expect(WcRequestRules.walletChangedExpected(requested: _other, active: null), _other);
    });
  });

  group('decideIntake — ตอบเองหรือถามผู้ใช้', () {
    final chains = ChainConfig.all.map((c) => c.chainId).toSet();
    WcIntake decide(String method, dynamic params, {String? active = _pkAddress}) =>
        WcRequestRules.decideIntake(method: method, params: params, supportedChainIds: chains, activeAddress: active);

    test('personal_sign ของกระเป๋าที่เปิดอยู่ → ถามผู้ใช้', () {
      expect(decide('personal_sign', ['0x68656c6c6f', _pkAddress]), isA<WcAskUser>());
      expect(decide('eth_sendTransaction', [
        {'from': _pkAddress, 'to': _other, 'value': '0x0'},
      ]), isA<WcAskUser>());
    });

    test('★ เว็บขอกระเป๋าอื่น → 4100 wallet_changed (ไม่เผยที่อยู่ของใบที่เปิดอยู่) + บอกว่าเว็บรอใบไหน', () {
      final r = decide('personal_sign', ['0x68656c6c6f', _other]) as WcAutoReject;
      expect(r.code, 4100);
      expect(r.message, contains('wallet_changed'));
      expect(r.message.toLowerCase(), isNot(contains(_pkAddress)));
      expect(r.walletExpected, _other);

      final tx = decide('eth_sendTransaction', [
        {'from': _other, 'to': _pkAddress},
      ]) as WcAutoReject;
      expect(tx.code, 4100);
      expect(tx.walletExpected, _other);
    });

    test('★ สลับไปเชนที่รองรับ → สำเร็จ (result null) + chainChanged · เพิ่มเชนที่มีแล้ว → สำเร็จเฉย ๆ', () {
      final sw = decide('wallet_switchEthereumChain', [
        {'chainId': '0x10c1'},
      ]) as WcAutoOk;
      expect(sw.chainChanged, 4289);
      final add = decide('wallet_addEthereumChain', [
        {'chainId': '0x38', 'chainName': 'BNB Smart Chain', 'rpcUrls': ['https://bsc.example']},
      ]) as WcAutoOk;
      expect(add.chainChanged, isNull);
    });

    test('★ เชนที่ไม่รองรับ → 4902 Unrecognized chain ID', () {
      for (final method in ['wallet_switchEthereumChain', 'wallet_addEthereumChain']) {
        final r = decide(method, [
          {'chainId': '0xa4b1'},
        ]) as WcAutoReject;
        expect(r.code, 4902, reason: method);
        expect(r.message, contains('Unrecognized chain ID'));
        expect(r.walletExpected, isNull);
      }
    });

    test('params เสีย → -32602 · เมธอดที่ไม่รองรับ → 4200 (ไม่ขึ้นการ์ดให้กดเปล่า ๆ)', () {
      expect((decide('wallet_switchEthereumChain', []) as WcAutoReject).code, -32602);
      expect((decide('wallet_switchEthereumChain', [
        {'chainId': 'abc'},
      ]) as WcAutoReject).code, -32602);
      expect((decide('personal_sign', ['hello', 'world']) as WcAutoReject).code, -32602);
      expect((decide('eth_signTransaction', [{}]) as WcAutoReject).code, 4200);
    });

    test('parseChainId: 0x-hex / ฐานสิบ / int · ขยะ = null', () {
      expect(WcRequestRules.parseChainId('0x10c1'), 4289);
      expect(WcRequestRules.parseChainId('0X38'), 56);
      expect(WcRequestRules.parseChainId('137'), 137);
      expect(WcRequestRules.parseChainId(1), 1);
      for (final bad in ['0x', 'abc', -1, 0, null, 1.5]) {
        expect(WcRequestRules.parseChainId(bad), isNull, reason: '$bad');
      }
    });
  });

  group('WcOrigin.check — ที่มาของเว็บ', () {
    VerifyContext ctx(Validation v, {String origin = 'https://tpix.online', bool? isScam}) =>
        VerifyContext(origin: origin, validation: v, verifyUrl: 'https://verify.walletconnect.org', isScam: isScam);

    test('VALID + โดเมนตรง → verified พร้อมโดเมน', () {
      final o = WcOrigin.check(ctx(Validation.VALID), 'https://tpix.online');
      expect(o.level, WcOriginLevel.verified);
      expect(o.host, 'tpix.online');
      expect(o.isDanger, isFalse);
    });

    test('UNKNOWN / ไม่มี verify context → unknown (โน้ตกลาง ๆ)', () {
      expect(WcOrigin.check(ctx(Validation.UNKNOWN), 'https://tpix.online').level, WcOriginLevel.unknown);
      final none = WcOrigin.check(null, 'https://tpix.online/trade');
      expect(none.level, WcOriginLevel.unknown);
      expect(none.displayHost, 'tpix.online');
    });

    test('INVALID → invalid · SCAM หรือ isScam → scam (เตือนแดง)', () {
      expect(WcOrigin.check(ctx(Validation.INVALID), 'https://tpix.online').level, WcOriginLevel.invalid);
      expect(WcOrigin.check(ctx(Validation.SCAM), 'https://tpix.online').level, WcOriginLevel.scam);
      final flagged = WcOrigin.check(ctx(Validation.VALID, isScam: true), 'https://tpix.online');
      expect(flagged.level, WcOriginLevel.scam);
      expect(flagged.isDanger, isTrue);
    });

    test('★ ที่มาจริงไม่ตรงกับโดเมนที่อ้าง → mismatch แม้ Verify ไม่ได้ฟันธง', () {
      final o = WcOrigin.check(ctx(Validation.UNKNOWN, origin: 'https://tpix-online.xyz'), 'https://tpix.online');
      expect(o.level, WcOriginLevel.mismatch);
      expect(o.host, 'tpix-online.xyz');
      expect(o.claimedHost, 'tpix.online');
      expect(o.isDanger, isTrue);
      expect(
        WcOrigin.check(ctx(Validation.VALID, origin: 'https://www.tpix.online'), 'https://tpix.online').level,
        WcOriginLevel.mismatch,
      );
    });

    test('เว็บไม่บอกที่อยู่ตัวเอง → invalid · origin ไม่มี scheme / ตัวพิมพ์ใหญ่ก็อ่านได้', () {
      expect(WcOrigin.check(ctx(Validation.UNKNOWN, origin: ''), '').level, WcOriginLevel.invalid);
      expect(WcOrigin.check(ctx(Validation.VALID, origin: 'TPIX.online'), 'https://tpix.online').level,
          WcOriginLevel.verified);
    });
  });

  group('อื่น ๆ', () {
    test('wcShortAddress → 0x1234…abcd', () {
      expect(wcShortAddress('0x8aF94D36Ea0C14C40CDaff5bddE017269A9ccc04'), '0x8aF9…cc04');
      expect(wcShortAddress('0x1234'), '0x1234');
    });

    test('WcRequestView: personal_sign โชว์ข้อความ · sendTransaction โชว์ปลายทาง + จำนวนตามเหรียญของเชน', () {
      final sign = WcRequestView.build(
        method: 'personal_sign',
        params: [_hexOf(utf8.encode(_loginMessage)), _pkAddress],
        chainId: 'eip155:4289',
      );
      expect(sign.kind, WcRequestKind.signMessage);
      expect(sign.body, _loginMessage);

      final tx = WcRequestView.build(
        method: 'eth_sendTransaction',
        params: [
          {'from': _pkAddress, 'to': _other, 'value': '0xde0b6b3a7640000'},
        ],
        chainId: 'eip155:56',
      );
      expect(tx.kind, WcRequestKind.sendTransaction);
      expect(tx.to, _other);
      expect(tx.value, '1 ${ChainConfig.bsc.symbol}');
      expect(tx.chainName, ChainConfig.bsc.name);
    });
  });
}
