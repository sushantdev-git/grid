// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/infrastructure/codecs/announcement_codec.dart';
import 'package:grid/infrastructure/services/local_storage_service.dart';
import 'package:grid/presentation/models/peer_model.dart';
import 'package:grid/presentation/state/identity_state.dart';
import 'package:grid/presentation/utils/chat_command.dart';
import 'package:grid/domain/enums/transport_medium.dart';

/// Phase 10: Profile editing and phone-based peer search tests.
void main() {
  // ── Identity state: setNickname preserves phone ───────────────────────────
  group('IdentityNotifier.setNickname', () {
    late IdentityNotifier notifier;

    setUp(() {
      final storage = LocalStorageService(inMemoryOnly: true);
      notifier = IdentityNotifier(null, storage);
    });

    test('setNickname updates state nickname', () async {
      await notifier.initialize(nickname: 'alice');
      expect(notifier.state.nickname, 'alice');

      notifier.setNickname('bob');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.state.nickname, 'bob');
    });

    test('setNickname ignores empty or identical nickname', () async {
      await notifier.initialize(nickname: 'alice');
      notifier.setNickname('');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.nickname, 'alice');

      notifier.setNickname('alice');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.nickname, 'alice');
    });
  });

  // ── Identity state: setPhoneNumber ───────────────────────────────────────
  group('IdentityNotifier.setPhoneNumber', () {
    late IdentityNotifier notifier;

    setUp(() {
      final storage = LocalStorageService(inMemoryOnly: true);
      notifier = IdentityNotifier(null, storage);
    });

    test('setPhoneNumber stores phone number', () async {
      await notifier.initialize(nickname: 'alice');
      notifier.setPhoneNumber('+91 98765 43210');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.state.phoneNumber, '+91 98765 43210');
    });

    test('setPhoneNumber(null) clears phone number', () async {
      await notifier.initialize(nickname: 'alice');
      notifier.setPhoneNumber('+91 98765 43210');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      notifier.setPhoneNumber(null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.state.phoneNumber, isNull);
    });

    test('setPhoneNumber with empty string clears phone number', () async {
      await notifier.initialize(nickname: 'alice');
      notifier.setPhoneNumber('+91 98765 43210');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      notifier.setPhoneNumber('');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.state.phoneNumber, isNull);
    });

    test('phone number persists across re-initialize', () async {
      final storage = LocalStorageService(inMemoryOnly: true);
      final n1 = IdentityNotifier(null, storage);
      await n1.initialize(nickname: 'alice');
      n1.setPhoneNumber('+91 98765 43210');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // New notifier with same storage
      final n2 = IdentityNotifier(null, storage);
      await n2.initialize();
      expect(n2.state.nickname, 'alice');
      expect(n2.state.phoneNumber, '+91 98765 43210');
    });

    test('setNickname preserves existing phone number', () async {
      await notifier.initialize(nickname: 'alice');
      notifier.setPhoneNumber('+91 98765 43210');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      notifier.setNickname('bob');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.state.nickname, 'bob');
      expect(notifier.state.phoneNumber, '+91 98765 43210');
    });
  });

  // ── PeerModel.matchesPhoneCommitment ──────────────────────────────────────
  group('PeerModel.matchesPhoneCommitment', () {
    final aliceHash = AnnouncementCodec.computePhoneCommitment('+91 98765 43210')
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    PeerModel makePeer(String? hash) => PeerModel(
          peerId: 'abcd1234',
          nickname: 'alice',
          phoneHash: hash,
          lastSeen: DateTime.now(),
        );

    test('matches phone query regardless of formatting', () {
      final peer = makePeer(aliceHash);
      expect(peer.matchesPhoneCommitment('+91 98765-43210'), isTrue);
      expect(peer.matchesPhoneCommitment('919876543210'), isTrue);
    });

    test('returns false when phoneHash is null', () {
      final peer = makePeer(null);
      expect(peer.matchesPhoneCommitment('+91 98765 43210'), isFalse);
    });

    test('returns false on mismatched phone number', () {
      final peer = makePeer(aliceHash);
      expect(peer.matchesPhoneCommitment('+1 555 123 4567'), isFalse);
    });
  });

  // ── Peer search matching logic ─────────────────────────────────────────────
  group('Peer search matching', () {
    bool matches(PeerModel peer, String query) {
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      if (peer.nickname.toLowerCase().contains(q)) return true;
      if (peer.peerId.toLowerCase().startsWith(q)) return true;
      if (peer.matchesPhoneCommitment(query)) return true;
      return false;
    }

    final alicePhoneHash = AnnouncementCodec.computePhoneCommitment('+91 98765 43210')
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final alice = PeerModel(
      peerId: 'c0e64ded12345678',
      nickname: 'alice',
      phoneHash: alicePhoneHash,
      lastSeen: DateTime.now(),
      medium: TransportMedium.bleMesh,
    );

    final bob = PeerModel(
      peerId: 'deadbeef87654321',
      nickname: 'bob',
      phoneHash: null,
      lastSeen: DateTime.now(),
      medium: TransportMedium.bleMesh,
    );

    test('empty query matches everything', () {
      expect(matches(alice, ''), isTrue);
      expect(matches(bob, ''), isTrue);
    });

    test('matches by nickname (case-insensitive)', () {
      expect(matches(alice, 'alic'), isTrue);
      expect(matches(alice, 'ALICE'), isTrue);
      expect(matches(bob, 'alic'), isFalse);
    });

    test('matches by peer ID prefix', () {
      expect(matches(alice, 'c0e6'), isTrue);
      expect(matches(bob, 'c0e6'), isFalse);
      expect(matches(bob, 'dead'), isTrue);
    });

    test('matches by privacy-preserving phone commitment tag', () {
      expect(matches(alice, '+91 98765 43210'), isTrue);
      expect(matches(alice, '919876543210'), isTrue);
      expect(matches(bob, '+91 98765 43210'), isFalse);
    });

    test('no match on wrong data', () {
      expect(matches(alice, 'xyz'), isFalse);
      expect(matches(bob, '99999'), isFalse);
    });
  });

  // ── /nick command parsing ──────────────────────────────────────────────────
  group('/nick command', () {
    test('parses name correctly', () {
      final cmd = ChatCommand.parse('/nick alice_dev');
      expect(cmd.type, ChatCommandType.nick);
      expect(cmd.argument, 'alice_dev');
      expect(cmd.errorMessage, isNull);
    });

    test('returns error when name missing', () {
      final cmd = ChatCommand.parse('/nick');
      expect(cmd.type, ChatCommandType.nick);
      expect(cmd.errorMessage, isNotNull);
    });

    test('handles multi-word nickname', () {
      final cmd = ChatCommand.parse('/nick alice bob');
      expect(cmd.type, ChatCommandType.nick);
      expect(cmd.argument, 'alice bob');
    });
  });

  // ── /phone command parsing ─────────────────────────────────────────────────
  group('/phone command', () {
    test('parses phone number correctly', () {
      final cmd = ChatCommand.parse('/phone +91 98765 43210');
      expect(cmd.type, ChatCommandType.phone);
      expect(cmd.argument, '+91 98765 43210');
      expect(cmd.errorMessage, isNull);
    });

    test('/phone clear sets argument to empty string', () {
      final cmd = ChatCommand.parse('/phone clear');
      expect(cmd.type, ChatCommandType.phone);
      expect(cmd.argument, '');
      expect(cmd.errorMessage, isNull);
    });

    test('returns error when number missing', () {
      final cmd = ChatCommand.parse('/phone');
      expect(cmd.type, ChatCommandType.phone);
      expect(cmd.errorMessage, isNotNull);
    });
  });

  // ── PeerModel phoneHash serialization round-trip ──────────────────────────
  group('PeerModel phoneHash serialization', () {
    test('PeerModel serializes and restores phoneHash', () {
      final peer = PeerModel(
        peerId: 'abcd1234efgh5678',
        nickname: 'alice',
        phoneHash: 'a1b2c3d4e5f60718',
        lastSeen: DateTime.fromMillisecondsSinceEpoch(1000000),
        medium: TransportMedium.bleMesh,
      );
      final json = peer.toJson();
      final restored = PeerModel.fromJson(json);
      expect(restored.phoneHash, 'a1b2c3d4e5f60718');
    });

    test('PeerModel round-trip without phoneHash stays null', () {
      final peer = PeerModel(
        peerId: 'abcd1234',
        nickname: 'bob',
        lastSeen: DateTime.fromMillisecondsSinceEpoch(1000000),
        medium: TransportMedium.bleMesh,
      );
      final json = peer.toJson();
      final restored = PeerModel.fromJson(json);
      expect(restored.phoneHash, isNull);
    });
  });
}
