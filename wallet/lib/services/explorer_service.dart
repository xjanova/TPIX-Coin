/// TPIX Wallet — ประวัติธุรกรรมจาก TPIX Explorer (Blockscout v2 API)
///
/// ทำไมไม่สแกนบล็อกอย่างเดียว:
///   - สแกนได้แค่ ~50 บล็อกล่าสุด (บล็อกละ 2 วินาที = ไม่ถึง 2 นาที) เปิดแอปช้ากว่านั้นก็ไม่เห็น
///   - การ "รับ" โทเค็น ERC-20 (เช่น USDT) ไม่มีที่อยู่เราอยู่ใน from/to ของธุรกรรม
///     ต้องอ่านจาก event Transfer ซึ่ง explorer จัดเตรียมไว้ให้แล้ว
///
/// explorer ล่ม/ตอบผิดรูป → คืน null ให้ผู้เรียกถอยไปสแกนบล็อกแบบเดิม
///
/// Developed by Xman Studio
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tx_record.dart';

class ExplorerService {
  ExplorerService._();

  static const String baseUrl = 'https://explorer.tpix.online/api/v2';
  static const Duration _timeout = Duration(seconds: 12);

  /// เทสต์เปลี่ยนเป็น MockClient ได้
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// ประวัติหน้าแรก (ธุรกรรม + การโอนโทเค็น ERC-20) ของที่อยู่นี้
  /// null = explorer ใช้ไม่ได้ (ผู้เรียกควรใช้วิธีสำรอง) / [] = ไม่มีประวัติจริงๆ
  static Future<List<TxRecord>?> fetchHistory(String address) async {
    final client = clientFactory();
    try {
      final results = await Future.wait([
        _getJson(client, '$baseUrl/addresses/$address/transactions'),
        _getJson(client, '$baseUrl/addresses/$address/token-transfers?type=ERC-20'),
      ]);
      final txs = results[0];
      final transfers = results[1];
      // ธุรกรรมหลักต้องได้ ไม่งั้นถือว่า explorer ใช้ไม่ได้
      if (txs == null) return null;
      return mergeHistory(
        address: address,
        transactions: txs,
        tokenTransfers: transfers ?? const {'items': []},
      );
    } catch (e) {
      debugPrint('ExplorerService.fetchHistory: ${e.runtimeType}');
      return null;
    } finally {
      client.close();
    }
  }

  /// GET แล้วแปลงเป็น JSON — 404 "Not found" ของ Blockscout = ที่อยู่ที่ยังไม่เคยมีธุรกรรม
  static Future<Map<String, dynamic>?> _getJson(http.Client client, String url) async {
    try {
      final res = await client.get(Uri.parse(url), headers: const {
        'Accept': 'application/json',
        'User-Agent': 'TPIX-Wallet (Flutter)',
      }).timeout(_timeout);
      if (res.statusCode == 404) return const {'items': []};
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    } on http.ClientException {
      return null;
    } catch (e) {
      debugPrint('ExplorerService._getJson: ${e.runtimeType}');
      return null;
    }
  }

