import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../presentation/models/chat_message.dart';
import '../../presentation/models/peer_model.dart';
import '../database/app_database.dart';

/// Service managing persistent storage of node identity, conversations,
/// and peer directories across app restarts, backed by an embedded SQLite database
/// with atomic transactions and zero-trace panic wipe.
class LocalStorageService {
  final Directory? _customDir;
  final bool _inMemoryOnly;
  final Map<String, String> _inMemoryStore = {};
  AppDatabase? _database;

  LocalStorageService({
    Directory? customDir,
    bool inMemoryOnly = false,
    AppDatabase? database,
  })  : _customDir = customDir,
        _inMemoryOnly = inMemoryOnly,
        _database = database;

  Future<AppDatabase> _getDb() async {
    if (_database != null && _database!.isInitialized) {
      return _database!;
    }

    if (_inMemoryOnly) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final memDb = await openDatabase(
        inMemoryDatabasePath,
        version: 2,
        onCreate: AppDatabase.onCreate,
        onUpgrade: AppDatabase.onUpgrade,
        onConfigure: AppDatabase.onConfigure,
      );
      _database = AppDatabase(db: memDb);
      return _database!;
    }

    if (_customDir != null) {
      if (!await _customDir!.exists()) {
        await _customDir!.create(recursive: true);
      }
      final dbPath = p.join(_customDir!.path, 'grid.db');
      final dbInstance = AppDatabase();
      await dbInstance.init(customPath: dbPath);
      _database = dbInstance;
      return _database!;
    }

    if (!AppDatabase.instance.isInitialized) {
      await AppDatabase.instance.init();
    }
    _database = AppDatabase.instance;
    return _database!;
  }

  // --- Identity ---

  Future<void> saveIdentity(Map<String, dynamic> json) async {
    _inMemoryStore['identity.json'] = jsonEncode(json);
    try {
      final db = await _getDb();
      await db.saveIdentity(json);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadIdentity() async {
    try {
      final db = await _getDb();
      final id = await db.loadIdentity();
      if (id != null) return id;
    } catch (_) {}

    if (_inMemoryStore.containsKey('identity.json')) {
      try {
        final raw = _inMemoryStore['identity.json']!;
        return jsonDecode(raw) as Map<String, dynamic>?;
      } catch (_) {}
    }
    return null;
  }

  Future<void> deleteIdentity() async {
    _inMemoryStore.remove('identity.json');
    try {
      final db = await _getDb();
      await db.deleteIdentity();
    } catch (_) {}
  }

  static const String identityFileName = 'identity.json';
  static const String conversationsFileName = 'conversations.json';
  static const String peersFileName = 'peers.json';

  // --- Timeline / Conversations ---

  Future<void> saveTimeline(Map<String, List<ChatMessage>> messagesByChannel) async {
    final serialized = <String, dynamic>{};
    for (final entry in messagesByChannel.entries) {
      serialized[entry.key] = entry.value.map((m) => m.toJson()).toList();
    }
    _inMemoryStore[conversationsFileName] = jsonEncode(serialized);
    try {
      final db = await _getDb();
      await db.saveTimeline(messagesByChannel);
    } catch (_) {}
  }

  Future<Map<String, List<ChatMessage>>?> loadTimeline() async {
    try {
      final db = await _getDb();
      final timeline = await db.loadTimeline();
      if (timeline.isNotEmpty) return timeline;
    } catch (_) {}

    if (_inMemoryStore.containsKey(conversationsFileName)) {
      try {
        final raw = _inMemoryStore[conversationsFileName]!;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final result = <String, List<ChatMessage>>{};
          for (final entry in decoded.entries) {
            if (entry.value is List) {
              result[entry.key] = (entry.value as List)
                  .whereType<Map<String, dynamic>>()
                  .map((m) => ChatMessage.fromJson(m))
                  .toList();
            }
          }
          return result;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> deleteTimeline() async {
    _inMemoryStore.remove(conversationsFileName);
    try {
      final db = await _getDb();
      await db.deleteTimeline();
    } catch (_) {}
  }

  // --- Peers Directory ---

  Future<void> savePeers(List<PeerModel> peers) async {
    final serialized = peers.map((p) => p.toJson()).toList();
    _inMemoryStore[peersFileName] = jsonEncode(serialized);
    try {
      final db = await _getDb();
      await db.savePeers(peers);
    } catch (_) {}
  }

  Future<List<PeerModel>?> loadPeers() async {
    try {
      final db = await _getDb();
      final peers = await db.loadPeers();
      if (peers.isNotEmpty) return peers;
    } catch (_) {}

    if (_inMemoryStore.containsKey(peersFileName)) {
      try {
        final raw = _inMemoryStore[peersFileName]!;
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((m) => PeerModel.fromJson(m))
              .toList();
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> deletePeers() async {
    _inMemoryStore.remove(peersFileName);
    try {
      final db = await _getDb();
      await db.deletePeers();
    } catch (_) {}
  }

  // --- Emergency Panic Wipe ---

  /// Overwrites and deletes all persisted records, wipes database pages with VACUUM.
  Future<void> wipeAll() async {
    _inMemoryStore.clear();
    try {
      final db = await _getDb();
      await db.wipeAll();
    } catch (_) {}

    if (_customDir != null && await _customDir!.exists()) {
      try {
        final filesToScrub = [
          File(p.join(_customDir!.path, identityFileName)),
          File(p.join(_customDir!.path, conversationsFileName)),
          File(p.join(_customDir!.path, peersFileName)),
        ];
        for (final f in filesToScrub) {
          if (await f.exists()) {
            try {
              final len = await f.length();
              if (len > 0) {
                await f.writeAsBytes(List<int>.filled(len, 0), flush: true);
              }
              await f.delete();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
  }
}

/// Global provider for local persistent storage service.
final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService();
});
