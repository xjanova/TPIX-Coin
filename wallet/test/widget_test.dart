/// TPIX Wallet — Smoke Tests
/// ของเดิมเป็น scaffold test อ้าง MyApp ที่ไม่มีอยู่จริง → compile error
/// ทำให้ flutter test ของ wallet รันไม่ได้เลย — แทนด้วย test ที่มีความหมาย:
/// ตรวจ ChainConfig registry ที่ทุกฟีเจอร์ (send/swap/peer sign-tx) พึ่งพา
/// Developed by Xman Studio
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tpix_wallet/models/chain_config.dart';

void main() {
  group('ChainConfig registry', () {
    test('มีเชนหลักครบ: TPIX + BSC', () {
      final ids = ChainConfig.all.map((c) => c.chainId).toList();
      expect(ids, contains(4289));
      expect(ids, contains(56));
    });

    test('ทุกเชนมี RPC และ explorer', () {
      for (final chain in ChainConfig.all) {
        expect(chain.rpcUrl, startsWith('https://'),
            reason: '${chain.name} rpcUrl');
        expect(chain.explorerUrl, startsWith('https://'),
            reason: '${chain.name} explorerUrl');
      }
    });

    test('chainId ไม่ซ้ำกัน', () {
      final ids = ChainConfig.all.map((c) => c.chainId).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('BSC พร้อมสำหรับ sign-tx จาก TPIX Trade (เทรดจริง)', () {
      final bsc = ChainConfig.byId(56);
      expect(bsc.chainId, 56);
      expect(bsc.symbol, 'BNB');
      expect(bsc.rpcUrl, isNotEmpty);
    });
  });
}
