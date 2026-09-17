import 'dart:async';
import 'dart:typed_data';

import '../entities/bitchat_packet.dart';
import '../enums/message_type.dart';
import '../enums/noise_payload_type.dart';
import 'feature_registry.dart';
import 'noise_session_manager.dart';

/// Function signature for sending a directed packet through the transport mesh.
typedef SendDirectedPacketCallback = Future<void> Function({
  required Uint8List recipientId,
  required MessageType type,
  required Uint8List payload,
});

/// Callback invoked when an incoming encrypted packet is successfully decrypted.
typedef InboundDecryptedPayloadHandler = void Function(
  BitchatPacket packet,
  PacketContext context,
  NoisePayloadType payloadType,
  Uint8List innerPayload,
);

/// Callback invoked when a Noise_XX session is successfully established.
typedef SessionEstablishedCallback = void Function(
  Uint8List peerId,
  NoiseSession session,
);

/// Feature module handling end-to-end encrypted communication using the Noise Protocol Framework.
///
/// Implements [ProtocolFeatureModule] to register for:
/// - [MessageType.noiseHandshake] (0x10): Handles 3-way mutual authentication handshakes (Noise_XX).
/// - [MessageType.noiseEncrypted] (0x11): Decrypts transport frames with ChaCha20-Poly1305.
class NoiseProtocolModule implements ProtocolFeatureModule {
  final NoiseSessionManager sessionManager;
  final SendDirectedPacketCallback sendDirectedPacket;
  final InboundDecryptedPayloadHandler? onDecryptedPayload;
  final SessionEstablishedCallback? onSessionEstablished;

  final Map<String, List<_PendingInboundEncryptedPacket>> _pendingInboundPackets = {};

  NoiseProtocolModule({
    required this.sessionManager,
    required this.sendDirectedPacket,
    this.onDecryptedPayload,
    this.onSessionEstablished,
  });

  @override
  String get moduleId => 'noise_e2ee';

  @override
  Set<MessageType> get handledTypes => {
        MessageType.noiseHandshake,
        MessageType.noiseEncrypted,
      };

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    if (packet.type == MessageType.noiseHandshake) {
      await _handleHandshake(packet, context);
    } else if (packet.type == MessageType.noiseEncrypted) {
      await _handleEncrypted(packet, context);
    }
  }

  Future<void> _handleHandshake(BitchatPacket packet, PacketContext context) async {
    try {
      final result = await sessionManager.handleIncomingHandshakeMessage(
        packet.senderId,
        packet.payload,
      );

      // If a response handshake message is required (e.g. Responder Step 2, Initiator Step 3)
      if (result.responsePayload != null) {
        await sendDirectedPacket(
          recipientId: packet.senderId,
          type: MessageType.noiseHandshake,
          payload: result.responsePayload!,
        );
      }

      if (result.isSessionEstablished && result.session != null) {
        onSessionEstablished?.call(packet.senderId, result.session!);

        // Drain any inbound encrypted packets that arrived out-of-order before Step 3 completed
        final key = _hex(packet.senderId);
        final pending = _pendingInboundPackets.remove(key);
        if (pending != null) {
          for (final item in pending) {
            await _decryptAndDispatch(item.packet, item.context);
          }
        }
      }
    } catch (_) {
      // Ignore malformed or out-of-order handshake packets
    }
  }

  Future<void> _handleEncrypted(BitchatPacket packet, PacketContext context) async {
    if (!sessionManager.hasSession(packet.senderId)) {
      // Buffer packet briefly if a handshake is currently pending or establishing
      final key = _hex(packet.senderId);
      final list = _pendingInboundPackets.putIfAbsent(key, () => []);
      if (list.length < 20) {
        list.add(_PendingInboundEncryptedPacket(packet, context));
      }
      return;
    }

    await _decryptAndDispatch(packet, context);
  }

  Future<void> _decryptAndDispatch(BitchatPacket packet, PacketContext context) async {
    try {
      final decrypted = await sessionManager.decryptPayload(
        packet.senderId,
        packet.payload,
      );

      if (decrypted.isEmpty) return;

      final payloadType = NoisePayloadType.fromRaw(decrypted[0]);
      final innerPayload = Uint8List.sublistView(decrypted, 1);

      onDecryptedPayload?.call(packet, context, payloadType, innerPayload);
    } catch (_) {
      // Drop packets that fail AEAD authentication tag or replay checks
    }
  }

  /// Clears any cached states and buffered in-flight packets.
  void clear() {
    _pendingInboundPackets.clear();
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class _PendingInboundEncryptedPacket {
  final BitchatPacket packet;
  final PacketContext context;
  _PendingInboundEncryptedPacket(this.packet, this.context);
}

