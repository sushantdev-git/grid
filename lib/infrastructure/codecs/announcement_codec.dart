import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart' as crypto;
import '../../core/utils/binary_reader.dart';
import '../../core/utils/binary_writer.dart';

/// Decoded representation of a BitChat peer presence announcement packet.
class AnnouncementPayload {
  final String nickname;
  final Uint8List noisePublicKey;
  final Uint8List signingPublicKey;
  final List<Uint8List>? directNeighbors;
  final int? capabilities;
  final String? bridgeGeohash;
  /// Privacy-preserving 8-byte commitment tag: SHA-256("grid-phone-v1:" + phoneDigits)[0..8]
  final Uint8List? phoneHash;
  /// Optional local phone number (never serialized raw to wire).
  final String? phoneNumber;

  const AnnouncementPayload({
    required this.nickname,
    required this.noisePublicKey,
    required this.signingPublicKey,
    this.directNeighbors,
    this.capabilities,
    this.bridgeGeohash,
    this.phoneHash,
    this.phoneNumber,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final eq = const ListEquality().equals;
    return other is AnnouncementPayload &&
        other.nickname == nickname &&
        eq(other.noisePublicKey, noisePublicKey) &&
        eq(other.signingPublicKey, signingPublicKey) &&
        other.capabilities == capabilities &&
        other.bridgeGeohash == bridgeGeohash &&
        eq(other.phoneHash, phoneHash) &&
        other.phoneNumber == phoneNumber;
  }

  @override
  int get hashCode => Object.hash(
        nickname,
        const ListEquality().hash(noisePublicKey),
        const ListEquality().hash(signingPublicKey),
        capabilities,
        bridgeGeohash,
        const ListEquality().hash(phoneHash),
        phoneNumber,
      );
}

/// TLV encoder and decoder for BitChat peer presence announcements.
/// Forward-compatible: safely ignores unknown future TLV tags without crashing.
class AnnouncementCodec {
  static const int tlvNickname = 0x01;
  static const int tlvNoisePublicKey = 0x02;
  static const int tlvSigningPublicKey = 0x03;
  static const int tlvDirectNeighbors = 0x04;
  static const int tlvCapabilities = 0x05;
  static const int tlvBridgeGeohash = 0x06;
  // Phase 10: privacy-preserving phone commitment tag (8 bytes)
  static const int tlvPhoneNumber = 0x07;

  /// Computes an irreversible 8-byte cryptographic commitment for privacy-preserving discovery:
  /// `SHA-256("grid-phone-v1:" + digits)[0..8]`.
  static Uint8List computePhoneCommitment(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    final input = utf8.encode('grid-phone-v1:$digits');
    final digest = crypto.sha256.convert(input).bytes;
    return Uint8List.fromList(digest.sublist(0, 8));
  }

