import 'dart:typed_data';
import '../../domain/enums/transport_medium.dart';

/// Delivery state of a chat message in the presentation timeline.
enum MessageDeliveryStatus {
  sending,
  sent,
  delivered,
  failed,
}

/// Immutable presentation model representing a chat message in the UI timeline.
class ChatMessage {
  final String id;
  final String senderId;
  final String senderNickname;
  final String content;
  final DateTime timestamp;
  final bool isOutgoing;
  final bool isEncrypted;
  final TransportMedium medium;
  final String channelOrPeerId;
  final bool isSystem;
  final MessageDeliveryStatus deliveryStatus;
  final Uint8List? rawPayload;
  final String? mediaPath;
  final int? mediaDurationMs;
  final List<int>? waveformSamples;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderNickname,
    required this.content,
    required this.timestamp,
    required this.isOutgoing,
    this.isEncrypted = false,
    this.medium = TransportMedium.bleMesh,
    required this.channelOrPeerId,
    this.isSystem = false,
    this.deliveryStatus = MessageDeliveryStatus.sent,
    this.rawPayload,
    this.mediaPath,
    this.mediaDurationMs,
    this.waveformSamples,
  });

  bool get isVoice => mediaPath != null || (mediaDurationMs != null && mediaDurationMs! > 0);

  /// Creates a local system message (e.g. notifications, slaps, pings, diagnostics).
  factory ChatMessage.system({
    required String id,
    required String content,
    required String channelOrPeerId,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id,
      senderId: 'system',
      senderNickname: 'System',
      content: content,
      timestamp: timestamp ?? DateTime.now(),
      isOutgoing: false,
      isEncrypted: false,
      channelOrPeerId: channelOrPeerId,
      isSystem: true,
      deliveryStatus: MessageDeliveryStatus.delivered,
    );
  }

  /// Serializes message to Map for local disk persistence.
  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderNickname': senderNickname,
    'content': content,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'isOutgoing': isOutgoing,
    'isEncrypted': isEncrypted,
    'medium': medium.name,
    'channelOrPeerId': channelOrPeerId,
    'isSystem': isSystem,
    'deliveryStatus': deliveryStatus.name,
    if (mediaPath != null) 'mediaPath': mediaPath,
    if (mediaDurationMs != null) 'mediaDurationMs': mediaDurationMs,
    if (waveformSamples != null) 'waveformSamples': waveformSamples,
  };

  /// Restores message from persistent Map.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderNickname: json['senderNickname'] as String? ?? 'anon',
      content: json['content'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
      isOutgoing: json['isOutgoing'] as bool? ?? false,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
      medium: TransportMedium.values.firstWhere(
        (m) => m.name == json['medium'],
        orElse: () => TransportMedium.bleMesh,
      ),
      channelOrPeerId: json['channelOrPeerId'] as String? ?? '#mesh',
      isSystem: json['isSystem'] as bool? ?? false,
      deliveryStatus: MessageDeliveryStatus.values.firstWhere(
        (s) => s.name == json['deliveryStatus'],
        orElse: () => MessageDeliveryStatus.sent,
      ),
      mediaPath: json['mediaPath'] as String?,
      mediaDurationMs: json['mediaDurationMs'] as int?,
      waveformSamples: (json['waveformSamples'] as List<dynamic>?)?.map((e) => e as int).toList(),
    );
  }

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderNickname,
    String? content,
    DateTime? timestamp,
    bool? isOutgoing,
    bool? isEncrypted,
    TransportMedium? medium,
    String? channelOrPeerId,
    bool? isSystem,
    MessageDeliveryStatus? deliveryStatus,
    Uint8List? rawPayload,
    String? mediaPath,
    int? mediaDurationMs,
    List<int>? waveformSamples,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderNickname: senderNickname ?? this.senderNickname,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      medium: medium ?? this.medium,
      channelOrPeerId: channelOrPeerId ?? this.channelOrPeerId,
      isSystem: isSystem ?? this.isSystem,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      rawPayload: rawPayload ?? this.rawPayload,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaDurationMs: mediaDurationMs ?? this.mediaDurationMs,
      waveformSamples: waveformSamples ?? this.waveformSamples,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
