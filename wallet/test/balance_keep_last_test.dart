/// TPIX Wallet — เทสต์ "ยอดเงินต้องไม่กลายเป็น 0 เพราะเน็ตสะดุด"
///
/// ของเดิม: RPC ล้มเมื่อไหร่ getBalance คืน 0 แล้วทับยอดล่าสุด → ผู้ใช้เห็นเงินหาย
/// ตอนนี้: ล้ม = คงยอดเดิม + ติดป้าย stale · สลับกระเป๋า = ล้างยอดของใบเก่าทิ้ง
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/models/token_info.dart';
import 'package:tpix_wallet/models/tx_record.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/price_service.dart';
import 'package:tpix_wallet/services/rpc_client.dart';
import 'package:tpix_wallet/services/token_service.dart';
import 'package:tpix_wallet/services/wallet_service.dart';
import 'support/isolated_db.dart';

const _walletA = '0xaaaa000000000000000000000000000000001111';
const _walletB = '0xbbbb000000000000000000000000000000002222';
final _oneTpix = BigInt.from(10).pow(18);

/// WalletService ปลอม — คุมผลของ getBalanceWei ได้ทีละครั้ง
class _FakeWalletService extends WalletService {
  String? fakeAddress = _walletA;
  int fakeSlot = 1;
  Future<BigInt> Function() balance = () async => BigInt.zero;

  @override
  String? get address => fakeAddress;

  @override
  int get activeSlot => fakeSlot;

  @override
  Future<BigInt> getBalanceWei() => balance();

  @override
  Future<void> switchWallet(int slot) async {
    fakeSlot = slot;
    fakeAddress = slot == 1 ? _walletA : _walletB;
  }

  @override
  Future<List<TxRecord>> getActiveTxHistory() async => [];
}

/// ตัดทุกการเรียกเน็ตจริงในเทสต์: ราคา / รายการโทเค็น / RPC ทุกเชน = ล่ม
void _offline() {
  PriceService.clientFactory =
      () => MockClient((_) async => http.Response('down', 503));
  TokenService.clientFactory =
      () => MockClient((_) async => http.Response('down', 503));
  for (final chain in ChainConfig.all) {
    RpcClient.overrideForChain(
      chain.chainId,
      RpcClient(chain.rpcUrls,
          httpClient: MockClient((_) async => http.Response('down', 503))),
    );
  }
}

