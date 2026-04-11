import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/tx_record.dart';

/// SQLite database service for TPIX Wallet
/// Stores transactions persistently with indexed queries
class DbService {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tpix_wallet.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tx_hash TEXT UNIQUE NOT NULL,
            from_address TEXT NOT NULL,
            to_address TEXT NOT NULL,
            value TEXT NOT NULL,
            direction TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            block_number INTEGER,
            timestamp INTEGER,
            created_at TEXT NOT NULL,
            wallet_slot INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_tx_slot ON transactions(wallet_slot)');
        await db.execute('CREATE INDEX idx_tx_hash ON transactions(tx_hash)');
        await db.execute('CREATE INDEX idx_tx_timestamp ON transactions(wallet_slot, timestamp DESC)');
      },
    );
  }

  // ================================================================
  // Transaction CRUD
  // ================================================================

  /// Insert a transaction record (ignore if duplicate tx_hash)
  static Future<void> insertTx(TxRecord tx, int walletSlot) async {
    final db = await database;
    await db.insert(
      'transactions',
      {
        'tx_hash': tx.txHash,
        'from_address': tx.fromAddress,
        'to_address': tx.toAddress,
        'value': tx.value,
        'direction': tx.direction,
        'status': tx.status,
        'block_number': tx.blockNumber,
        'timestamp': tx.timestamp,
        'created_at': tx.createdAt,
        'wallet_slot': walletSlot,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Get transactions for a wallet slot, ordered by newest first
  static Future<List<TxRecord>> getTxForSlot(int walletSlot, {int limit = 200}) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'wallet_slot = ?',
      whereArgs: [walletSlot],
      orderBy: 'COALESCE(timestamp, 0) DESC, id DESC',
      limit: limit,
    );
    return rows.map(_rowToTxRecord).toList();
  }

  /// Update transaction status by hash
  static Future<void> updateTxStatus(String txHash, String newStatus) async {
    final db = await database;
    await db.update(
      'transactions',
      {'status': newStatus},
      where: 'tx_hash = ?',
      whereArgs: [txHash],
    );
  }

  /// Check if a transaction hash already exists
  static Future<bool> txExists(String txHash) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      columns: ['id'],
      where: 'tx_hash = ?',
      whereArgs: [txHash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get transaction count for a wallet
  static Future<int> getTxCount(int walletSlot) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM transactions WHERE wallet_slot = ?',
      [walletSlot],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete all transactions for a wallet slot
  static Future<void> deleteTxForSlot(int walletSlot) async {
    final db = await database;
    await db.delete(
      'transactions',
      where: 'wallet_slot = ?',
      whereArgs: [walletSlot],
    );
  }

  /// Bulk insert transactions (for migration or scan)
  static Future<void> insertTxBatch(List<TxRecord> txList, int walletSlot) async {
    final db = await database;
    final batch = db.batch();
    for (final tx in txList) {
      batch.insert(
        'transactions',
        {
          'tx_hash': tx.txHash,
          'from_address': tx.fromAddress,
          'to_address': tx.toAddress,
          'value': tx.value,
          'direction': tx.direction,
          'status': tx.status,
          'block_number': tx.blockNumber,
          'timestamp': tx.timestamp,
          'created_at': tx.createdAt,
          'wallet_slot': walletSlot,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  // ================================================================
  // Helpers
  // ================================================================

  static TxRecord _rowToTxRecord(Map<String, dynamic> row) {
    return TxRecord(
      txHash: row['tx_hash'] as String,
      fromAddress: row['from_address'] as String,
      toAddress: row['to_address'] as String,
      value: row['value'] as String,
      direction: row['direction'] as String,
      status: row['status'] as String,
      blockNumber: row['block_number'] as int?,
      timestamp: row['timestamp'] as int?,
      createdAt: row['created_at'] as String?,
    );
  }

  /// Close database
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
