import '../enums/message_type.dart';
import '../enums/transport_medium.dart';

/// Direction of traffic relative to the local mesh node.
enum MeshTrafficDirection {
  inbound,
  outbound,
  relayed,
  dropped,
}

/// An immutable telemetry entry capturing packet traversal, forwarding, or dropping.
class MeshTrafficEntry {
  final String id;
  final DateTime timestamp;
  final MeshTrafficDirection direction;
  final MessageType type;
  final String senderId;
  final String? recipientId;
  final int ttl;
  final int hops;
  final int payloadLength;
  final TransportMedium medium;
  final String? dropReason;
  final String summary;

  const MeshTrafficEntry({
    required this.id,
    required this.timestamp,
    required this.direction,
    required this.type,
    required this.senderId,
    this.recipientId,
    required this.ttl,
    required this.hops,
    required this.payloadLength,
    required this.medium,
    this.dropReason,
    required this.summary,
  });

  /// Short 4-character hex identifier for sender.
  String get shortSenderId =>
      senderId.length >= 8 ? senderId.substring(0, 8) : senderId;

  /// Short 4-character hex identifier for recipient.
  String? get shortRecipientId => recipientId != null && recipientId!.length >= 8
      ? recipientId!.substring(0, 8)
      : recipientId;
}
