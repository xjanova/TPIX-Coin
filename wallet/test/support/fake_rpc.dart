/// RPC ปลอมสำหรับเทสต์ — ตอบตามชื่อเมธอด (และ selector ของ eth_call) โดยไม่ยิงเน็ตจริง
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tpix_wallet/services/rpc_client.dart';

/// โยนจาก handler = โหนดตอบ JSON-RPC error (เช่น execution reverted)
class FakeRpcError implements Exception {
  final String message;
  const FakeRpcError(this.message);
}

typedef FakeRpcHandler = Object? Function(List<dynamic> params);

/// เลข 32 ไบต์แบบ ABI (ผลของ eth_call ที่คืน uint)
String abiUint(BigInt v) => '0x${v.toRadixString(16).padLeft(64, '0')}';

String hexQty(BigInt v) => '0x${v.toRadixString(16)}';

class FakeRpc {
  FakeRpc(this.handlers);

  final Map<String, FakeRpcHandler> handlers;

  /// เมธอดที่ถูกเรียก ตามลำดับ
  final List<String> calls = [];

  /// พารามิเตอร์ของแต่ละครั้ง (ลำดับเดียวกับ [calls])
  final List<List<dynamic>> params = [];

  late final RpcClient client = RpcClient(['https://rpc.fake.test'], httpClient: MockClient(_handle));

  Future<http.Response> _handle(http.Request req) async {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final method = body['method'] as String;
    final p = (body['params'] as List?) ?? const [];
    calls.add(method);
    params.add(p);
    final handler = handlers[method];
    if (handler == null) {
      return _json({'jsonrpc': '2.0', 'id': body['id'], 'error': {'code': -32601, 'message': 'method not found: $method'}});
    }
    try {
      return _json({'jsonrpc': '2.0', 'id': body['id'], 'result': handler(p)});
    } on FakeRpcError catch (e) {
      return _json({'jsonrpc': '2.0', 'id': body['id'], 'error': {'code': 3, 'message': e.message}});
    }
  }

  static http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

  /// handler ของ eth_call ที่แยกตาม selector (4 ไบต์แรกของ data)
  static FakeRpcHandler ethCall(Map<String, Object? Function(String to, String data)> bySelector) => (p) {
        final call = p.first as Map;
        final data = (call['data'] as String).toLowerCase();
        final selector = data.substring(0, 10);
        final h = bySelector[selector];
        if (h == null) throw const FakeRpcError('execution reverted');
        return h((call['to'] as String).toLowerCase(), data);
      };
}

const selDecimals = '0x313ce567';
const selBalanceOf = '0x70a08231';
