/// TPIX Wallet — JSON-RPC client ที่สลับไป RPC สำรองเองเมื่อตัวหลักใช้ไม่ได้
///
/// ทำไมต้องมี:
///   rpc.tpix.online อยู่หลัง Cloudflare ซึ่งบางครั้งบล็อกบางเครื่อง (ตอบหน้า HTML
///   403 แทน JSON) ของเดิมยิง RPC ตัวเดียว พังเมื่อไหร่ = ยอดเงินกลายเป็น 0 และส่งเงินไม่ได้
///   ทั้งที่ rpc1.tpix.online (ไม่มีตัวกรอง) ใช้ได้ปกติ
///
/// กติกาการสลับ:
///   - สลับไปตัวถัดไป เมื่อ "ไปไม่ถึง/ตอบไม่เป็น JSON-RPC" เท่านั้น:
///     เน็ตหลุด, timeout, HTTP 403/429/5xx หรือสถานะไม่ใช่ 2xx, body ไม่ใช่ JSON
///   - "ไม่สลับ" เมื่อโหนดตอบ JSON-RPC error กลับมา (เช่น insufficient funds,
///     nonce too low, execution reverted) — นั่นคือคำตอบจริงของเชน
///     ยิงซ้ำที่โหนดอื่นก็ได้คำตอบเดิม และสำหรับการส่งธุรกรรมอาจทำให้สับสน
///   - จำตัวที่ใช้ได้ล่าสุดไว้ (sticky) ครั้งหน้าเริ่มจากตัวนั้น ไม่ต้องรอ timeout ตัวที่พังทุกรอบ
///
/// Developed by Xman Studio
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpException, SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chain_config.dart';

/// โหนดตอบ JSON-RPC error กลับมาจริง — เป็นคำตอบของเชน ไม่ใช่ปัญหาเครือข่าย
class RpcException implements Exception {
  final int? code;
  final String message;

  const RpcException(this.message, {this.code});

  @override
  String toString() => message;
}

/// RPC ทุกตัวในลิสต์ติดต่อไม่ได้ (เน็ต/timeout/ถูกบล็อก/ล่ม)
///
/// ข้อความตั้งใจไม่ใส่ URL — ห้าม endpoint หลุดไปถึงหน้าจอผู้ใช้
class RpcUnavailableException implements Exception {
  /// จำนวนตัวที่ลองไปแล้ว (ไว้ debug เท่านั้น)
  final int attempts;

  const RpcUnavailableException(this.attempts);

  @override
  String toString() => 'Network unavailable — could not reach TPIX Chain';
}

class RpcClient {
  RpcClient(
    List<String> urls, {
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  })  : assert(urls.isNotEmpty),
        urls = List.unmodifiable(urls),
        _http = httpClient ?? http.Client();

  /// ลำดับ RPC — ตัวแรกคือตัวหลัก ที่เหลือคือสำรอง
  final List<String> urls;

  /// เวลารอต่อหนึ่ง RPC (ไม่ใช่รวมทั้งลิสต์)
  final Duration timeout;

  final http.Client _http;

  /// ตัวที่ใช้ได้ล่าสุด — รอบหน้าเริ่มจากตัวนี้
  int _preferred = 0;
  int _nextId = 1;

  /// RPC ที่ใช้ได้ล่าสุด (ไว้แสดงในหน้าตั้งค่า/debug)
  String get activeUrl => urls[_preferred];

  // ================================================================
  // Registry ต่อเชน — ใช้ client เดียวทั้งแอป เพื่อแชร์ sticky + connection
  // ================================================================

  static final Map<int, RpcClient> _byChain = {};

  /// client ของเชนนั้น (หลัก + สำรองจาก [ChainConfig.rpcUrls])
  static RpcClient forChain(ChainConfig chain) =>
      _byChain.putIfAbsent(chain.chainId, () => RpcClient(chain.rpcUrls));

  /// client ของ TPIX Chain
  static RpcClient get tpix => forChain(ChainConfig.tpix);

  /// หา client จาก URL ที่ผู้เรียกส่งมา (โค้ดเก่าส่ง rpcUrl เป็นสตริง)
  /// ถ้า URL เป็นของเชนที่รู้จัก → ได้ลิสต์สำรองของเชนนั้นด้วย
  static RpcClient forUrl(String rpcUrl, {int? chainId}) {
    for (final chain in ChainConfig.all) {
      if (chain.rpcUrls.contains(rpcUrl) || chain.chainId == chainId) {
        return forChain(chain);
      }
    }
    // URL นอกลิสต์ — แคชไว้ด้วย ไม่งั้นเปิด http.Client ใหม่ทิ้งไว้ทุกครั้งที่เรียก
    return _byUrl.putIfAbsent(rpcUrl, () => RpcClient([rpcUrl]));
  }

  static final Map<String, RpcClient> _byUrl = {};

  /// เทสต์ใช้แทน client จริงของเชน (null = ล้างกลับเป็นค่าเริ่มต้น)
  @visibleForTesting
  static void overrideForChain(int chainId, RpcClient? client) {
    if (client == null) {
      _byChain.remove(chainId);
    } else {
      _byChain[chainId] = client;
    }
  }

