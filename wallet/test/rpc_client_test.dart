/// TPIX Wallet — เทสต์การสลับ RPC สำรอง
///
/// กติกาที่ต้องกันพลาด:
///   - ตัวหลักไปไม่ถึง (403 จาก Cloudflare / HTML / 5xx / timeout / เน็ตหลุด) → ลองตัวถัดไป
///   - โหนดตอบ JSON-RPC error (เช่น insufficient funds) → "ไม่" ลองตัวอื่น ส่งต่อให้ผู้ใช้เลย
///   - ไปไม่ถึงสักตัว → RpcUnavailableException (ไม่ใช่คืน 0)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/services/rpc_client.dart';

const _primary = 'https://rpc.tpix.online';
const _fallback = 'https://rpc1.tpix.online';

http.Response _ok(dynamic result) => http.Response(
      jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _rpcError(String message) => http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'error': {'code': -32000, 'message': message},
      }),
      200,
    );

/// หน้าบล็อกของ Cloudflare — HTML ไม่ใช่ JSON
http.Response _cloudflareBlock([int status = 403]) => http.Response(
      '<!DOCTYPE html><html><head><title>Attention Required! | Cloudflare</title></head></html>',
      status,
      headers: {'content-type': 'text/html'},
    );

/// client ปลอม: ตอบตาม host + จดว่าเรียก host ไหนไปบ้าง
({RpcClient rpc, List<String> calls}) _client(
  FutureOr<http.Response> Function(String host) handler, {
  Duration timeout = const Duration(seconds: 2),
}) {
  final calls = <String>[];
  final mock = MockClient((req) async {
    calls.add(req.url.host);
    return handler(req.url.host);
  });
  return (
    rpc: RpcClient([_primary, _fallback], httpClient: mock, timeout: timeout),
    calls: calls,
  );
}

void main() {
  group('ChainConfig', () {
    test('TPIX Chain มี rpc1 เป็นตัวสำรอง และตัวหลักมาก่อน', () {
      expect(ChainConfig.tpix.rpcUrls, [_primary, _fallback]);
    });
  });

  group('RpcClient — สลับไปตัวสำรอง', () {
    test('ตัวหลักโดน Cloudflare 403 → ได้ผลจาก rpc1', () async {
      final c = _client((host) =>
          host == 'rpc.tpix.online' ? _cloudflareBlock() : _ok('0x10c1'));
      expect(await c.rpc.call('eth_chainId'), '0x10c1');
      expect(c.calls, ['rpc.tpix.online', 'rpc1.tpix.online']);
    });

    test('ตัวหลักตอบ HTML สถานะ 200 (challenge page) → ถือว่าไปไม่ถึง', () async {
      final c = _client((host) =>
          host == 'rpc.tpix.online' ? _cloudflareBlock(200) : _ok('0x1'));
      expect(await c.rpc.call('eth_blockNumber'), '0x1');
      expect(c.calls, hasLength(2));
    });

    test('ตัวหลัก 502 → ตัวสำรอง', () async {
      final c = _client((host) => host == 'rpc.tpix.online'
          ? http.Response('bad gateway', 502)
          : _ok('0x2'));
      expect(await c.rpc.call('eth_blockNumber'), '0x2');
    });

    test('ตัวหลักเน็ตหลุด (SocketException) → ตัวสำรอง', () async {
      final c = _client((host) {
        if (host == 'rpc.tpix.online') {
          throw const SocketException('Failed host lookup');
        }
        return _ok('0x3');
      });
      expect(await c.rpc.call('eth_blockNumber'), '0x3');
    });

    test('ตัวหลัก timeout → ตัวสำรอง', () async {
      final c = _client(
        (host) async {
          if (host == 'rpc.tpix.online') {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
          return _ok('0x4');
        },
        timeout: const Duration(milliseconds: 50),
      );
      expect(await c.rpc.call('eth_blockNumber'), '0x4');
      expect(c.calls, ['rpc.tpix.online', 'rpc1.tpix.online']);
    });

    test('จำตัวที่ใช้ได้ล่าสุด — ครั้งต่อไปเริ่มที่ rpc1 ไม่ต้องรอตัวหลักพังซ้ำ', () async {
      final c = _client((host) =>
          host == 'rpc.tpix.online' ? _cloudflareBlock() : _ok('0x5'));
      await c.rpc.call('eth_blockNumber');
      c.calls.clear();
      await c.rpc.call('eth_blockNumber');
      expect(c.calls, ['rpc1.tpix.online']);
      expect(c.rpc.activeUrl, _fallback);
    });
  });

  group('RpcClient — ไม่สลับเมื่อโหนดตอบ error จริง', () {
    test('insufficient funds → throw RpcException ทันที ไม่ยิงซ้ำที่ rpc1', () async {
      final c = _client((_) => _rpcError('insufficient funds for gas * price + value'));
      await expectLater(
        c.rpc.call('eth_sendRawTransaction', ['0xdead']),
        throwsA(isA<RpcException>().having(
            (e) => e.message, 'message', contains('insufficient funds'))),
      );
      expect(c.calls, ['rpc.tpix.online']);
    });

    test('result เป็น null ได้ (เช่น receipt ที่ยังไม่ขุด) ไม่ถือว่าพัง', () async {
      final c = _client((_) => _ok(null));
      expect(await c.rpc.call('eth_getTransactionReceipt', ['0x1']), isNull);
      expect(c.calls, hasLength(1));
    });
  });

  group('RpcClient — ไปไม่ถึงสักตัว', () {
    test('ทุกตัวพัง → RpcUnavailableException (ห้ามคืน 0)', () async {
      final c = _client((_) => _cloudflareBlock());
      await expectLater(
        c.rpc.getBalance('0x0a4ee87551ef041f3eecfbbfdcffc1b46a4878f1'),
        throwsA(isA<RpcUnavailableException>()),
      );
      expect(c.calls, hasLength(2));
    });

    test('ข้อความ error ไม่มี URL ของ RPC หลุดไปถึงผู้ใช้', () {
      expect(const RpcUnavailableException(2).toString(), isNot(contains('http')));
    });
  });

  group('helpers', () {
    test('parseQuantity', () {
      expect(RpcClient.parseQuantity('0x0'), BigInt.zero);
      expect(RpcClient.parseQuantity('0x'), BigInt.zero);
      expect(RpcClient.parseQuantity('0x10c1'), BigInt.from(4289));
      expect(() => RpcClient.parseQuantity(null), throwsFormatException);
    });

    test('getCode ตอบแปลกๆ (ไม่ใช่สตริง) = ไม่รู้ ไม่ใช่ "ไม่มีสัญญา"', () async {
      final c = _client((_) => _ok(null));
      await expectLater(c.rpc.getCode('0x1111111111111111111111111111111111111111'),
          throwsFormatException);
    });
  });
}
