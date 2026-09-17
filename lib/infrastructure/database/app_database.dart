import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/enums/transport_medium.dart';
import '../../presentation/models/chat_message.dart';
import '../../presentation/models/peer_model.dart';

/// Central embedded SQLite database service providing transactional persistence
/// for user cryptographic identity, chat messages, discovered peers, and joined channels.
class AppDatabase {
  Database? _db;
  bool _isInitialized = false;

  AppDatabase({Database? db})
      : _db = db,
        _isInitialized = db != null && db.isOpen;

  static final AppDatabase instance = AppDatabase();

  bool get isInitialized => _isInitialized && _db != null && _db!.isOpen;

  Database get database {
    if (_db == null || !_db!.isOpen) {
      throw StateError('AppDatabase is not initialized. Call init() first.');
    }
    return _db!;
  }

  /// Initializes the SQLite database engine and opens the database.
  /// Safe to call multiple times (idempotent).
  Future<void> init({String? customPath, Database? inMemoryDb}) async {
    if (_isInitialized && _db != null && _db!.isOpen) {
      return;
    }

    if (inMemoryDb != null) {
      _db = inMemoryDb;
      _isInitialized = true;
      return;
    }

    // Configure FFI database factory for desktop and headless unit test runners
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST'))) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String dbPath;
    if (customPath != null) {
      dbPath = customPath;
    } else {
      String basePath;
      try {
        final dir = await getApplicationDocumentsDirectory();
        basePath = p.join(dir.path, 'grid');
      } catch (_) {
        try {
          basePath = await getDatabasesPath();
        } catch (_) {
          basePath = Directory.systemTemp.path;
        }
      }

      final dir = Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      dbPath = p.join(basePath, 'grid.db');
    }

    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onConfigure: onConfigure,
    );

    _isInitialized = true;

