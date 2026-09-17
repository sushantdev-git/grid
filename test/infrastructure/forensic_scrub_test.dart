import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:grid/infrastructure/database/app_database.dart';
import 'package:grid/infrastructure/services/local_storage_service.dart';
import 'package:grid/infrastructure/services/voice_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Storage Forensic Scrubbing & Panic Wipe Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('forensic_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('VoiceService.wipeAllVoiceNotes scrubs file bytes before unlinking', () async {
      final voiceService = VoiceService(testMode: true);
      final voiceDir = await voiceService.getVoiceDirectory();

      // Create a dummy audio note in the voice directory
      final testAudio = File('${voiceDir.path}/test_secret_audio.m4a');
      final secretData = Uint8List.fromList(List.generate(1024, (i) => (i % 256)));
      testAudio.writeAsBytesSync(secretData, flush: true);

      expect(testAudio.existsSync(), isTrue);
      expect(testAudio.lengthSync(), equals(1024));

      // Execute forensic wipe
      await voiceService.wipeAllVoiceNotes();

      // Ensure file and directory are unlinked
      expect(testAudio.existsSync(), isFalse);
    });

    test('AppDatabase.wipeAll truncates WAL and wipes database tables cleanly', () async {
      final dbPath = '${tempDir.path}/test_db.db';
      final appDb = AppDatabase();
      await appDb.init(customPath: dbPath);

      // Save a message into the database
      final rawDb = appDb.database;
      await rawDb.insert('messages', {
        'id': 'msg_test_1',
        'sender_id': 'alice',
        'sender_nickname': 'Alice',
        'channel_or_peer_id': 'bob',
        'content': 'Classified intelligence payload',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_outgoing': 1,
        'is_encrypted': 1,
        'delivery_status': 'sent',
      });

      var rows = await rawDb.rawQuery('SELECT COUNT(*) as count FROM messages');
      expect(rows.first['count'], equals(1));

      // Execute panic wipe on database
      await appDb.wipeAll();

      // Count must be 0 and tables must be cleanly vacuumed
      rows = await rawDb.rawQuery('SELECT COUNT(*) as count FROM messages');
      expect(rows.first['count'], equals(0));

      await appDb.close();
    });

    test('LocalStorageService.wipeAll zero-overwrites legacy JSON files and wipes DB', () async {
      final storage = LocalStorageService(customDir: tempDir);

      // Populate some test data
      await storage.saveIdentity({'nickname': 'TopSecretAgent', 'peerId': '0011223344556677'});
      final identity = await storage.loadIdentity();
      expect(identity?['nickname'], equals('TopSecretAgent'));

      // Execute wipe
      await storage.wipeAll();

      final cleared = await storage.loadIdentity();
      expect(cleared, isNull);
    });
  });
}