  /// Encodes an [AnnouncementPayload] into binary TLV format.
  static Uint8List? encode(AnnouncementPayload announcement) {
    final writer = BinaryWriter(initialCapacity: 128);

    // 1. Nickname TLV
    final nickBytes = utf8.encode(announcement.nickname);
    if (nickBytes.length > 255) return null;
    writer.writeUint8(tlvNickname);
    writer.writeUint8(nickBytes.length);
    writer.writeBytes(nickBytes);

    // 2. Noise Public Key TLV (Curve25519)
    if (announcement.noisePublicKey.length > 255) return null;
    writer.writeUint8(tlvNoisePublicKey);
    writer.writeUint8(announcement.noisePublicKey.length);
    writer.writeBytes(announcement.noisePublicKey);

    // 3. Signing Public Key TLV (Ed25519)
    if (announcement.signingPublicKey.length > 255) return null;
    writer.writeUint8(tlvSigningPublicKey);
    writer.writeUint8(announcement.signingPublicKey.length);
    writer.writeBytes(announcement.signingPublicKey);

    // 4. Direct Neighbors TLV (Optional, sequence of 8-byte IDs)
    if (announcement.directNeighbors != null && announcement.directNeighbors!.isNotEmpty) {
      final neighbors = announcement.directNeighbors!;
      final totalBytes = neighbors.length * 8;
      if (totalBytes <= 255) {
        writer.writeUint8(tlvDirectNeighbors);
        writer.writeUint8(totalBytes);
        for (final n in neighbors) {
          final hop = n.length >= 8 ? n.sublist(0, 8) : Uint8List(8)..setRange(0, n.length, n);
          writer.writeBytes(hop);
        }
      }
    }

    // 5. Capabilities TLV (Optional 4-byte bitmask)
    if (announcement.capabilities != null) {
      writer.writeUint8(tlvCapabilities);
      writer.writeUint8(4);
      writer.writeUint32(announcement.capabilities!);
    }

    // 6. Bridge Geohash TLV (Optional string)
    if (announcement.bridgeGeohash != null) {
      final geohashBytes = utf8.encode(announcement.bridgeGeohash!);
      if (geohashBytes.length <= 255) {
        writer.writeUint8(tlvBridgeGeohash);
        writer.writeUint8(geohashBytes.length);
        writer.writeBytes(geohashBytes);
      }
    }

    // 7. Privacy-Preserving Phone Commitment Hash TLV (8-byte tag, zero raw string leakage)
    final phoneCommitment = announcement.phoneHash ??
        (announcement.phoneNumber != null && announcement.phoneNumber!.isNotEmpty
            ? computePhoneCommitment(announcement.phoneNumber!)
            : null);

    if (phoneCommitment != null && phoneCommitment.length == 8) {
      writer.writeUint8(tlvPhoneNumber);
      writer.writeUint8(8);
      writer.writeBytes(phoneCommitment);
    }

    return writer.toBytes();
  }

  /// Decodes binary TLV data into an [AnnouncementPayload].
  /// Resiliently skips unknown TLV types for future protocol extensibility.
  static AnnouncementPayload? decode(Uint8List bytes) {
    if (bytes.isEmpty) return null;

    final reader = BinaryReader(bytes);
    String? nickname;
    Uint8List? noisePublicKey;
    Uint8List? signingPublicKey;
    List<Uint8List>? directNeighbors;
    int? capabilities;
    String? bridgeGeohash;
    String? phoneNumber;
    Uint8List? phoneHash;

    try {
      while (!reader.isAtEnd) {
        if (reader.remaining < 2) break;

        final tag = reader.readUint8();
        final length = reader.readUint8();
        if (reader.remaining < length) break;

        final valBytes = reader.readBytes(length);

        switch (tag) {
          case tlvNickname:
            nickname = utf8.decode(valBytes, allowMalformed: true);
            break;
          case tlvNoisePublicKey:
            noisePublicKey = valBytes;
            break;
          case tlvSigningPublicKey:
            signingPublicKey = valBytes;
            break;
          case tlvDirectNeighbors:
            final count = length ~/ 8;
            final neighbors = <Uint8List>[];
            for (int i = 0; i < count; i++) {
              neighbors.add(valBytes.sublist(i * 8, (i + 1) * 8));
            }
            directNeighbors = neighbors;
            break;
          case tlvCapabilities:
            if (length >= 4) {
              capabilities = ByteData.sublistView(valBytes).getUint32(0, Endian.big);
            }
            break;
          case tlvBridgeGeohash:
            bridgeGeohash = utf8.decode(valBytes, allowMalformed: true);
            break;
          case tlvPhoneNumber:
            if (length == 8) {
              phoneHash = valBytes;
            } else {
              // Backward-compatibility fallback for legacy cleartext broadcasts
              phoneNumber = utf8.decode(valBytes, allowMalformed: true);
              phoneHash = computePhoneCommitment(phoneNumber);
            }
            break;
          default:
            // Unknown TLV tag: safely ignored for future forward-compatibility!
            break;
        }
      }

      // Mandatory fields
      if (nickname == null || noisePublicKey == null || signingPublicKey == null) {
        return null;
      }

      return AnnouncementPayload(
        nickname: nickname,
        noisePublicKey: noisePublicKey,
        signingPublicKey: signingPublicKey,
        directNeighbors: directNeighbors,
        capabilities: capabilities,
        bridgeGeohash: bridgeGeohash,
        phoneHash: phoneHash,
        phoneNumber: phoneNumber,
      );
    } catch (_) {
      return null;
    }
  }
}
