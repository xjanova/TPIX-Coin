/// TPIX Wallet — เทสต์ประวัติธุรกรรมโทเค็น (explorer + ฐานข้อมูล v7)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tpix_wallet/models/tx_record.dart';
import 'package:tpix_wallet/services/db_service.dart';
import 'package:tpix_wallet/services/explorer_service.dart';
import 'support/isolated_db.dart';

const _me = '0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7';
const _other = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _usdt = '0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1';

Map<String, dynamic> _tx({
  required String hash,
  required String from,
  required String to,
  String value = '0',
  String status = 'ok',
}) =>
    {
      'hash': hash,
      'from': {'hash': from},
      'to': {'hash': to},
      'value': value,
      'status': status,
      'block_number': 100,
      'timestamp': '2026-10-10T17:25:40.000000Z',
    };

Map<String, dynamic> _transfer({
  required String hash,
  required String from,
  required String to,
  required String value,
}) =>
    {
      'transaction_hash': hash,
      'from': {'hash': from},
      'to': {'hash': to},
      'token': {'address': _usdt, 'symbol': 'USDT', 'decimals': '6', 'type': 'ERC-20'},
      'total': {'decimals': '6', 'value': value},
      'block_number': 101,
      'timestamp': '2026-10-10T17:30:00.000000Z',
    };

void main() {
  group('ExplorerService.mergeHistory', () {
    test('ส่ง USDT: ธุรกรรม value 0 ไปที่สัญญา → กลายเป็น "ส่ง 1 USDT ให้ผู้รับ"', () {
      final list = ExplorerService.mergeHistory(
        address: _me,
        transactions: {
          'items': [_tx(hash: '0xaa', from: _me, to: _usdt)],
        },
        tokenTransfers: {
          'items': [_transfer(hash: '0xaa', from: _me, to: _other, value: '1000000')],
        },
      );
      expect(list, hasLength(1));
      final r = list.single;
      expect(r.direction, 'sent');
      expect(r.toAddress, _other);
      expect(r.symbol, 'USDT');
      expect(r.amount, 1.0);
      expect(r.status, 'confirmed');
    });

    test('รับ USDT (ไม่ได้เป็นคนส่งธุรกรรม) → เห็นจาก token-transfers', () {
      final list = ExplorerService.mergeHistory(
        address: _me,
        transactions: {'items': []},
        tokenTransfers: {
          'items': [_transfer(hash: '0xbb', from: _other, to: _me, value: '2500000')],
        },
      );
      expect(list.single.direction, 'received');
      expect(list.single.amount, 2.5);
    });

    test('ธุรกรรมที่มี TPIX ติดไป (เช่นสวอป) → เก็บฝั่ง TPIX ไม่ถูกทับ', () {
      final list = ExplorerService.mergeHistory(
        address: _me,
        transactions: {
          'items': [
            _tx(hash: '0xcc', from: _me, to: _other, value: '1000000000000000000'),
          ],
        },
        tokenTransfers: {
          'items': [_transfer(hash: '0xcc', from: _other, to: _me, value: '99')],
        },
      );
      expect(list.single.isTpix, isTrue);
      expect(list.single.amount, 1.0);
    });

    test('ธุรกรรมล้ม → failed, ข้อมูลผิดรูปถูกข้าม', () {
      final list = ExplorerService.mergeHistory(
        address: _me,
        transactions: {
          'items': [
            _tx(hash: '0xdd', from: _me, to: _other, value: '5', status: 'error'),
            {'hash': 123},
          ],
        },
        tokenTransfers: const {'items': 'oops'},
      );
      expect(list.single.status, 'failed');
    });
  });

  group('ฐานข้อมูล v7 — คอลัมน์โทเค็นในธุรกรรม', () {
    // ฐานข้อมูลแยกของไฟล์นี้ — กันชนกับไฟล์เทสต์อื่นที่รันพร้อมกัน
    setUpAll(() => useIsolatedTestDb('tx_history_token'));

    setUp(() async {
      await DbService.close();
      await databaseFactory.deleteDatabase(
        '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db',
      );
    });

    tearDownAll(() async => DbService.close());

    test('อัปเกรด v6 → v7: แถวเดิมอยู่ครบ และเป็น TPIX เหมือนเดิม', () async {
      final path = '${await databaseFactory.getDatabasesPath()}/tpix_wallet.db';
      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE transactions(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tx_hash TEXT UNIQUE NOT NULL, from_address TEXT NOT NULL,
                to_address TEXT NOT NULL, value TEXT NOT NULL,
                direction TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
                block_number INTEGER, timestamp INTEGER,
                created_at TEXT NOT NULL, wallet_slot INTEGER NOT NULL)
            ''');
            await db.insert('transactions', {
              'tx_hash': '0xold',
              'from_address': _me,
              'to_address': _other,
              'value': '1000000000000000000',
              'direction': 'sent',
              'status': 'confirmed',
              'created_at': '2026-01-01',
              'wallet_slot': 1,
            });
          },
        ),
      );
      await old.close();

      final db = await DbService.database;
      expect(await db.getVersion(), 7);
      final rows = await DbService.getTxForSlot(1);
      expect(rows.single.txHash, '0xold');
      expect(rows.single.isTpix, isTrue);
      expect(rows.single.amount, 1.0);
    });

    test('บันทึกธุรกรรม USDT แล้วอ่านกลับได้สัญลักษณ์/ทศนิยมถูก', () async {
      await DbService.insertTx(
        TxRecord(
          txHash: '0xusdt',
          fromAddress: _me,
          toAddress: _other,
          value: '1500000',
          direction: 'sent',
          tokenAddress: _usdt,
          tokenSymbol: 'USDT',
          tokenDecimals: 6,
        ),
        1,
      );
      final r = (await DbService.getTxForSlot(1)).single;
      expect(r.symbol, 'USDT');
      expect(r.amount, 1.5);
      expect(r.tokenAddress, _usdt.toLowerCase());
    });

    test('upsert จาก explorer: pending → confirmed และเติมข้อมูลโทเค็นให้แถวที่สแกนเจอ', () async {
      // ส่งเองแล้วยัง pending
      await DbService.insertTx(
        TxRecord(txHash: '0xp', fromAddress: _me, toAddress: _other, value: '5', direction: 'sent'),
        1,
      );
      // สแกนบล็อกเจอการเรียกสัญญา USDT แบบ value 0 (ยังไม่รู้ว่าเป็นโทเค็น)
      await DbService.insertTx(
        TxRecord(
            txHash: '0xs', fromAddress: _me, toAddress: _usdt, value: '0', direction: 'sent',
            status: 'confirmed'),
        1,
      );

      await DbService.upsertTxBatch([
        TxRecord(
            txHash: '0xp', fromAddress: _me, toAddress: _other, value: '5', direction: 'sent',
            status: 'confirmed', blockNumber: 9),
        TxRecord(
          txHash: '0xs',
          fromAddress: _me,
          toAddress: _other,
          value: '1000000',
          direction: 'sent',
          status: 'confirmed',
          tokenAddress: _usdt,
          tokenSymbol: 'USDT',
          tokenDecimals: 6,
        ),
      ], 1);

      final rows = {for (final r in await DbService.getTxForSlot(1)) r.txHash: r};
      expect(rows['0xp']!.status, 'confirmed');
      expect(rows['0xp']!.blockNumber, 9);
      expect(rows['0xs']!.symbol, 'USDT');
      expect(rows['0xs']!.toAddress, _other);
      expect(rows['0xs']!.amount, 1.0);
    });
  });
}
