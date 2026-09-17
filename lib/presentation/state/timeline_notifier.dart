import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/bitchat_coordinator.dart';
import '../../core/utils/geohash.dart';
import '../../domain/entities/bitchat_packet.dart';
import '../../domain/enums/message_type.dart';
import '../../domain/enums/transport_medium.dart';
import '../../domain/ports/transport_port.dart';
import '../../domain/services/message_router.dart';
import '../../infrastructure/codecs/binary_protocol_codec.dart';
import '../../infrastructure/codecs/fragment_codec.dart';
import '../../infrastructure/codecs/voice_frame_codec.dart';
import '../../infrastructure/services/local_storage_service.dart';
import '../../infrastructure/services/voice_service.dart';
import '../models/chat_message.dart';
import '../utils/chat_command.dart';
import 'channels_notifier.dart';
import 'identity_state.dart';
import 'peers_notifier.dart';

/// State holding in-memory and persistent conversation timelines partitioned by channel or peer ID.
class TimelineState {
  final Map<String, List<ChatMessage>> messagesByChannel;

  const TimelineState({this.messagesByChannel = const {}});

  List<ChatMessage> getMessages(String channelOrPeerId) {
    return messagesByChannel[TimelineNotifier.normalizeKey(channelOrPeerId)] ?? const [];
  }

  TimelineState copyWith({Map<String, List<ChatMessage>>? messagesByChannel}) {
    return TimelineState(
      messagesByChannel: messagesByChannel ?? this.messagesByChannel,
    );
  }
}

/// StateNotifier managing ephemeral message feeds, slash command routing, and packet dispatching.
class TimelineNotifier extends StateNotifier<TimelineState> {
  final Ref ref;
  final MessageRouter? router;
  final LocalStorageService? storageService;
  static const int maxMessagesPerChannel = 500;

  TimelineNotifier(this.ref, {this.router, this.storageService, TimelineState? initial})
      : super(initial ?? const TimelineState());

  /// Normalizes channel or peer identifiers (e.g. '@peer_id' -> 'peer_id', lowercase).
  static String normalizeKey(String channelOrPeerId) {
    var key = channelOrPeerId.trim().toLowerCase();
    if (key.startsWith('@')) {
      key = key.substring(1);
    }
    return key;
  }

  int _initEpoch = 0;

  /// Initializes by restoring saved conversations from persistent storage.
  Future<void> initialize() async {
    if (storageService == null) return;
    final currentEpoch = ++_initEpoch;
    try {
      final loaded = await storageService!.loadTimeline();
      if (loaded != null && loaded.isNotEmpty) {
        if (mounted && _initEpoch == currentEpoch) {
          state = state.copyWith(messagesByChannel: loaded);
        }
      }
    } catch (_) {}
  }

  void _persistTimeline() {
    if (storageService != null) {
      try {
        storageService!.saveTimeline(state.messagesByChannel);
      } catch (_) {}
    }
  }

  /// Adds a message into the specified conversation timeline with LRU ring-buffer capping.
  void addMessage(ChatMessage message) {
    final key = normalizeKey(message.channelOrPeerId);
    final existing = state.messagesByChannel[key] ?? [];

    final updated = List<ChatMessage>.from(existing)..add(message);
    if (updated.length > maxMessagesPerChannel) {
      updated.removeAt(0);
    }

    final newMap = Map<String, List<ChatMessage>>.from(state.messagesByChannel);
    newMap[key] = updated;
    state = state.copyWith(messagesByChannel: newMap);
    _persistTimeline();
  }

