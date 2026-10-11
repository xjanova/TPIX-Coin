/// TPIX Wallet — เทสต์ "ยืนยันแล้ว / ไม่ยืนยัน / เลียนแบบ" + ลำดับการเลือกโลโก้
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/models/token_info.dart';
import 'package:tpix_wallet/models/token_list.dart';
import 'package:tpix_wallet/services/token_trust.dart';

const _idtc = '0x5fbdb2315678afecb367f032d93f642f64180aa3';
const _idtcLogo = 'https://tpix.online/storage/tokens/idtc.png';
const _fake = '0x9999999999999999999999999999999999999999';
final _usdt = ChainConfig.tpixUsdtAddress.toLowerCase();
final _usdtBuiltInLogo = ChainConfig.tpix.knownTokens.single.logoUrl!;

/// รายการที่ยืนยันแล้ว: IDTC (โทเค็นลูกจาก Token Factory) + USDT (โลโก้ของ tpix.online)
final _list = TokenList(name: 'TPIX Token List', tokens: const [
  TokenListEntry(
    chainId: 4289,
    address: _idtc,
    name: 'IDTC Token',
    symbol: 'IDTC',
    decimals: 18,
    logoUri: _idtcLogo,
  ),
  TokenListEntry(
    chainId: 4289,
    address: '0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1',
    name: 'Tether USD',
    symbol: 'USDT',
    decimals: 6,
    logoUri: 'https://tpix.online/images/tokens/usdt.png',
  ),
]);

TokenTrustResult _classify(
  String address,
  String name,
  String symbol, {
  int decimals = 18,
  TokenList? list,
}) =>
    TokenTrustService.classify(
      address: address,
      name: name,
      symbol: symbol,
      decimals: decimals,
      list: list,
    );

TokenInfo _token(String address, {String? logo, int chainId = 4289, String symbol = 'X'}) =>
    TokenInfo(
      contractAddress: address,
      name: symbol,
      symbol: symbol,
      walletSlot: 1,
      chainId: chainId,
      logoUrl: logo,
    );

/// สร้างสตริงจากรหัสอักขระ (ไม่ใส่อักษรหน้าตาเหมือนกันลงในซอร์สตรงๆ)
String _cp(List<int> codes) => String.fromCharCodes(codes);

