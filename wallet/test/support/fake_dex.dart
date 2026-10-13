/// TPIX DEX ปลอมสำหรับเทสต์ — เชน 4289 + เว็บ tpix.online (ทะเบียน/คู่เทรด) โดยไม่ยิงเน็ตจริง
///
/// router คิด getAmountsOut จาก reserve ของพูลด้วยสูตร UniV2 จริง — ตัวเลขในเทสต์จึงสอดคล้องกัน
/// ที่อยู่ทั้งหมดเป็นของปลอม (ห้ามคัดลอกไปใช้ในแอป — แอปต้องอ่านจาก /dex/config เท่านั้น)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes;

import 'fake_rpc.dart';

final dexRouter = '0x${'a1' * 20}';
final dexWtpix = '0x${'b2' * 20}';
final dexUsdt = '0x${'c3' * 20}';
final dexFactory = '0x${'d4' * 20}';
final dexToken = '0x${'f6' * 20}'; // เหรียญอื่นบนเชน (ไม่มีคู่ตรงกับ USDT)
const _zero = '0x0000000000000000000000000000000000000000';

final e18 = BigInt.from(10).pow(18);
final e6 = BigInt.from(10).pow(6);

const selDecimalsDex = '0x313ce567';
const selBalanceOfDex = '0x70a08231';
const selAllowance = '0xdd62ed3e';
const selGetAmountsOut = '0xd06ca61f';
const selGetPair = '0xe6a43905';
const selToken0 = '0x0dfe1681';
const selGetReserves = '0x0902f1ac';
const selApprove = '0x095ea7b3';
const selSwapEthForTokens = '0x7ff36ab5';
const selSwapTokensForEth = '0x18cbafe5';
const selSwapTokensForTokens = '0x38ed1739';

Map<String, dynamic> dexConfig({
  bool ready = true,
  int chainId = 4289,
  String? router,
  String? wtpix,
  String? usdt,
  String? factory,
}) =>
    {
      'ready': ready,
      'chainId': chainId,
      'rpc': 'https://rpc.tpix.online',
      'missing': const [],
      'WTPIX': wtpix ?? dexWtpix,
      'USDT': usdt ?? dexUsdt,
      'FACTORY': factory ?? dexFactory,
      'ROUTER': router ?? dexRouter,
    };

Map<String, dynamic> dexPair(
  String base,
  String baseAddr,
  int baseDec,
  String quote,
  String quoteAddr,
  int quoteDec, {
  bool active = true,
  int chainId = 4289,
}) =>
    {
      'symbol': '$base-$quote',
      'base_asset': base,
      'quote_asset': quote,
      'base_address': baseAddr,
      'quote_address': quoteAddr,
      'base_decimals': baseDec,
      'quote_decimals': quoteDec,
      'base_logo': null,
      'quote_logo': null,
      'is_active': active,
      'chain_id': chainId,
    };

/// คู่จริงวันนี้: TPIX-USDT เท่านั้น
List<Map<String, dynamic>> livePairs() => [dexPair('TPIX', _zero, 18, 'USDT', dexUsdt, 6)];

String _word(BigInt v) => v.toRadixString(16).padLeft(64, '0');
String _addrWord(String a) => a.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');

/// เว็บ tpix.online ปลอม: /dex/config + /dex/pairs + ปลายทางบันทึกไม้ของ WalletAuthService
class FakeDexSite {
  Map<String, dynamic> config = dexConfig();
  List<Map<String, dynamic>> pairs = livePairs();

  /// เว็บตอบหน้า HTML ของ Cloudflare (200) แทน JSON
  bool down = false;
  int configCalls = 0;

  /// body ของ POST /swap/execute ที่แอปส่งมา
  final List<Map<String, dynamic>> recorded = [];

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json; charset=utf-8'});

  http.Client client() => MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/dex/config')) {
          configCalls++;
          if (down) return http.Response('<!DOCTYPE html><html>Cloudflare</html>', 200);
          return _json({'success': true, 'data': config});
        }
        if (path.endsWith('/dex/pairs')) {
          if (down) return http.Response('<!DOCTYPE html><html>Cloudflare</html>', 200);
          return _json({'success': true, 'data': pairs});
        }
        if (path.endsWith('/wallet/connect')) return _json({'success': true});
        if (path.endsWith('/wallet/sign')) {
          return _json({'success': true, 'data': {'message': 'Sign in to TPIX', 'nonce': 'n1'}});
        }
        if (path.endsWith('/wallet/verify-signature')) return _json({'success': true, 'verified': true});
        if (path.endsWith('/swap/execute')) {
          recorded.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json({'success': true});
        }
        return _json({'success': false}, 404);
      });
}