    // Run one-time migration from legacy flat JSON files if they exist
    await _migrateLegacyJsonFiles();
  }

  static Future<void> onConfigure(Database db) async {
    // Enable WAL (Write-Ahead Logging) for superior concurrent read/write throughput
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL;');
    } catch (_) {}
    try {
      await db.rawQuery('PRAGMA synchronous = NORMAL;');
    } catch (_) {}
    // Enable secure_delete so SQLite overwrites deleted cells and pages with zeros
    try {
      await db.rawQuery('PRAGMA secure_delete = ON;');
    } catch (_) {}
  }

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN media_path TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE messages ADD COLUMN media_duration_ms INTEGER;');
      } catch (_) {}
    }
  }

  static Future<void> onCreate(Database db, int version) async {
    final batch = db.batch();

    // 1. Identity table (single row for local user node)
    batch.execute('''
      CREATE TABLE identity (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        nickname TEXT NOT NULL,
        phone_number TEXT,
        noise_private_key BLOB NOT NULL,
        signing_private_key BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // 2. Chat messages table (indexed by channel/peer and timestamp)
    batch.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        channel_or_peer_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        sender_nickname TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_outgoing INTEGER NOT NULL,
        is_encrypted INTEGER NOT NULL DEFAULT 0,
        medium TEXT NOT NULL DEFAULT 'bleMesh',
        is_system INTEGER NOT NULL DEFAULT 0,
        delivery_status TEXT NOT NULL DEFAULT 'sent',
        media_path TEXT,
        media_duration_ms INTEGER
      );
    ''');
    batch.execute('''
      CREATE INDEX idx_messages_channel_time ON messages(channel_or_peer_id, timestamp);
    ''');

    // 3. Discovered peers directory
    batch.execute('''
      CREATE TABLE peers (
        peer_id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        phone_number TEXT,
        noise_public_key TEXT NOT NULL,
        signing_public_key TEXT NOT NULL,
        rssi INTEGER,
        hops INTEGER NOT NULL DEFAULT 0,
        last_seen INTEGER NOT NULL,
        is_direct_neighbor INTEGER NOT NULL DEFAULT 1,
        is_verified INTEGER NOT NULL DEFAULT 0,
        medium TEXT NOT NULL,
        safety_number TEXT
      );
    ''');

    // 4. Joined channels table
    batch.execute('''
      CREATE TABLE channels (
        name TEXT PRIMARY KEY,
        joined_at INTEGER NOT NULL
      );
    ''');

    await batch.commit(noResult: true);
  }

  // --- Identity CRUD ---

  Future<void> saveIdentity(Map<String, dynamic> json) async {
    final db = database;
    final nickname = json['nickname'] as String? ?? 'anon_node';
    final phoneNumber = json['phoneNumber'] as String?;
    final noisePriv = _extractBytes(json['noisePrivateKey']);
    final signingPriv = _extractBytes(json['signingPrivateKey']);
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.rawInsert('''
      INSERT INTO identity (id, nickname, phone_number, noise_private_key, signing_private_key, created_at, updated_at)
      VALUES (1, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        nickname = excluded.nickname,
        phone_number = excluded.phone_number,
        noise_private_key = excluded.noise_private_key,
        signing_private_key = excluded.signing_private_key,
        updated_at = excluded.updated_at;
    ''', [
      nickname,
      phoneNumber,
      noisePriv,
      signingPriv,
      now,
      now,
    ]);
  }

  Future<Map<String, dynamic>?> loadIdentity() async {
    final db = database;
    final rows = await db.query(
      'identity',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    final noiseBytes = row['noise_private_key'] as List<int>;
    final signingBytes = row['signing_private_key'] as List<int>;

    return {
      'version': 1,
      'nickname': row['nickname'] as String,
      'phoneNumber': row['phone_number'] as String?,
      'noisePrivateKey': noiseBytes,
      'signingPrivateKey': signingBytes,
    };
  }

  Future<void> deleteIdentity() async {
    final db = database;
    await db.delete('identity', where: 'id = ?', whereArgs: [1]);
  }

  // --- Messages / Timeline CRUD ---

  Future<void> saveMessage(ChatMessage message) async {
    final db = database;
    await db.insert(
      'messages',
      {
        'id': message.id,
        'channel_or_peer_id': message.channelOrPeerId,
        'sender_id': message.senderId,
        'sender_nickname': message.senderNickname,
        'content': message.content,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'is_outgoing': message.isOutgoing ? 1 : 0,
        'is_encrypted': message.isEncrypted ? 1 : 0,
        'medium': message.medium.name,
        'is_system': message.isSystem ? 1 : 0,
        'delivery_status': message.deliveryStatus.name,
        'media_path': message.mediaPath,
        'media_duration_ms': message.mediaDurationMs,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveTimeline(Map<String, List<ChatMessage>> messagesByChannel) async {
    final db = database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in messagesByChannel.entries) {
        for (final msg in entry.value) {
          batch.insert(
            'messages',
            {
              'id': msg.id,
              'channel_or_peer_id': entry.key,
              'sender_id': msg.senderId,
              'sender_nickname': msg.senderNickname,
              'content': msg.content,
              'timestamp': msg.timestamp.millisecondsSinceEpoch,
              'is_outgoing': msg.isOutgoing ? 1 : 0,
              'is_encrypted': msg.isEncrypted ? 1 : 0,
              'medium': msg.medium.name,
              'is_system': msg.isSystem ? 1 : 0,
              'delivery_status': msg.deliveryStatus.name,
              'media_path': msg.mediaPath,
              'media_duration_ms': msg.mediaDurationMs,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, List<ChatMessage>>> loadTimeline() async {
    final db = database;
    final rows = await db.query(
      'messages',
      orderBy: 'timestamp ASC',
    );

    final result = <String, List<ChatMessage>>{};
    for (final row in rows) {
      final channelOrPeerId = row['channel_or_peer_id'] as String;
      final mediumStr = row['medium'] as String? ?? 'bleMesh';
      final medium = TransportMedium.values.firstWhere(
        (m) => m.name == mediumStr,
        orElse: () => TransportMedium.bleMesh,
      );
      final statusStr = row['delivery_status'] as String? ?? 'sent';
      final status = MessageDeliveryStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => MessageDeliveryStatus.sent,
      );

      final msg = ChatMessage(
        id: row['id'] as String,
        senderId: row['sender_id'] as String,
        senderNickname: row['sender_nickname'] as String,
        content: row['content'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        isOutgoing: (row['is_outgoing'] as int) == 1,
        isEncrypted: (row['is_encrypted'] as int? ?? 0) == 1,
        medium: medium,
        channelOrPeerId: channelOrPeerId,
        isSystem: (row['is_system'] as int? ?? 0) == 1,
        deliveryStatus: status,
        mediaPath: row['media_path'] as String?,
        mediaDurationMs: row['media_duration_ms'] as int?,
      );
      result.putIfAbsent(channelOrPeerId, () => []).add(msg);
    }
    return result;
  }

  Future<void> deleteTimeline() async {
    final db = database;
    await db.delete('messages');
  }

  // --- Peers Directory CRUD ---

  Future<void> savePeers(List<PeerModel> peers) async {
    final db = database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final peer in peers) {
        batch.insert(
          'peers',
          {
            'peer_id': peer.peerId,
            'nickname': peer.nickname,
            'phone_number': peer.phoneHash,
            'noise_public_key': peer.noisePublicKey,
            'signing_public_key': peer.signingPublicKey,
            'rssi': peer.rssi,
            'hops': peer.hops,
            'last_seen': peer.lastSeen.millisecondsSinceEpoch,
            'is_direct_neighbor': peer.isDirectNeighbor ? 1 : 0,
            'is_verified': peer.isVerified ? 1 : 0,
            'medium': peer.medium.name,
            'safety_number': peer.safetyNumber,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<PeerModel>> loadPeers() async {
    final db = database;
    final rows = await db.query(
      'peers',
      orderBy: 'last_seen DESC',
    );

    final result = <PeerModel>[];
    for (final row in rows) {
      final mediumStr = row['medium'] as String? ?? 'bleMesh';
      final medium = TransportMedium.values.firstWhere(
        (m) => m.name == mediumStr,
        orElse: () => TransportMedium.bleMesh,
      );

      result.add(PeerModel(
        peerId: row['peer_id'] as String,
        nickname: row['nickname'] as String,
        phoneHash: row['phone_number'] as String?,
        noisePublicKey: row['noise_public_key'] as String,
        signingPublicKey: row['signing_public_key'] as String,
        rssi: row['rssi'] as int?,
        hops: row['hops'] as int? ?? 0,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(row['last_seen'] as int),
        isDirectNeighbor: (row['is_direct_neighbor'] as int) == 1,
        isVerified: (row['is_verified'] as int) == 1,
        medium: medium,
        safetyNumber: row['safety_number'] as String?,
      ));
    }
    return result;
  }

  Future<void> deletePeers() async {
    final db = database;
    await db.delete('peers');
  }

  // --- Channels CRUD ---

  Future<void> saveChannels(List<String> channels) async {
    final db = database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final ch in channels) {
        batch.insert(
          'channels',
          {'name': ch, 'joined_at': DateTime.now().millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<String>> loadChannels() async {
    final db = database;
    final rows = await db.query('channels', orderBy: 'joined_at ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> deleteChannels() async {
    final db = database;
    await db.delete('channels');
  }

  // --- Emergency Panic Wipe ---

  /// Zeroizes all tables forensically, wipes database pages with VACUUM.
  Future<void> wipeAll() async {
    final db = database;
    await db.transaction((txn) async {
      await txn.delete('identity');
      await txn.delete('messages');
      await txn.delete('peers');
      await txn.delete('channels');
    });
    // Truncate and purge write-ahead logs to eliminate residual plaintext in grid.db-wal
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}
    try {
      await db.rawQuery('VACUUM;');
    } catch (_) {}
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _isInitialized = false;
    }
  }

  // --- Helper & Legacy Migration ---

  static Uint8List _extractBytes(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    if (value is String) {
      if (value.length % 2 == 0 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
        final bytes = <int>[];
        for (int i = 0; i < value.length; i += 2) {
          bytes.add(int.parse(value.substring(i, i + 2), radix: 16));
        }
        return Uint8List.fromList(bytes);
      }
    }
    throw ArgumentError('Invalid byte representation for database: $value');
  }

  Future<void> _migrateLegacyJsonFiles() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dirsToCheck = [
        Directory(p.join(docDir.path, 'grid')),
        Directory(p.join(docDir.path, 'dec_chat')),
      ];

      for (final dir in dirsToCheck) {
        if (!await dir.exists()) continue;

        // 1. Check legacy identity.json
        final idFile = File(p.join(dir.path, 'identity.json'));
        if (await idFile.exists()) {
          try {
            final raw = await idFile.readAsString();
            final json = jsonDecode(raw);
            if (json is Map<String, dynamic> && await loadIdentity() == null) {
              await saveIdentity(json);
            }
            await idFile.delete();
          } catch (_) {}
        }

        // 2. Check legacy peers.json
        final peersFile = File(p.join(dir.path, 'peers.json'));
        if (await peersFile.exists()) {
          try {
            final raw = await peersFile.readAsString();
            final list = jsonDecode(raw);
            if (list is List) {
              final peers = list
                  .whereType<Map<String, dynamic>>()
                  .map((m) => PeerModel.fromJson(m))
                  .toList();
              if (peers.isNotEmpty) {
                await savePeers(peers);
              }
            }
            await peersFile.delete();
          } catch (_) {}
        }

        // 3. Check legacy conversations.json
        final convFile = File(p.join(dir.path, 'conversations.json'));
        if (await convFile.exists()) {
          try {
            final raw = await convFile.readAsString();
            final map = jsonDecode(raw);
            if (map is Map<String, dynamic>) {
              final timeline = <String, List<ChatMessage>>{};
              for (final entry in map.entries) {
                if (entry.value is List) {
                  timeline[entry.key] = (entry.value as List)
                      .whereType<Map<String, dynamic>>()
                      .map((m) => ChatMessage.fromJson(m))
                      .toList();
                }
              }
              if (timeline.isNotEmpty) {
                await saveTimeline(timeline);
              }
            }
            await convFile.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // Best-effort migration, ignore errors in non-standard test environments
    }
  }
}