  // ================================================================
  // Call
  // ================================================================

  /// เรียก JSON-RPC หนึ่งครั้ง — คืนค่า `result` (อาจเป็น null ได้ เช่น receipt ที่ยังไม่ขุด)
  ///
  /// throws [RpcException] เมื่อโหนดตอบ error
  /// throws [RpcUnavailableException] เมื่อติดต่อไม่ได้สักตัว
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': _nextId++,
    });

    var attempts = 0;
    for (var i = 0; i < urls.length; i++) {
      final index = (_preferred + i) % urls.length;
      attempts++;
      final outcome = await _tryOnce(urls[index], body);
      if (outcome is _Ok) {
        _preferred = index;
        return outcome.result;
      }
      if (outcome is _RpcError) {
        // โหนดตอบมาแล้ว = เครือข่ายใช้ได้ จำตัวนี้ไว้ แต่ไม่ลองตัวอื่นซ้ำ
        _preferred = index;
        throw RpcException(outcome.message, code: outcome.code);
      }
      debugPrint('RpcClient: $method failed on rpc #$index (${(outcome as _Transport).reason})');
    }
    throw RpcUnavailableException(attempts);
  }

  Future<_Outcome> _tryOnce(String url, String body) async {
    try {
      final response = await _http
          .post(
            Uri.parse(url),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              // ไม่มี User-Agent = Cloudflare หน้า rpc.tpix.online ตอบหน้า HTML บล็อก
              'User-Agent': 'TPIX-Wallet (Flutter)',
            },
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _Transport('http ${response.statusCode}');
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        // Cloudflare challenge ตอบ HTML มาพร้อมสถานะ 200 ได้
        return const _Transport('non-json body');
      }
      if (decoded is! Map<String, dynamic>) {
        return const _Transport('unexpected body');
      }

      final error = decoded['error'];
      if (error != null) {
        if (error is Map) {
          final code = error['code'];
          return _RpcError(
            (error['message'] ?? 'RPC error').toString(),
            code is int ? code : null,
          );
        }
        return _RpcError(error.toString(), null);
      }
      if (!decoded.containsKey('result')) {
        return const _Transport('missing result');
      }
      return _Ok(decoded['result']);
    } on TimeoutException {
      return const _Transport('timeout');
    } on SocketException {
      return const _Transport('socket');
    } on HandshakeException {
      return const _Transport('tls');
    } on HttpException {
      return const _Transport('http exception');
    } on http.ClientException {
      return const _Transport('client exception');
    }
  }

  /// ปิด connection (ใช้ในเทสต์ — client ของเชนอยู่ตลอดอายุแอป)
  void close() => _http.close();

  // ================================================================
  // Helpers สำหรับเมธอดที่ใช้บ่อย
  // ================================================================

  /// แปลง quantity hex ของ JSON-RPC ("0x1a") เป็น BigInt — "0x" / "" = 0
  static BigInt parseQuantity(dynamic value) {
    if (value is! String) {
      throw const FormatException('Expected hex quantity');
    }
    final hex = value.startsWith('0x') || value.startsWith('0X')
        ? value.substring(2)
        : value;
    if (hex.isEmpty) return BigInt.zero;
    return BigInt.parse(hex, radix: 16);
  }

  /// ยอด native (wei) — throws เมื่อดึงไม่ได้ (ห้ามคืน 0 แทนความล้มเหลว)
  Future<BigInt> getBalance(String address) async =>
      parseQuantity(await call('eth_getBalance', [address, 'latest']));

  Future<int> getBlockNumber() async =>
      parseQuantity(await call('eth_blockNumber')).toInt();

  Future<BigInt> getGasPrice() async =>
      parseQuantity(await call('eth_gasPrice'));

  /// nonce ถัดไปรวมธุรกรรมที่ค้างใน mempool
  Future<int> getPendingNonce(String address) async => parseQuantity(
          await call('eth_getTransactionCount', [address, 'pending']))
      .toInt();

  /// bytecode ของสัญญา — "0x" = ไม่มีสัญญาที่ที่อยู่นี้
  /// ผลแปลกๆ (ไม่ใช่สตริง) → throw ให้ผู้เรียกถือว่า "ไม่รู้" ไม่ใช่ "ไม่มีสัญญา"
  Future<String> getCode(String address) async {
    final result = await call('eth_getCode', [address, 'latest']);
    if (result is! String) {
      throw const FormatException('eth_getCode: unexpected result');
    }
    return result;
  }

  Future<String?> ethCall(String to, String data) async {
    final result = await call('eth_call', [
      {'to': to, 'data': data},
      'latest',
    ]);
    return result is String ? result : null;
  }
}

// ผลของการยิงหนึ่ง URL — แยกชนิดชัดเจนว่าควรลองตัวถัดไปหรือไม่
sealed class _Outcome {
  const _Outcome();
}

class _Ok extends _Outcome {
  final dynamic result;
  const _Ok(this.result);
}

class _RpcError extends _Outcome {
  final String message;
  final int? code;
  const _RpcError(this.message, this.code);
}

class _Transport extends _Outcome {
  final String reason;
  const _Transport(this.reason);
}