class _Pool {
  _Pool(this.address, this.token0, this.reserve0, this.reserve1);
  final String address;
  final String token0;
  BigInt reserve0;
  BigInt reserve1;
}

/// เชน TPIX ปลอมที่มี router / factory / พูล / เหรียญ
class FakeDexChain {
  FakeDexChain() {
    // พูล WTPIX/USDT: 1,000,000 TPIX ↔ 100,000 USDT (ราคา 0.1)
    addPool(dexWtpix, dexUsdt, BigInt.from(1000000) * e18, BigInt.from(100000) * e6);
    decimals[dexUsdt] = 6;
    decimals[dexWtpix] = 18;
    decimals[dexToken] = 18;
  }

  final Map<String, _Pool> _pools = {};
  final Map<String, int> decimals = {};

  /// ยอดเหรียญ ERC-20 ของผู้ใช้ (ทุกกระเป๋าใช้ยอดเดียวกัน — เทสต์มีผู้ใช้คนเดียว)
  final Map<String, BigInt> tokenBalances = {};
  final Map<String, BigInt> allowances = {};
  BigInt nativeBalance = BigInt.from(5000) * e18;

  /// สถานะใบเสร็จ: '0x1' สำเร็จ · '0x0' ล้ม · null = ยังไม่ขุด
  String? receiptStatus = '0x1';
  int chainId = 4289;

  /// eth_estimateGas จำลองแล้ว revert
  bool estimateReverts = false;

  final List<String> rawTxs = [];
  int _poolSeq = 0;

  void addPool(String a, String b, BigInt reserveA, BigInt reserveB) {
    final x = a.toLowerCase();
    final y = b.toLowerCase();
    final token0 = x.compareTo(y) < 0 ? x : y;
    final addr = '0x${(++_poolSeq).toRadixString(16).padLeft(2, '0') * 20}';
    _pools[_key(x, y)] = _Pool(addr, token0, token0 == x ? reserveA : reserveB, token0 == x ? reserveB : reserveA);
  }