void main() {
  group('verifiedTokens', () {
    test('รายการจากเซิร์ฟเวอร์ ∪ ค่าในตัวแอป — ที่อยู่ซ้ำใช้ข้อมูลจากรายการ', () {
      final all = TokenTrustService.verifiedTokens(_list);
      expect(all.map((t) => t.symbol), ['USDT', 'IDTC']);
      final usdt = all.firstWhere((t) => t.symbol == 'USDT');
      expect(usdt.logoUrl, 'https://tpix.online/images/tokens/usdt.png');
    });

    test('ไม่มีรายการ (404/ออฟไลน์) → เหลือค่าในตัวแอป (USDT)', () {
      final all = TokenTrustService.verifiedTokens(null);
      expect(all.map((t) => t.address.toLowerCase()), [_usdt]);
    });
  });

  group('classify — ยืนยันแล้ว', () {
    test('อยู่ในรายการ + ข้อมูลตรง → verified ไม่มีคำเตือน', () {
      final r = _classify(_idtc.toUpperCase().replaceFirst('0X', '0x'), 'IDTC Token', 'IDTC', list: _list);
      expect(r.trust, TokenTrust.verified);
      expect(r.listed!.logoUrl, _idtcLogo);
      expect(r.mismatches, isEmpty);
      expect(r.listAvailable, isTrue);
    });

    test('ต่างแค่ตัวพิมพ์/ช่องว่างหัวท้าย → ไม่นับว่าไม่ตรง', () {
      final r = _classify(_idtc, ' idtc token ', 'idtc', list: _list);
      expect(r.mismatches, isEmpty);
    });

    test('บนสัญญาไม่ตรงกับรายการ → ยัง verified (ที่อยู่ถูก) แต่บอกช่องที่ไม่ตรง', () {
      final r = _classify(_idtc, 'IDTC Coin', 'IDT', decimals: 8, list: _list);
      expect(r.trust, TokenTrust.verified);
      expect(r.mismatches,
          {TokenMetaField.name, TokenMetaField.symbol, TokenMetaField.decimals});
    });

    test('ไม่มีรายการจากเซิร์ฟเวอร์ → USDT ในตัวแอปยังยืนยันได้', () {
      final r = _classify(_usdt, 'Tether USD', 'USDT', decimals: 6);
      expect(r.trust, TokenTrust.verified);
      expect(r.listAvailable, isFalse);
      expect(r.listed!.logoUrl, _usdtBuiltInLogo);
    });
  });

  group('classify — ไม่ยืนยัน', () {
    test('ชื่อไม่ซ้ำใคร → unverified (ยังเพิ่มได้ แต่เตือน)', () {
      final r = _classify(_fake, 'My Cool Token', 'MCT', list: _list);
      expect(r.trust, TokenTrust.unverified);
      expect(r.lookalikes, isEmpty);
      expect(r.listAvailable, isTrue);
    });

    test('ไม่มีรายการ → unverified + บอกว่าตรวจกับรายการไม่ได้', () {
      final r = _classify(_idtc, 'IDTC Token', 'IDTC');
      expect(r.trust, TokenTrust.unverified, reason: 'IDTC ไม่อยู่ในค่าในตัวแอป');
      expect(r.listAvailable, isFalse);
    });

    test('คล้ายแต่ไม่เหมือน (USDT2, USDT.e, Tether Gold) → ไม่ใช่ของเลียนแบบ', () {
      for (final s in ['USDT2', 'USDT.e', 'XUSDT']) {
        expect(_classify(_fake, 'Something', s, list: _list).trust, TokenTrust.unverified,
            reason: s);
      }
      expect(_classify(_fake, 'Tether Gold', 'XAUT', list: _list).trust, TokenTrust.unverified);
    });
  });

  group('classify — ชื่อเลียนแบบตัวที่ยืนยันแล้ว (กันโทเค็นปลอม)', () {
    void expectLookalike(String name, String symbol, String realSymbol, {TokenList? list}) {
      final r = _classify(_fake, name, symbol, list: list ?? _list);
      expect(r.trust, TokenTrust.lookalike, reason: '$name / $symbol');
      expect(r.lookalikes.map((t) => t.symbol), contains(realSymbol));
    }

    test('USDT ปลอม (สัญลักษณ์ตรง ต่างที่อยู่)', () {
      expectLookalike('Tether', 'USDT', 'USDT');
      expectLookalike('Whatever', 'usdt', 'USDT');
    });

    test('ชื่อตรงแต่สัญลักษณ์ต่าง', () {
      expectLookalike('Tether USD', 'TUSD', 'USDT');
    });

    test('รายการล่ม → ยังจับ USDT ปลอมได้จากค่าในตัวแอป', () {
      final r = _classify(_fake, 'Tether USD', 'USDT');
      expect(r.trust, TokenTrust.lookalike);
      expect(r.listAvailable, isFalse);
    });

    test('โทเค็นลูกจาก Token Factory (IDTC) ก็ถูกปกป้อง', () {
      expectLookalike('IDTC', 'IDTC', 'IDTC');
    });

    test('ERC-20 ชื่อ "TPIX" = ปลอมเหรียญหลักของเชน', () {
      final r = _classify(_fake, 'TPIX', 'TPIX', list: _list);
      expect(r.trust, TokenTrust.lookalike);
      expect(r.lookalikes.single.isNative, isTrue);
      expectLookalike('TP1X Coin', 'TP1X', 'TPIX');
    });

    test('ซ่อนด้วยช่องว่าง / ขีด / อักขระมองไม่เห็น', () {
      expectLookalike('x', 'U S D T', 'USDT');
      expectLookalike('x', 'USD-T', 'USDT');
      expectLookalike('x', 'US${_cp([0x200B])}DT', 'USDT');
    });

    test('อักษรหน้าตาเหมือน: ซีริลลิก / กรีก / เต็มความกว้าง / ดอลลาร์ / ₮', () {
      // "USDТ" — T เป็นซีริลลิก (U+0422)
      expectLookalike('x', 'USD${_cp([0x0422])}', 'USDT');
      // "UЅDT" — S เป็นซีริลลิก (U+0405)
      expectLookalike('x', 'U${_cp([0x0405])}DT', 'USDT');
      // "ΤPIX" — T เป็นกรีก (U+03A4)
      expectLookalike('x', '${_cp([0x03A4])}PIX', 'TPIX');
      // "ＵＳＤＴ" — อักษรเต็มความกว้าง
      expectLookalike('x', _cp([0xFF35, 0xFF33, 0xFF24, 0xFF34]), 'USDT');
      expectLookalike('x', r'U$DT', 'USDT');
      expectLookalike('x', 'USD${_cp([0x20AE])}', 'USDT');
    });

    test('skeleton: รูปแบบต่างๆ ของ USDT ได้ค่าเดียวกัน', () {
      final base = TokenTrustService.skeleton('USDT');
      for (final v in [
        'usdt',
        ' U.S.D.T ',
        'USD${_cp([0x0422])}',
        _cp([0xFF35, 0xFF33, 0xFF24, 0xFF34]),
      ]) {
        expect(TokenTrustService.skeleton(v), base, reason: v);
      }
      expect(TokenTrustService.skeleton('USDC'), isNot(base));
    });
  });

  group('trustOf — ป้ายในรายการโทเค็น', () {
    test('ตามประเภท และโทเค็นเชนอื่นไม่ติดป้าย', () {
      expect(TokenTrustService.trustOf(_token(_idtc, symbol: 'IDTC'), _list).name, 'verified');
      expect(TokenTrustService.trustOf(_token(_fake, symbol: 'USDT'), _list), TokenTrust.lookalike);
      expect(TokenTrustService.trustOf(_token(_fake, symbol: 'ZZZ'), _list), TokenTrust.unverified);
      expect(
        TokenTrustService.trustOf(_token(_fake, symbol: 'USDT', chainId: 56), _list),
        TokenTrust.unverified,
      );
    });
  });

  group('resolveLogo — ลำดับ: รายการ (ถ้าอยู่ในรายการ) → ที่บันทึกไว้ → DEX → ในตัวแอป', () {
    const stored = 'https://example.com/stored.png';
    const dex = 'https://tpix.online/dex/logo.png';

    test('1. อยู่ในรายการ → โลโก้จากรายการชนะโลโก้ที่บันทึกไว้ (แอดมินเปลี่ยนโลโก้ได้)', () {
      expect(
        TokenTrustService.resolveLogo(_token(_idtc, logo: stored),
            list: _list, dexLogos: {_idtc: dex}),
        _idtcLogo,
      );
      // USDT: บันทึกโลโก้ Trust Wallet ไว้ตอนเพิ่มอัตโนมัติ → รายการชนะ
      expect(
        TokenTrustService.resolveLogo(_token(_usdt, logo: _usdtBuiltInLogo), list: _list),
        'https://tpix.online/images/tokens/usdt.png',
      );
    });

    test('ที่อยู่ไม่สนตัวพิมพ์', () {
      expect(
        TokenTrustService.resolveLogo(_token(_idtc.toUpperCase().replaceFirst('0X', '0x')),
            list: _list, dexLogos: {_idtc: dex}),
        _idtcLogo,
      );
    });

    test('2. ไม่อยู่ในรายการ → โลโก้ที่บันทึกไว้ชนะ DEX/ค่าในตัวแอป', () {
      expect(
        TokenTrustService.resolveLogo(_token(_fake, logo: stored),
            list: _list, dexLogos: {_fake: dex}),
        stored,
      );
      // รายการล่ม → โทเค็นที่เคยอยู่ในรายการก็ใช้โลโก้ที่บันทึกไว้
      expect(
        TokenTrustService.resolveLogo(_token(_idtc, logo: stored), list: null, dexLogos: {_idtc: dex}),
        stored,
      );
    });

    test('อยู่ในรายการแต่รายการไม่มีโลโก้ → ใช้โลโก้ที่บันทึกไว้', () {
      final noLogo = TokenList(name: 'x', tokens: const [
        TokenListEntry(chainId: 4289, address: _idtc, name: 'IDTC Token', symbol: 'IDTC', decimals: 18),
      ]);
      expect(TokenTrustService.resolveLogo(_token(_idtc, logo: stored), list: noLogo), stored);
    });

    test('3. ไม่อยู่ในรายการ + ไม่มีที่บันทึก → โลโก้จากคู่เทรด DEX', () {
      expect(
        TokenTrustService.resolveLogo(_token(_idtc), list: null, dexLogos: {_idtc: dex}),
        dex,
      );
    });

    test('4. ไม่มีทั้งหมด → ค่าในตัวแอป (USDT_TPIX)', () {
      expect(TokenTrustService.resolveLogo(_token(_usdt)), _usdtBuiltInLogo);
    });

    test('ข้ามลิงก์ที่ไม่ใช่ https (ข้อมูลเก่าในฐานข้อมูล)', () {
      expect(
        TokenTrustService.resolveLogo(_token(_usdt, logo: 'http://insecure/logo.png')),
        _usdtBuiltInLogo,
      );
    });

    test('ไม่มีที่ไหนรู้จัก → null (วาดตัวอักษรแรกแทน)', () {
      expect(TokenTrustService.resolveLogo(_token(_fake), list: _list), isNull);
    });

    test('โทเค็นเชนอื่นไม่ใช้รายการของ TPIX — ใช้ค่าในตัวแอป/Trust Wallet ของเชนนั้น', () {
      // ที่อยู่เดียวกับ IDTC แต่อยู่บน BSC → ต้องไม่ได้โลโก้ IDTC
      final onBsc = TokenTrustService.resolveLogo(_token(_idtc, chainId: 56),
          list: _list, dexLogos: {_idtc: dex});
      expect(onBsc, isNot(_idtcLogo));
      expect(onBsc, isNot(dex));
      expect(onBsc, contains('/blockchains/smartchain/assets/0x5FbDB2315678afecb367f032d93F642f64180aa3/'),
          reason: 'Trust Wallet ใช้ที่อยู่แบบ checksum');

      final bscUsdt = ChainConfig.bsc.knownTokens.first;
      expect(
        TokenTrustService.resolveLogo(_token(bscUsdt.address.toLowerCase(), chainId: 56)),
        bscUsdt.logoUrl,
      );
    });
  });
}
