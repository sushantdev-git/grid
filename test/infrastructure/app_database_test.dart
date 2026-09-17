import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/infrastructure/database/app_database.dart';
import 'package:grid/presentation/models/chat_message.dart';
import 'package:grid/presentation/models/peer_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppDatabase SQLite Engine', () {
    late Directory tempDir;
    late String dbPath;
    late AppDatabase db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('app_db_test_');
      dbPath = p.join(tempDir.path, 'test_grid.db');
      db = AppDatabase();
      await db.init(customPath: dbPath);
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists, updates, and loads identity with nickname and phone', () async {
      expect(await db.loadIdentity(), isNull);

      final identity1 = {
        'version': 1,
        'nickname': 'Alice',
        'phoneNumber': '+1234567890',
        'noisePrivateKey': List.generate(32, (i) => i),
        'signingPrivateKey': List.generate(32, (i) => 31 - i),
      };

      await db.saveIdentity(identity1);

      final loaded1 = await db.loadIdentity();
      expect(loaded1, isNotNull);
      expect(loaded1!['nickname'], 'Alice');
      expect(loaded1['phoneNumber'], '+1234567890');
      expect(loaded1['noisePrivateKey'], orderedEquals(List.generate(32, (i) => i)));
      expect(loaded1['signingPrivateKey'], orderedEquals(List.generate(32, (i) => 31 - i)));

      // Update nickname & phone
      final identity2 = {
        'version': 1,
        'nickname': 'AliceUpdated',
        'phoneNumber': '+9876543210',
        'noisePrivateKey': List.generate(32, (i) => i),
        'signingPrivateKey': List.generate(32, (i) => 31 - i),
      };

      await db.saveIdentity(identity2);

      final loaded2 = await db.loadIdentity();
      expect(loaded2, isNotNull);
      expect(loaded2!['nickname'], 'AliceUpdated');
      expect(loaded2['phoneNumber'], '+9876543210');

      // Clear phone
      final identity3 = {
        'version': 1,
        'nickname': 'AliceUpdated',
        'phoneNumber': null,
        'noisePrivateKey': List.generate(32, (i) => i),
        'signingPrivateKey': List.generate(32, (i) => 31 - i),
      };

      await db.saveIdentity(identity3);

      final loaded3 = await db.loadIdentity();
      expect(loaded3, isNotNull);
      expect(loaded3!['phoneNumber'], isNull);

      await db.deleteIdentity();
      expect(await db.loadIdentity(), isNull);
    });

    test('retains identity across database close and reopen (cold restart simulation)', () async {
      final identity = {
        'version': 1,
        'nickname': 'PersistentNode',
        'phoneNumber': '+1122334455',
        'noisePrivateKey': List.generate(32, (i) => 42),
        'signingPrivateKey': List.generate(32, (i) => 84),
      };

      await db.saveIdentity(identity);
      await db.close();

      // Simulate new app launch opening the same dbPath
      final reopenedDb = AppDatabase();
      await reopenedDb.init(customPath: dbPath);

      final restored = await reopenedDb.loadIdentity();
      expect(restored, isNotNull);
      expect(restored!['nickname'], 'PersistentNode');
      expect(restored['phoneNumber'], '+1122334455');
      expect(restored['noisePrivateKey'], orderedEquals(List.generate(32, (i) => 42)));

      await reopenedDb.close();
    });

    test('persists, loads, and deletes chat messages and timelines', () async {
      final now = DateTime.now();
      final msg1 = ChatMessage(
        id: 'msg_1',
        senderId: 'peer_1',
        senderNickname: 'Alice',
        content: 'Hello Mesh',
        timestamp: now.subtract(const Duration(seconds: 10)),
        isOutgoing: false,
        channelOrPeerId: '#general',
      );

      final msg2 = ChatMessage(
        id: 'msg_2',
        senderId: 'peer_me',
        senderNickname: 'Me',
        content: 'Hey Alice!',
        timestamp: now,
        isOutgoing: true,
        channelOrPeerId: '#general',
      );

      final msg3 = ChatMessage(
        id: 'msg_3',
        senderId: 'peer_direct',
        senderNickname: 'Bob',
        content: 'Direct message',
        timestamp: now,
        isOutgoing: false,
        channelOrPeerId: 'peer_direct',
      );

      await db.saveTimeline({
        '#general': [msg1, msg2],
        'peer_direct': [msg3],
      });

      final loaded = await db.loadTimeline();
      expect(loaded.containsKey('#general'), isTrue);
      expect(loaded['#general']!.length, 2);
      expect(loaded['#general']!.first.content, 'Hello Mesh');
      expect(loaded['#general']!.last.content, 'Hey Alice!');

      expect(loaded.containsKey('peer_direct'), isTrue);
      expect(loaded['peer_direct']!.length, 1);
      expect(loaded['peer_direct']!.first.content, 'Direct message');

      await db.deleteTimeline();
      final afterDelete = await db.loadTimeline();
      expect(afterDelete.isEmpty, isTrue);
    });

    test('persists and loads discovered peers directory', () async {
      final peer = PeerModel(
        peerId: 'a1b2c3d4e5f60718',
        nickname: 'NeighborNode',
        phoneHash: 'a1b2c3d4e5f60718',
        noisePublicKey: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        signingPublicKey: 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
        rssi: -58,
        hops: 1,
        lastSeen: DateTime.now(),
        isDirectNeighbor: true,
        isVerified: true,
        medium: TransportMedium.bleMesh,
        safetyNumber: '12345 67890',
      );

      await db.savePeers([peer]);

      final peers = await db.loadPeers();
      expect(peers.length, 1);
      expect(peers.first.peerId, 'a1b2c3d4e5f60718');
      expect(peers.first.nickname, 'NeighborNode');
      expect(peers.first.phoneHash, 'a1b2c3d4e5f60718');
      expect(peers.first.isVerified, isTrue);
      expect(peers.first.safetyNumber, '12345 67890');
    });

    test('panic wipe forensically purges all tables and vacuums', () async {
      // Seed data into all tables
      await db.saveIdentity({
        'version': 1,
        'nickname': 'Target',
        'noisePrivateKey': List.generate(32, (i) => i),
        'signingPrivateKey': List.generate(32, (i) => i),
      });
      await db.saveMessage(ChatMessage(
        id: 'msg_w',
        senderId: 's',
        senderNickname: 'n',
        content: 'Secret',
        timestamp: DateTime.now(),
        isOutgoing: true,
        channelOrPeerId: '#mesh',
      ));
      await db.savePeers([
        PeerModel(
          peerId: 'p1',
          nickname: 'p1',
          noisePublicKey: 'npk',
          signingPublicKey: 'spk',
          lastSeen: DateTime.now(),
        ),
      ]);
      await db.saveChannels(['#secret_channel']);

      // Execute panic wipe
      await db.wipeAll();

      expect(await db.loadIdentity(), isNull);
      expect((await db.loadTimeline()).isEmpty, isTrue);
      expect((await db.loadPeers()).isEmpty, isTrue);
      expect((await db.loadChannels()).isEmpty, isTrue);
    });
  });
}