  static String _key(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  _Pool? _poolAt(String address) {
    for (final p in _pools.values) {
      if (p.address == address) return p;
    }
    return null;
  }

  BigInt _out(BigInt amountIn, String a, String b) {
    final p = _pools[_key(a, b)];
    if (p == null) throw const FakeRpcError('execution reverted: TPIX: INSUFFICIENT_LIQUIDITY');
    final rIn = p.token0 == a ? p.reserve0 : p.reserve1;
    final rOut = p.token0 == a ? p.reserve1 : p.reserve0;
    final inWithFee = amountIn * BigInt.from(997);
    return (inWithFee * rOut) ~/ (rIn * BigInt.from(1000) + inWithFee);
  }

  /// แยก calldata เป็นคำละ 32 ไบต์ (ไม่รวม selector)
  static List<String> _words(String data) {
    final body = data.substring(10);
    return [for (var i = 0; i + 64 <= body.length; i += 64) body.substring(i, i + 64)];
  }

  static String _addr(String word) => '0x${word.substring(24)}';

  late final FakeRpc rpc = FakeRpc({
    'eth_chainId': (_) => hexQty(BigInt.from(chainId)),
    'eth_getBalance': (_) => hexQty(nativeBalance),
    'eth_estimateGas': (_) {
      if (estimateReverts) throw const FakeRpcError('execution reverted: TPIX: INSUFFICIENT_OUTPUT_AMOUNT');
      return '0x30d40';
    },
    'eth_getTransactionCount': (_) => '0x0',
    'eth_sendRawTransaction': (p) {
      final raw = p.first as String;
      rawTxs.add(raw);
      final tx = decodeLegacyTx(raw);
      final data = bytesToHex(tx.data, include0x: true);
      // approve ที่ส่งจริง → allowance บนเชนเปลี่ยนตาม (ผู้ใช้คนเดียว)
      if (data.startsWith(selApprove)) {
        allowances[tx.to] = BigInt.parse(_words(data)[1], radix: 16);
      }
      return '0x${rawTxs.length.toRadixString(16).padLeft(64, '0')}';
    },
    'eth_getTransactionReceipt': (_) => receiptStatus == null ? null : {'status': receiptStatus},
    'eth_call': FakeRpc.ethCall({
      selDecimalsDex: (to, data) {
        final d = decimals[to];
        if (d == null) throw const FakeRpcError('execution reverted');
        return abiUint(BigInt.from(d));
      },
      selBalanceOfDex: (to, data) => abiUint(tokenBalances[to] ?? BigInt.zero),
      selAllowance: (to, data) => abiUint(allowances[to] ?? BigInt.zero),
      selGetAmountsOut: (to, data) {
        if (to != dexRouter) throw const FakeRpcError('execution reverted');
        final w = _words(data);
        final amountIn = BigInt.parse(w[0], radix: 16);
        final n = int.parse(w[2], radix: 16);
        final path = [for (var i = 0; i < n; i++) _addr(w[3 + i])];
        final amounts = [amountIn];
        for (var i = 0; i < n - 1; i++) {
          amounts.add(_out(amounts.last, path[i], path[i + 1]));
        }
        return '0x${_word(BigInt.from(32))}${_word(BigInt.from(n))}${amounts.map(_word).join()}';
      },
      selGetPair: (to, data) {
        if (to != dexFactory) throw const FakeRpcError('execution reverted');
        final w = _words(data);
        final p = _pools[_key(_addr(w[0]), _addr(w[1]))];
        return '0x${_addrWord(p?.address ?? _zero)}';
      },
      selToken0: (to, data) {
        final p = _poolAt(to);
        if (p == null) throw const FakeRpcError('execution reverted');
        return '0x${_addrWord(p.token0)}';
      },
      selGetReserves: (to, data) {
        final p = _poolAt(to);
        if (p == null) throw const FakeRpcError('execution reverted');
        return '0x${_word(p.reserve0)}${_word(p.reserve1)}${_word(BigInt.zero)}';
      },
    }),
  });

  List<String> get calls => rpc.calls;
}

/// ธุรกรรม legacy (EIP-155) ที่ถอดจาก raw — ใช้ตรวจว่าแอปเซ็นอะไรออกไปจริง
class DecodedTx {
  DecodedTx(this.nonce, this.gasPrice, this.gas, this.to, this.value, this.data, this.v);
  final BigInt nonce;
  final BigInt gasPrice;
  final BigInt gas;
  final String to;
  final BigInt value;
  final Uint8List data;
  final BigInt v;

  /// chain id จาก v ของ EIP-155: v = chainId·2 + 35/36
  int get chainId => ((v - BigInt.from(35)) ~/ BigInt.two).toInt();

  String get selector => bytesToHex(data.sublist(0, 4), include0x: true);

  /// คำที่ [i] ของ calldata (หลัง selector)
  BigInt word(int i) => BigInt.parse(bytesToHex(data.sublist(4 + 32 * i, 36 + 32 * i)), radix: 16);
}

/// ถอด RLP ของธุรกรรม legacy ที่เซ็นแล้ว: [nonce, gasPrice, gas, to, value, data, v, r, s]
DecodedTx decodeLegacyTx(String rawHex) {
  final b = hexToBytes(rawHex);
  var p = 0;

  int readLen(int count) {
    var len = 0;
    for (var i = 0; i < count; i++) {
      len = (len << 8) | b[p + 1 + i];
    }
    return len;
  }

  Uint8List item() {
    final prefix = b[p];
    if (prefix < 0x80) {
      p += 1;
      return Uint8List.fromList([prefix]);
    }
    int start;
    int len;
    if (prefix <= 0xb7) {
      len = prefix - 0x80;
      start = p + 1;
    } else {
      final ll = prefix - 0xb7;
      len = readLen(ll);
      start = p + 1 + ll;
    }
    p = start + len;
    return Uint8List.sublistView(b, start, start + len);
  }

  // หัวของลิสต์ชั้นนอก
  final head = b[p];
  p += head <= 0xf7 ? 1 : 1 + (head - 0xf7);

  BigInt uint(Uint8List x) => x.isEmpty ? BigInt.zero : BigInt.parse(bytesToHex(x), radix: 16);
  final nonce = uint(item());
  final gasPrice = uint(item());
  final gas = uint(item());
  final to = bytesToHex(item(), include0x: true);
  final value = uint(item());
  final data = Uint8List.fromList(item());
  final v = uint(item());
  return DecodedTx(nonce, gasPrice, gas, to, value, data, v);
}
