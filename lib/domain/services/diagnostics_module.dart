import 'dart:math';
import 'dart:typed_data';

import '../entities/bitchat_packet.dart';
import '../enums/message_type.dart';
import 'feature_registry.dart';

/// Callback to send a directed packet (used to reply with a pong).
typedef SendPongCallback = Future<void> Function(
  Uint8List recipientId,
  Uint8List payload,
);

/// Callback when a traceroute pong response is received.
typedef PongReceivedCallback = void Function(
  Uint8List senderId,
  int rttMs,
  int hops,
);

/// Protocol feature module handling network diagnostics: ping probes and pong replies.
///
/// Respects node privacy: if [isTraceAllowed] returns false, incoming diagnostic pings
/// are silently dropped without disclosing node presence or location.
class DiagnosticsModule implements ProtocolFeatureModule {
  final SendPongCallback onSendPong;
  final PongReceivedCallback? onPongReceived;
  final bool Function() isTraceAllowed;

  DiagnosticsModule({
    required this.onSendPong,
    this.onPongReceived,
    required this.isTraceAllowed,
  });

  @override
  String get moduleId => 'diagnostics';

  @override
  Set<MessageType> get handledTypes => {
        MessageType.ping,
        MessageType.pong,
      };

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    if (packet.type == MessageType.ping) {
      // Privacy check: do not respond if user opted out from diagnostic discovery
      if (!isTraceAllowed()) {
        return;
      }

      // Echo back pong with original timestamp payload so initiator can measure RTT
      try {
        await onSendPong(packet.senderId, packet.payload);
      } catch (_) {}
    } else if (packet.type == MessageType.pong) {
      if (packet.payload.length >= 8) {
        final sentTs = ByteData.sublistView(packet.payload).getUint64(0, Endian.big);
        final now = DateTime.now().millisecondsSinceEpoch;
        final rttMs = max(0, now - sentTs);
        onPongReceived?.call(packet.senderId, rttMs, context.hops);
      }
    }
  }
}