void main() {
  // ฐานข้อมูลแยกของไฟล์นี้ — กันชนกับไฟล์เทสต์อื่นที่รันพร้อมกัน
  setUpAll(() => useIsolatedTestDb('balance_keep_last'));

  late _FakeWalletService service;
  late WalletProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PriceService.reset();
    TokenService.resetCache();
    _offline();
    await DbService.close();
    await databaseFactory.deleteDatabase(
      '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db',
    );
    service = _FakeWalletService();
    provider = WalletProvider(walletService: service);
  });

  tearDown(() {
    provider.dispose();
    PriceService.clientFactory = http.Client.new;
    TokenService.clientFactory = http.Client.new;
    for (final chain in ChainConfig.all) {
      RpcClient.overrideForChain(chain.chainId, null);
    }
  });

  tearDownAll(() async => DbService.close());

  test('ยังไม่เคยดึงยอดได้ → "—" ไม่ใช่ 0', () {
    expect(provider.hasBalance, isFalse);
    expect(provider.formattedBalance, '—');
    expect(provider.portfolioValueUSD, isNull);
  });

  test('ดึงสำเร็จ → มียอด ไม่ stale', () async {
    service.balance = () async => _oneTpix * BigInt.from(5);
    await provider.refreshBalance();
    expect(provider.balanceWei, _oneTpix * BigInt.from(5));
    expect(provider.balance, 5.0);
    expect(provider.isBalanceStale, isFalse);
  });

  test('★ RPC ล้ม → คงยอดเดิม + ติดป้าย stale (ห้ามกลายเป็น 0)', () async {
    service.balance = () async => _oneTpix * BigInt.from(5);
    await provider.refreshBalance();

    service.balance = () async => throw const RpcUnavailableException(2);
    await provider.refreshBalance();
    expect(provider.balanceWei, _oneTpix * BigInt.from(5));
    expect(provider.isBalanceStale, isTrue);

    // เน็ตกลับมา → ป้ายหาย
    service.balance = () async => _oneTpix * BigInt.from(7);
    await provider.refreshBalance();
    expect(provider.balanceWei, _oneTpix * BigInt.from(7));
    expect(provider.isBalanceStale, isFalse);
  });

  test('ล้มตั้งแต่ครั้งแรก → ไม่มียอด + stale (UI บอกว่ายังดึงยอดไม่ได้)', () async {
    service.balance = () async => throw const RpcUnavailableException(2);
    await provider.refreshBalance();
    expect(provider.hasBalance, isFalse);
    expect(provider.isBalanceStale, isTrue);
    expect(provider.formattedBalance, '—');
  });

  test('ราคาดึงไม่ได้ → null (ไม่มี 0.18 ที่แต่งขึ้น)', () async {
    await provider.refreshBalance();
    expect(provider.tpixPrice, isNull);
    expect(provider.portfolioValueUSD, isNull);
  });

  test('สลับกระเป๋าระหว่างรอยอด → ยอดที่ได้ช้าของใบเก่าต้องไม่ไปโผล่ที่ใบใหม่', () async {
    final pending = Completer<BigInt>();
    service.balance = () => pending.future;
    final refresh = provider.refreshBalance();

    // ผู้ใช้สลับไปกระเป๋า B ขณะยอดของ A ยังไม่มา
    service.fakeAddress = _walletB;
    pending.complete(_oneTpix * BigInt.from(99));
    await refresh;

    expect(provider.hasBalance, isFalse,
        reason: 'ยอดของ A ห้ามถูกนับเป็นยอดของ B');
  });

  test('สลับกระเป๋าแล้วดึงยอดใบใหม่ไม่ได้ → ไม่โชว์ยอดของใบเก่าค้างไว้', () async {
    service.balance = () async => _oneTpix * BigInt.from(5);
    await provider.refreshBalance();
    expect(provider.hasBalance, isTrue);

    service.balance = () async => throw const RpcUnavailableException(2);
    await provider.switchWallet(2);

    expect(service.address, _walletB);
    expect(provider.hasBalance, isFalse,
        reason: 'ยอด 5 TPIX เป็นของกระเป๋า A ไม่ใช่ B');
    expect(provider.isBalanceStale, isTrue);

    // งานเบื้องหลังของ loadTokens (เพิ่ม USDT ค่าเริ่มต้น + ตรวจสัญญา) ให้จบก่อนปิด DB
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(provider.tokens.map((t) => t.symbol), contains('USDT'),
        reason: 'กระเป๋าใหม่ได้ USDT บน TPIX Chain อัตโนมัติ (ค่าเริ่มต้นเมื่อ API ล่ม)');
    expect(provider.missingContractTokens, isEmpty,
        reason: 'RPC ล่ม = ไม่รู้ ห้ามติดป้ายว่าสัญญาหาย');
  });

  test('โทเค็นที่สัญญาหาย (getCode = 0x) ถูกซ่อนจากยอด แต่ยังอยู่ให้ผู้ใช้ลบเอง', () async {
    const stale = '0x1111111111111111111111111111111111111111';
    RpcClient.overrideForChain(
      4289,
      RpcClient(
        ChainConfig.tpix.rpcUrls,
        httpClient: MockClient((req) async {
          final body = req.body;
          String result;
          if (body.contains('eth_getCode')) {
            result = body.contains(stale) ? '0x' : '0x6080';
          } else {
            result = '0x${BigInt.from(2500000).toRadixString(16).padLeft(64, '0')}';
          }
          return http.Response('{"jsonrpc":"2.0","id":1,"result":"$result"}', 200);
        }),
      ),
    );
    // โทเค็นที่ผู้ใช้เพิ่มไว้ก่อน re-genesis
    await DbService.addToken(TokenInfo(
      contractAddress: stale,
      name: 'Old Token',
      symbol: 'OLD',
      walletSlot: 1,
    ));

    await provider.loadTokens();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(provider.missingContractTokens.map((t) => t.contractAddress), [stale]);
    expect(provider.activeTokens.map((t) => t.contractAddress), isNot(contains(stale)));
    expect(provider.tokenBalances.keys, isNot(contains(stale)),
        reason: 'สัญญาหาย = ไม่นับยอด');
    // ยังอยู่ในฐานข้อมูล — ไม่ลบข้อมูลผู้ใช้เงียบๆ
    expect((await DbService.getTokensForSlot(1)).map((t) => t.contractAddress),
        contains(stale));
    // USDT (สัญญายังอยู่) ได้ยอด 2.5
    expect(provider.getTokenBalance('0x0a4ee87551ef041f3eecfbbfdcffc1b46a4878f1'), 2.5);
  });
}
