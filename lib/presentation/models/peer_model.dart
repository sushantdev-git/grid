import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import '../../domain/entities/identity_key_pair.dart';
import '../../domain/enums/transport_medium.dart';

/// Presentation model representing a discovered or connected peer on the network.
class PeerModel {
  final String peerId;
  final String nickname;
  /// Optional local phone number. Null if not set.
  final String? phoneNumber;
  /// Privacy-preserving 8-byte commitment tag (hex string) advertised over BLE mesh.
  final String? phoneHash;
  final String? noisePublicKey;
  final String? signingPublicKey;
  final int? rssi;
  final int hops;
  final DateTime lastSeen;
  final bool isDirectNeighbor;
  final bool isVerified;
  final TransportMedium medium;
  final String? safetyNumber;

  const PeerModel({
    required this.peerId,
    required this.nickname,
    this.phoneNumber,
    this.phoneHash,
    this.noisePublicKey,
    this.signingPublicKey,
    this.rssi,
    this.hops = 0,
    required this.lastSeen,
    this.isDirectNeighbor = true,
    this.isVerified = false,
    this.medium = TransportMedium.bleMesh,
    this.safetyNumber,
  });

  /// Serializes peer info to Map for local disk persistence.
  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'nickname': nickname,
    'phoneNumber': phoneNumber,
    'phoneHash': phoneHash,
    'noisePublicKey': noisePublicKey,
    'signingPublicKey': signingPublicKey,
    'rssi': rssi,
    'hops': hops,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
    'isDirectNeighbor': isDirectNeighbor,
    'isVerified': isVerified,
    'medium': medium.name,
    'safetyNumber': safetyNumber,
  };

  /// Restores peer info from persistent Map.
  factory PeerModel.fromJson(Map<String, dynamic> json) {
    return PeerModel(
      peerId: json['peerId'] as String,
      nickname: json['nickname'] as String? ?? 'peer',
      phoneNumber: json['phoneNumber'] as String?,
      phoneHash: json['phoneHash'] as String?,
      noisePublicKey: json['noisePublicKey'] as String?,
      signingPublicKey: json['signingPublicKey'] as String?,
      rssi: json['rssi'] as int?,
      hops: json['hops'] as int? ?? 0,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int? ?? 0),
      isDirectNeighbor: json['isDirectNeighbor'] as bool? ?? true,
      isVerified: json['isVerified'] as bool? ?? false,
      medium: TransportMedium.values.firstWhere(
        (m) => m.name == json['medium'],
        orElse: () => TransportMedium.bleMesh,
      ),
      safetyNumber: json['safetyNumber'] as String?,
    );
  }

  /// Formats the safety number into 12 blocks of 5 digits if available.
  String? get formattedSafetyNumber {
    if (safetyNumber == null) return null;
    return IdentityKeyPair.formatSafetyNumber(safetyNumber!);
  }

  /// Truncated 8-character peer identifier for UI badges.
  String get shortPeerId =>
      peerId.length > 8 ? peerId.substring(0, 8) : peerId;

  /// Digits-only version of phone number for search matching (strips spaces, dashes, +).
  String? get phoneDigits =>
      phoneNumber?.replaceAll(RegExp(r'[^\d]'), '');

  /// Checks if this peer matches a search query by privacy-preserving phone commitment tag (Solution 1)
  /// or local known phone number digits.
  bool matchesPhoneCommitment(String query) {
    final queryDigits = query.replaceAll(RegExp(r'[^\d]'), '');
    if (queryDigits.isEmpty) return false;

    // 1. Match against advertised 8-byte phone commitment hash tag
    if (phoneHash != null && phoneHash!.isNotEmpty) {
      final input = utf8.encode('grid-phone-v1:$queryDigits');
      final digest = crypto.sha256.convert(input).bytes.sublist(0, 8);
      final expectedHex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (phoneHash!.toLowerCase() == expectedHex.toLowerCase()) {
        return true;
      }
    }

    // 2. Match against locally known full phone number if saved
    if (phoneNumber != null) {
      final localDigits = phoneNumber!.replaceAll(RegExp(r'[^\d]'), '');
      if (localDigits.isNotEmpty && (localDigits.contains(queryDigits) || queryDigits.contains(localDigits))) {
        return true;
      }
    }

    return false;
  }

  /// User-friendly signal quality indicator.
  String get signalQuality {
    if (rssi == null) return 'Internet / Relay';
    if (rssi! >= -60) return 'Excellent';
    if (rssi! >= -75) return 'Good';
    if (rssi! >= -85) return 'Fair';
    return 'Weak';
  }

  PeerModel copyWith({
    String? peerId,
    String? nickname,
    Object? phoneNumber = _peerSentinel,
    Object? phoneHash = _peerSentinel,
    String? noisePublicKey,
    String? signingPublicKey,
    int? rssi,
    int? hops,
    DateTime? lastSeen,
    bool? isDirectNeighbor,
    bool? isVerified,
    TransportMedium? medium,
    String? safetyNumber,
  }) {
    return PeerModel(
      peerId: peerId ?? this.peerId,
      nickname: nickname ?? this.nickname,
      phoneNumber: phoneNumber == _peerSentinel ? this.phoneNumber : phoneNumber as String?,
      phoneHash: phoneHash == _peerSentinel ? this.phoneHash : phoneHash as String?,
      noisePublicKey: noisePublicKey ?? this.noisePublicKey,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      rssi: rssi ?? this.rssi,
      hops: hops ?? this.hops,
      lastSeen: lastSeen ?? this.lastSeen,
      isDirectNeighbor: isDirectNeighbor ?? this.isDirectNeighbor,
      isVerified: isVerified ?? this.isVerified,
      medium: medium ?? this.medium,
      safetyNumber: safetyNumber ?? this.safetyNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerModel && runtimeType == other.runtimeType && peerId == other.peerId;

  @override
  int get hashCode => peerId.hashCode;
}

const Object _peerSentinel = Object();
