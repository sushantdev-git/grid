import '../entities/bitchat_packet.dart';
import '../enums/message_type.dart';
import '../../infrastructure/codecs/binary_protocol_codec.dart';
import '../../infrastructure/codecs/fragment_codec.dart';
import 'chat_message_module.dart';
import 'feature_registry.dart';
import 'fragment_assembler.dart';

/// Callback invoked when a complete voice frame packet is received.
typedef InboundVoiceMessageHandler = void Function(
  BitchatPacket packet,
  PacketContext context,
);

/// Callback invoked when a generic assembled packet is ready for dispatch.
typedef InboundPacketHandler = Future<void> Function(
  BitchatPacket packet,
  PacketContext context,
);

/// Protocol feature module that processes direct [MessageType.voiceFrame] packets
/// and reassembles incoming [MessageType.fragment] streams into complete messages.
class VoiceMessageModule implements ProtocolFeatureModule {
  final InboundVoiceMessageHandler onVoiceMessage;
  final InboundMessageHandler? onGenericMessage;
  final InboundPacketHandler? onAssembledPacket;
  final FragmentAssembler fragmentAssembler;

  VoiceMessageModule({
    required this.onVoiceMessage,
    this.onGenericMessage,
    this.onAssembledPacket,
    FragmentAssembler? fragmentAssembler,
  }) : fragmentAssembler = fragmentAssembler ?? FragmentAssembler();

  @override
  String get moduleId => 'voice_messages';

  @override
  Set<MessageType> get handledTypes => {
        MessageType.voiceFrame,
        MessageType.fragment,
      };

  @override
  Future<void> handleInboundPacket(BitchatPacket packet, PacketContext context) async {
    if (packet.type == MessageType.voiceFrame) {
      onVoiceMessage(packet, context);
      return;
    }

    if (packet.type == MessageType.fragment) {
      final fragment = FragmentCodec.decode(packet.payload);
      if (fragment == null) return;

      final assembledBytes = fragmentAssembler.ingestFragment(fragment);
      if (assembledBytes != null) {
        final innerPacket = BinaryProtocolCodec.decode(assembledBytes);
        if (innerPacket != null) {
          if (innerPacket.type == MessageType.voiceFrame) {
            onVoiceMessage(innerPacket, context);
          } else if (innerPacket.type == MessageType.message && onGenericMessage != null) {
            onGenericMessage!(innerPacket, context);
          } else if (onAssembledPacket != null) {
            await onAssembledPacket!(innerPacket, context);
          }
        }
      }
    }
  }

  /// Clears in-flight fragment sessions (e.g. on panic wipe).
  void clear() {
    fragmentAssembler.clear();
  }
}
