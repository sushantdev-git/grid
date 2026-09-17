import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/infrastructure/codecs/announcement_codec.dart';
import 'package:grid/presentation/models/peer_model.dart';

void main() {
  group('Privacy-Preserving Phone Commitment Tests (Solution 1)', () {
    test('computePhoneCommitment produces consistent 8-byte commitment tag', () {
      const phone1 = '+1 (555) 234-5678';
      const phone2 = '15552345678';
      const phone3 = '1-555-234-5678';

      final hash1 = AnnouncementCodec.computePhoneCommitment(phone1);
      final hash2 = AnnouncementCodec.computePhoneCommitment(phone2);
      final hash3 = AnnouncementCodec.computePhoneCommitment(phone3);

      expect(hash1.length, equals(8));
      expect(hash1, equals(hash2));
      expect(hash1, equals(hash3));

      // Verify domain separation string
      final expectedSha = crypto.sha256.convert(utf8.encode('grid-phone-v1:15552345678')).bytes.sublist(0, 8);
      expect(hash1, equals(Uint8List.fromList(expectedSha)));
    });

    test('different phone numbers produce distinct 8-byte commitment tags', () {
      final hashA = AnnouncementCodec.computePhoneCommitment('+1 555 111 2222');
      final hashB = AnnouncementCodec.computePhoneCommitment('+1 555 111 3333');

      expect(hashA, isNot(equals(hashB)));
    });

    test('AnnouncementCodec never serializes cleartext phone strings into wire payload', () {
      final commitment = AnnouncementCodec.computePhoneCommitment('+1 (555) 987-6543');
      final payload = AnnouncementPayload(
        nickname: 'Alice',
        noisePublicKey: Uint8List(32),
        signingPublicKey: Uint8List(32),
        phoneHash: commitment,
        phoneNumber: '+1 (555) 987-6543', // Local memory representation
      );

      final encoded = AnnouncementCodec.encode(payload);
      expect(encoded, isNotNull);

      // Verify that raw phone string digits are NOT present in cleartext anywhere in the encoded wire bytes
      final wireString = String.fromCharCodes(encoded!);
      expect(wireString.contains('+1 (555) 987-6543'), isFalse);
      expect(wireString.contains('9876543'), isFalse);

      // Verify decoding extracts phoneHash correctly
      final decoded = AnnouncementCodec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.phoneHash, equals(commitment));
    });

    test('PeerModel matches search query via phone commitment hash', () {
      final commitment = AnnouncementCodec.computePhoneCommitment('+1 415 555 2671');
      final commitmentHex = commitment.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final peer = PeerModel(
        peerId: 'peer_abc123',
        nickname: 'Bob',
        phoneHash: commitmentHex,
        lastSeen: DateTime.now(),
        medium: TransportMedium.bleMesh,
      );

      // Positive matches with various phone formats
      expect(peer.matchesPhoneCommitment('14155552671'), isTrue);
      expect(peer.matchesPhoneCommitment('+1 (415) 555-2671'), isTrue);
      expect(peer.matchesPhoneCommitment('1-415-555-2671'), isTrue);

      // Negative matches
      expect(peer.matchesPhoneCommitment('14155552672'), isFalse);
      expect(peer.matchesPhoneCommitment('12345'), isFalse);
      expect(peer.matchesPhoneCommitment(''), isFalse);
    });
  });
}
