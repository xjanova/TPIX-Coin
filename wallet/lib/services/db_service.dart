import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/tx_record.dart';
import '../models/token_info.dart';

/// SQLite database service for TPIX Wallet
/// Stores transactions and custom tokens persistently
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
      version: 4,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTokensTable(db);
        }
        if (oldVersion < 3) {
          await _createPriceHistoryTable(db);
        }
        if (oldVersion < 4) {
          await _addChainIdColumn(db);
        }
      },
    );
  }

  static Future<void> _createTables(Database db) async {
    // Transactions table
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

    // Tokens table
    await _createTokensTable(db);

    // Price history table
    await _createPriceHistoryTable(db);
  }

  static Future<void> _createTokensTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tokens(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contract_address TEXT NOT NULL,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        decimals INTEGER NOT NULL DEFAULT 18,
        wallet_slot INTEGER NOT NULL,
        chain_id INTEGER NOT NULL DEFAULT 4289,
        logo_url TEXT,
        added_at TEXT NOT NULL,
        UNIQUE(contract_address, wallet_slot, chain_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_token_slot ON tokens(wallet_slot)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_token_chain ON tokens(chain_id, wallet_slot)');
  }

  static Future<void> _addChainIdColumn(Database db) async {
    // Recreate tokens table to update UNIQUE constraint for multi-chain support
    // Old: UNIQUE(contract_address, wallet_slot)
    // New: UNIQUE(contract_address, wallet_slot, chain_id)
    // SQLite can't ALTER UNIQUE constraints, so we must recreate the table
    try {
      // Check if chain_id column already exists (fresh v3+ install)
      final tableInfo = await db.rawQuery("PRAGMA table_info('tokens')");
      final hasChainId = tableInfo.any((col) => col['name'] == 'chain_id');

      if (!hasChainId) {
        // Step 1: Rename old table
        await db.execute('ALTER TABLE tokens RENAME TO tokens_old');

        // Step 2: Create new table with updated UNIQUE constraint
        await db.execute('''
          CREATE TABLE tokens(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            contract_address TEXT NOT NULL,
            name TEXT NOT NULL,
            symbol TEXT NOT NULL,
            decimals INTEGER NOT NULL DEFAULT 18,
            wallet_slot INTEGER NOT NULL,
            chain_id INTEGER NOT NULL DEFAULT 4289,
            logo_url TEXT,
            added_at TEXT NOT NULL,
            UNIQUE(contract_address, wallet_slot, chain_id)
          )
        ''');

        // Step 3: Copy data from old table (all existing tokens get chain_id = 4289)
        await db.execute('''
          INSERT INTO tokens(contract_address, name, symbol, decimals, wallet_slot, chain_id, logo_url, added_at)
          SELECT contract_address, name, symbol, decimals, wallet_slot, 4289, logo_url, added_at
          FROM tokens_old
        ''');

        // Step 4: Drop old table
        await db.execute('DROP TABLE tokens_old');
      }
    } catch (e) {
      // Fallback: just try to add the column if recreation failed
      debugPrint('Token table migration failed, trying ALTER fallback: $e');
      try {
        await db.execute('ALTER TABLE tokens ADD COLUMN chain_id INTEGER NOT NULL DEFAULT 4289');
      } catch (e2) {
        debugPrint('ALTER TABLE fallback also failed: $e2');
        // If both fail, the column may already exist from a partial migration.
        // Verify by checking table_info; throw if column truly missing.
        final tableInfo = await db.rawQuery("PRAGMA table_info('tokens')");
        final hasChainId = tableInfo.any((col) => col['name'] == 'chain_id');
        if (!hasChainId) {
          throw Exception('Critical: tokens table missing chain_id column after migration');
        }
      }
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_token_slot ON tokens(wallet_slot)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_token_chain ON tokens(chain_id, wallet_slot)');
  }

  static Future<void> _createPriceHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        price REAL NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_price_ts ON price_history(timestamp)');
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
    await db.delete('transactions', where: 'wallet_slot = ?', whereArgs: [walletSlot]);
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
  // Token CRUD
  // ================================================================

  /// Add a custom token for a wallet slot
  static Future<void> addToken(TokenInfo token) async {
    final db = await database;
    await db.insert(
      'tokens',
      {
        'contract_address': token.contractAddress.toLowerCase(),
        'name': token.name,
        'symbol': token.symbol,
        'decimals': token.decimals,
        'wallet_slot': token.walletSlot,
        'chain_id': token.chainId,
        'logo_url': token.logoUrl,
        'added_at': token.addedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all tokens for a wallet slot (optionally filtered by chain)
  static Future<List<TokenInfo>> getTokensForSlot(int walletSlot, {int? chainId}) async {
    final db = await database;
    String where = 'wallet_slot = ?';
    List<Object?> whereArgs = [walletSlot];
    if (chainId != null) {
      where += ' AND chain_id = ?';
      whereArgs.add(chainId);
    }
    final rows = await db.query(
      'tokens',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'added_at ASC',
    );
    return rows.map(_rowToTokenInfo).toList();
  }

  /// Check if a token already exists for this wallet
  static Future<bool> tokenExists(String contractAddress, int walletSlot, {int chainId = 4289}) async {
    final db = await database;
    final result = await db.query(
      'tokens',
      columns: ['id'],
      where: 'contract_address = ? AND wallet_slot = ? AND chain_id = ?',
      whereArgs: [contractAddress.toLowerCase(), walletSlot, chainId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Remove a token for a wallet slot
  static Future<void> removeToken(String contractAddress, int walletSlot, {int chainId = 4289}) async {
    final db = await database;
    await db.delete(
      'tokens',
      where: 'contract_address = ? AND wallet_slot = ? AND chain_id = ?',
      whereArgs: [contractAddress.toLowerCase(), walletSlot, chainId],
    );
  }

  /// Delete all tokens for a wallet slot
  static Future<void> deleteTokensForSlot(int walletSlot) async {
    final db = await database;
    await db.delete('tokens', where: 'wallet_slot = ?', whereArgs: [walletSlot]);
  }

  // ================================================================
  // Price History CRUD
  // ================================================================

  /// Insert a price point
  static Future<void> insertPricePoint(double price, int timestamp) async {
    final db = await database;
    await db.insert('price_history', {
      'price': price,
      'timestamp': timestamp,
    });
  }

  /// Get price history since a given timestamp
  static Future<List<Map<String, dynamic>>> getPriceHistory(int sinceTimestamp) async {
    final db = await database;
    return db.query(
      'price_history',
      where: 'timestamp >= ?',
      whereArgs: [sinceTimestamp],
      orderBy: 'timestamp ASC',
    );
  }

  /// Get the last recorded price
  static Future<double?> getLastPrice() async {
    final db = await database;
    final rows = await db.query(
      'price_history',
      columns: ['price'],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['price'] as num).toDouble();
  }

  /// Get timestamp of last price entry
  static Future<int?> getLastPriceTimestamp() async {
    final db = await database;
    final rows = await db.query(
      'price_history',
      columns: ['timestamp'],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['timestamp'] as int;
  }

  /// Get total count of price entries
  static Future<int> getPriceCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM price_history');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clean up old price data (keep last N days)
  static Future<void> pruneOldPrices({int keepDays = 90}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch ~/ 1000;
    await db.delete('price_history', where: 'timestamp < ?', whereArgs: [cutoff]);
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

  static TokenInfo _rowToTokenInfo(Map<String, dynamic> row) {
    return TokenInfo(
      contractAddress: row['contract_address'] as String,
      name: row['name'] as String,
      symbol: row['symbol'] as String,
      decimals: row['decimals'] as int? ?? 18,
      walletSlot: row['wallet_slot'] as int,
      chainId: row['chain_id'] as int? ?? 4289,
      logoUrl: row['logo_url'] as String?,
      addedAt: DateTime.tryParse(row['added_at'] as String? ?? ''),
    );
  }

  /// Close database
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