  /// รวม "ธุรกรรม" กับ "การโอนโทเค็น" เป็นรายการเดียว (pure — เทสต์ได้)
  ///
  /// ตาราง transactions ใน SQLite ให้ tx_hash ไม่ซ้ำ → หนึ่ง hash ได้หนึ่งแถว:
  ///   - ธุรกรรมที่มี TPIX ติดไป (value > 0) → เก็บฝั่ง TPIX
  ///   - ไม่มี TPIX (เช่นเรียก transfer ของ USDT) → เก็บฝั่งโทเค็น ซึ่งบอกจำนวน/ผู้รับจริง
  ///   - รับโทเค็นอย่างเดียว (ไม่ได้เป็นคนส่งธุรกรรม) → มีแต่ฝั่งโทเค็น
  @visibleForTesting
  static List<TxRecord> mergeHistory({
    required String address,
    required Map<String, dynamic> transactions,
    required Map<String, dynamic> tokenTransfers,
  }) {
    final me = address.toLowerCase();
    final byHash = <String, TxRecord>{};

    for (final item in _items(transactions)) {
      final rec = _fromTransaction(item, me);
      if (rec != null) byHash[rec.txHash.toLowerCase()] = rec;
    }

    // ฝั่งโทเค็น: ถ้าหนึ่ง hash มีหลายการโอน (เช่นสวอป) เลือกขาที่เราเป็นคนส่งก่อน
    final tokenByHash = <String, TxRecord>{};
    for (final item in _items(tokenTransfers)) {
      final rec = _fromTokenTransfer(item, me);
      if (rec == null) continue;
      final key = rec.txHash.toLowerCase();
      final existing = tokenByHash[key];
      if (existing == null || (existing.direction != 'sent' && rec.direction == 'sent')) {
        tokenByHash[key] = rec;
      }
    }

    for (final entry in tokenByHash.entries) {
      final native = byHash[entry.key];
      final nativeHasValue = native != null && native.value != '0';
      if (!nativeHasValue) {
        // ใช้สถานะจากธุรกรรมหลัก (token-transfers ไม่บอกว่าธุรกรรมล้มหรือไม่)
        final t = entry.value;
        byHash[entry.key] = native == null
            ? t
            : TxRecord(
                txHash: t.txHash,
                fromAddress: t.fromAddress,
                toAddress: t.toAddress,
                value: t.value,
                direction: t.direction,
                status: native.status,
                blockNumber: t.blockNumber ?? native.blockNumber,
                timestamp: t.timestamp ?? native.timestamp,
                tokenAddress: t.tokenAddress,
                tokenSymbol: t.tokenSymbol,
                tokenDecimals: t.tokenDecimals,
              );
      }
    }

    final list = byHash.values.toList()
      ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
    return list;
  }

  static Iterable<Map<String, dynamic>> _items(Map<String, dynamic> page) {
    final items = page['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>();
  }

  static String? _hashOf(dynamic party) =>
      party is Map ? party['hash'] as String? : null;

  static int? _unixSeconds(dynamic iso) {
    if (iso is! String) return null;
    final dt = DateTime.tryParse(iso);
    return dt == null ? null : dt.millisecondsSinceEpoch ~/ 1000;
  }

  static TxRecord? _fromTransaction(Map<String, dynamic> item, String me) {
    final hash = item['hash'];
    final from = _hashOf(item['from']);
    final to = _hashOf(item['to']) ??
        _hashOf(item['created_contract']) ??
        '';
    final value = item['value'];
    if (hash is! String || from == null || value is! String) return null;
    if (BigInt.tryParse(value) == null) return null;

    final status = switch (item['status']) {
      'ok' => 'confirmed',
      'error' => 'failed',
      _ => 'pending',
    };
    return TxRecord(
      txHash: hash,
      fromAddress: from,
      toAddress: to,
      value: value,
      direction: from.toLowerCase() == me ? 'sent' : 'received',
      status: status,
      blockNumber: item['block_number'] as int?,
      timestamp: _unixSeconds(item['timestamp']),
    );
  }

  static TxRecord? _fromTokenTransfer(Map<String, dynamic> item, String me) {
    final hash = item['transaction_hash'] ?? item['tx_hash'];
    final from = _hashOf(item['from']);
    final to = _hashOf(item['to']);
    final token = item['token'];
    final total = item['total'];
    if (hash is! String || from == null || to == null) return null;
    if (token is! Map || total is! Map) return null;

    final tokenAddress = token['address'] ?? token['address_hash'];
    final symbol = token['symbol'];
    final decimals = int.tryParse('${total['decimals'] ?? token['decimals']}');
    final value = total['value'];
    if (tokenAddress is! String || value is! String || decimals == null) return null;
    if (BigInt.tryParse(value) == null) return null;

    final isMine = from.toLowerCase() == me || to.toLowerCase() == me;
    if (!isMine) return null;

    return TxRecord(
      txHash: hash,
      fromAddress: from,
      toAddress: to,
      value: value,
      direction: from.toLowerCase() == me ? 'sent' : 'received',
      status: 'confirmed',
      blockNumber: item['block_number'] as int?,
      timestamp: _unixSeconds(item['timestamp']),
      tokenAddress: tokenAddress,
      tokenSymbol: symbol is String && symbol.isNotEmpty ? symbol : '?',
      tokenDecimals: decimals,
    );
  }
}