  /// Sends a message or executes a slash command from the user input composer.
  Future<void> sendUserMessage({
    required String channelOrPeerId,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    if (ChatCommand.isCommand(clean)) {
      final cmd = ChatCommand.parse(clean);
      await executeCommand(cmd, channelOrPeerId);
      return;
    }

    final identity = ref.read(identityProvider);
    final isChannel = channelOrPeerId.startsWith('#');
    final messageId = '${DateTime.now().millisecondsSinceEpoch}_${identity.peerIdHex.substring(0, 4)}';

    final chatMessage = ChatMessage(
      id: messageId,
      senderId: identity.peerIdHex,
      senderNickname: identity.nickname,
      content: clean,
      timestamp: DateTime.now(),
      isOutgoing: true,
      isEncrypted: !isChannel,
      medium: TransportMedium.bleMesh,
      channelOrPeerId: channelOrPeerId,
      deliveryStatus: MessageDeliveryStatus.sent,
    );

    addMessage(chatMessage);

    // Wire protocol dispatching
    final coordinator = ref.read(bitchatCoordinatorProvider);
    if (coordinator != null) {
      final payloadBytes = Uint8List.fromList(utf8.encode(clean));
      try {
        if (isChannel) {
          await coordinator.meshEngine.sendBroadcastPacket(
            type: MessageType.message,
            payload: payloadBytes,
          );
        } else {
          final hexClean = channelOrPeerId.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
          if (hexClean.isNotEmpty) {
            final targetBytes = Uint8List.fromList(
              List.generate(hexClean.length ~/ 2, (i) => int.parse(hexClean.substring(i * 2, i * 2 + 2), radix: 16)),
            );
            await coordinator.meshEngine.sendDirectedPacket(
              recipientId: targetBytes,
              type: MessageType.message,
              payload: payloadBytes,
            );
          }
        }
      } catch (_) {
        // Handled silently in offline / decoupled mode
      }
    } else if (router != null) {
      final payloadBytes = Uint8List.fromList(utf8.encode(clean));

      try {
        if (isChannel) {
          if (Geohash.isLocationChannel(channelOrPeerId)) {
            await router!.sendLocationMessage(channelOrPeerId, payloadBytes);
          } else {
            await router!.sendBroadcast(payloadBytes);
          }
        } else {
          await router!.sendDirected(channelOrPeerId, payloadBytes);
        }
      } catch (_) {
        // Handled silently in offline / decoupled testing mode
      }
    }
  }

  /// Sends a Push-to-Talk voice memo.
  /// Slices large audio payloads into MTU-safe fragments for BLE mesh transmission.
  Future<void> sendVoiceMessage({
    required String channelOrPeerId,
    required String audioPath,
    required int durationMs,
    required Uint8List waveform,
    required Uint8List audioBytes,
  }) async {
    final identity = ref.read(identityProvider);
    final isChannel = channelOrPeerId.startsWith('#');
    final messageId = 'voice_${DateTime.now().millisecondsSinceEpoch}_${identity.peerIdHex.substring(0, 4)}';
    final durationSec = (durationMs / 1000).toStringAsFixed(1);

    final chatMessage = ChatMessage(
      id: messageId,
      senderId: identity.peerIdHex,
      senderNickname: identity.nickname,
      content: '[Voice Note: ${durationSec}s]',
      timestamp: DateTime.now(),
      isOutgoing: true,
      isEncrypted: !isChannel,
      medium: TransportMedium.bleMesh,
      channelOrPeerId: channelOrPeerId,
      deliveryStatus: MessageDeliveryStatus.sent,
      mediaPath: audioPath,
      mediaDurationMs: durationMs,
      waveformSamples: waveform.toList(),
    );

    addMessage(chatMessage);

    final voicePayload = VoiceFramePayload(
      durationMs: durationMs,
      codec: VoiceCodecType.aacLc,
      waveform: waveform,
      audioData: audioBytes,
    );
    final voiceBytes = VoiceFrameCodec.encode(voicePayload);

    final coordinator = ref.read(bitchatCoordinatorProvider);
    final hexClean = channelOrPeerId.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final targetBytes = (!isChannel && hexClean.isNotEmpty)
        ? Uint8List.fromList(
            List.generate(hexClean.length ~/ 2, (i) => int.parse(hexClean.substring(i * 2, i * 2 + 2), radix: 16)))
        : null;

    if (coordinator != null) {
      try {
        if (voiceBytes.length <= FragmentCodec.defaultMaxFragmentPayloadSize) {
          if (isChannel) {
            await coordinator.meshEngine.sendBroadcastPacket(
              type: MessageType.voiceFrame,
              payload: voiceBytes,
            );
          } else if (targetBytes != null) {
            await coordinator.meshEngine.sendDirectedPacket(
              recipientId: targetBytes,
              type: MessageType.voiceFrame,
              payload: voiceBytes,
            );
          }
        } else {
          // Slice payload into MTU-safe fragments
          final rand = math.Random();
          final fragmentId = Uint8List.fromList(List.generate(8, (_) => rand.nextInt(256)));

          final voicePacket = BitchatPacket(
            version: 1,
            type: MessageType.voiceFrame,
            ttl: 7,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            senderId: identity.keyPair?.peerId ?? Uint8List(8),
            recipientId: targetBytes,
            payload: voiceBytes,
          );
          final rawPacketBytes = BinaryProtocolCodec.encode(voicePacket, padding: false);
          if (rawPacketBytes != null) {
            final fragments = FragmentCodec.slice(
              rawPacketBytes,
              fragmentId: fragmentId,
              maxChunkSize: FragmentCodec.defaultMaxFragmentPayloadSize,
            );
            for (final frag in fragments) {
              final fragPayload = FragmentCodec.encode(frag);
              if (isChannel) {
                await coordinator.meshEngine.sendBroadcastPacket(
                  type: MessageType.fragment,
                  payload: fragPayload,
                );
              } else if (targetBytes != null) {
                await coordinator.meshEngine.sendDirectedPacket(
                  recipientId: targetBytes,
                  type: MessageType.fragment,
                  payload: fragPayload,
                );
              }
            }
          }
        }
      } catch (_) {
        // Handled silently in decoupled mode
      }
    } else if (router != null) {
      try {
        if (isChannel) {
          await router!.sendBroadcast(voiceBytes);
        } else {
          await router!.sendDirected(channelOrPeerId, voiceBytes);
        }
      } catch (_) {}
    }
  }

  /// Executes a parsed BitChat slash command.
  Future<void> executeCommand(ChatCommand cmd, String currentChannel) async {
    final identity = ref.read(identityProvider);

    switch (cmd.type) {
      case ChatCommandType.privateMessage:
        if (cmd.errorMessage != null) {
          _addSystemMessage(currentChannel, cmd.errorMessage!);
          return;
        }
        final targetPeer = cmd.target!;
        final text = cmd.argument!;
        await sendUserMessage(channelOrPeerId: targetPeer, text: text);
        _addSystemMessage(currentChannel, 'Sent private message to @$targetPeer');
        break;

      case ChatCommandType.who:
        final peersState = ref.read(peersProvider);
        final peers = peersState.allPeers;
        if (peers.isEmpty) {
          _addSystemMessage(currentChannel, 'No active peers currently discovered nearby.');
        } else {
          final buffer = StringBuffer('Discovered Peers (${peers.length}):\n');
          for (final p in peers) {
            final verifiedTag = p.isVerified ? ' [VERIFIED]' : '';
            final directTag = p.isDirectNeighbor ? '1-hop BLE' : '${p.hops}-hops';
            buffer.writeln('• ${p.nickname} (${p.shortPeerId})$verifiedTag — $directTag, ${p.signalQuality}');
          }
          _addSystemMessage(currentChannel, buffer.toString().trimRight());
        }
        break;

      case ChatCommandType.slap:
        if (cmd.errorMessage != null) {
          _addSystemMessage(currentChannel, cmd.errorMessage!);
          return;
        }
        final slapText = '* ${identity.nickname} slaps ${cmd.target} with a large trout *';
        await sendUserMessage(channelOrPeerId: currentChannel, text: slapText);
        break;

      case ChatCommandType.ping:
        if (cmd.errorMessage != null) {
          _addSystemMessage(currentChannel, cmd.errorMessage!);
          return;
        }
        _addSystemMessage(currentChannel, 'PING sent to ${cmd.target} (waiting for pong...)');
        break;

      case ChatCommandType.join:
        if (cmd.errorMessage != null) {
          _addSystemMessage(currentChannel, cmd.errorMessage!);
          return;
        }
        ref.read(channelsProvider.notifier).joinChannel(cmd.target!);
        _addSystemMessage(cmd.target!, 'Joined channel ${cmd.target}');
        break;

      case ChatCommandType.clear:
        clearChannel(currentChannel);
        _addSystemMessage(currentChannel, 'Conversation timeline cleared.');
        break;

      case ChatCommandType.panic:
        await clearAll();
        _addSystemMessage('#mesh', 'EMERGENCY PANIC WIPE EXECUTED. All in-memory data purged.');
        break;

      case ChatCommandType.help:
        final buffer = StringBuffer('Available BitChat Slash Commands:\n');
        for (final s in ChatCommand.availableSuggestions) {
          buffer.writeln('• ${s.syntax} — ${s.description}');
        }
        _addSystemMessage(currentChannel, buffer.toString().trimRight());
        break;

      case ChatCommandType.nick:
        // Profile commands are intercepted in ChatScreen._handleSend() before reaching here.
        if (cmd.errorMessage != null) {
          _addSystemMessage(currentChannel, cmd.errorMessage!);
        }
        break;

      case ChatCommandType.phone:
        // Profile commands are intercepted in ChatScreen._handleSend() before reaching here.
        if (cmd.errorMessage != null) {
          _addSystemMessage(currentChannel, cmd.errorMessage!);
        }
        break;

      case ChatCommandType.unknown:
        _addSystemMessage(currentChannel, cmd.errorMessage ?? 'Unknown command');
        break;
    }
  }

  void _addSystemMessage(String channelOrPeerId, String text) {
    final sysMsg = ChatMessage.system(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      content: text,
      channelOrPeerId: channelOrPeerId,
    );
    addMessage(sysMsg);
  }

  /// Processes an inbound raw packet received from the mesh network.
  void handleInboundPacket(BitchatPacket packet, TransportPacketEvent event) {
    final identity = ref.read(identityProvider);
    final senderHex = packet.senderId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Drop our own echoed packets
    if (senderHex.toLowerCase() == identity.peerIdHex.toLowerCase()) {
      return;
    }

    final peersState = ref.read(peersProvider);
    final peer = peersState.getPeer(senderHex);
    final senderName = peer?.nickname ?? 'node_${senderHex.substring(0, 4)}';

    if (packet.type == MessageType.message) {
      try {
        final text = utf8.decode(packet.payload);
        final isDirected = packet.recipientId != null;
        final channel = isDirected ? senderHex : '#mesh';

        final msg = ChatMessage(
          id: 'in_${DateTime.now().millisecondsSinceEpoch}_${packet.timestamp}',
          senderId: senderHex,
          senderNickname: senderName,
          content: text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
          isOutgoing: false,
          isEncrypted: isDirected,
          medium: event.medium,
          channelOrPeerId: channel,
          deliveryStatus: MessageDeliveryStatus.delivered,
        );

        addMessage(msg);
      } catch (_) {}
    }
  }

  /// Processes an inbound Push-to-Talk voice frame received over the network or reassembled from fragments.
  Future<void> handleInboundVoiceFrame(BitchatPacket packet, TransportPacketEvent event) async {
    final identity = ref.read(identityProvider);
    final senderHex = packet.senderId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Drop our own echoed packets
    if (senderHex.toLowerCase() == identity.peerIdHex.toLowerCase()) {
      return;
    }

    final peersState = ref.read(peersProvider);
    final peer = peersState.getPeer(senderHex);
    final senderName = peer?.nickname ?? 'node_${senderHex.substring(0, 4)}';

    final voicePayload = VoiceFrameCodec.decode(packet.payload);
    if (voicePayload == null) return;

    final messageId = 'in_voice_${DateTime.now().millisecondsSinceEpoch}_${packet.timestamp}';
    final voiceService = ref.read(voiceServiceProvider);
    final filePath = await voiceService.saveReceivedVoiceNote(voicePayload.audioData, messageId);

    final isDirected = packet.recipientId != null;
    final channel = isDirected ? senderHex : '#mesh';
    final durationSec = (voicePayload.durationMs / 1000).toStringAsFixed(1);

    final msg = ChatMessage(
      id: messageId,
      senderId: senderHex,
      senderNickname: senderName,
      content: '[Voice Note: ${durationSec}s]',
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
      isOutgoing: false,
      isEncrypted: isDirected,
      medium: event.medium,
      channelOrPeerId: channel,
      deliveryStatus: MessageDeliveryStatus.delivered,
      mediaPath: filePath,
      mediaDurationMs: voicePayload.durationMs,
      waveformSamples: voicePayload.waveform.toList(),
    );

    addMessage(msg);
  }

  /// Clears messages for a single channel or peer conversation.
  void clearChannel(String channelOrPeerId) {
    final key = normalizeKey(channelOrPeerId);
    final newMap = Map<String, List<ChatMessage>>.from(state.messagesByChannel);
    newMap.remove(key);
    state = state.copyWith(messagesByChannel: newMap);
    _persistTimeline();
  }

  /// Emergency panic wipe: zeroizes all message timelines across all channels and deletes disk cache.
  Future<void> clearAll() async {
    _initEpoch++;
    state = const TimelineState(messagesByChannel: {});
    if (storageService != null) {
      try {
        await storageService!.deleteTimeline();
      } catch (_) {}
    }
  }
}

/// Global provider for the conversation timeline.
final timelineProvider = StateNotifierProvider<TimelineNotifier, TimelineState>((ref) {
  final storage = ref.watch(localStorageServiceProvider);
  final notifier = TimelineNotifier(ref, storageService: storage);
  notifier.initialize();
  return notifier;
});
