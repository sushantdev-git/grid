import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/bitchat_packet.dart';
import '../domain/entities/identity_key_pair.dart';
import '../domain/enums/message_type.dart';
import '../domain/enums/noise_payload_type.dart';
import '../domain/ports/transport_port.dart';
import '../domain/services/announcement_module.dart';
import '../domain/services/chat_message_module.dart';
import '../domain/services/courier_module.dart';
import '../domain/services/courier_service.dart';
import '../domain/services/feature_registry.dart';
import '../domain/services/mesh_engine.dart';
import '../domain/services/message_router.dart';
import '../domain/services/noise_module.dart';
import '../domain/services/noise_session_manager.dart';
import '../domain/services/panic_zeroization_service.dart';
import '../domain/services/seen_packet_cache.dart';
import '../domain/services/voice_message_module.dart';
import '../infrastructure/adapters/native_ble_link_adapter.dart';
import '../infrastructure/adapters/nostr_relay_adapter.dart';
import '../infrastructure/codecs/announcement_codec.dart';
import '../presentation/state/identity_state.dart';
import '../presentation/state/peers_notifier.dart';
import '../presentation/state/timeline_notifier.dart';

/// Master coordinator tying together the full Grid stack:
/// - Cryptographic identity & Noise sessions
/// - Controlled flooding MeshEngine
/// - Store-and-forward Courier DTN engine
/// - Dual-transport radio links
/// - Panic zeroization pipeline
class BitchatCoordinator {
  final Uint8List localPeerId;
  final TransportPort transportPort;
  final ProtocolFeatureRegistry featureRegistry;
  final SeenPacketCache seenCache;
  final IdentityKeyPair? keyPair;
  final PeerAnnouncementHandler? onAnnouncementReceived;
  final InboundMessageHandler? onMessageReceived;
  final InboundVoiceMessageHandler? onVoiceReceived;

  late final MeshEngine meshEngine;
  late final CourierService courierService;
  late final VoiceMessageModule voiceMessageModule;
  late final NoiseSessionManager? noiseSessionManager;
  late final NoiseProtocolModule? noiseProtocolModule;
  late final PanicZeroizationService panicZeroizationService;
  final Map<String, List<_PendingOutboundMessage>> _pendingOutboundMessages = {};

  bool _isStarted = false;
  Timer? _announcementTimer;

  BitchatCoordinator({
    required this.localPeerId,
    required this.transportPort,
    ProtocolFeatureRegistry? featureRegistry,
    SeenPacketCache? seenCache,
    this.keyPair,
    this.onAnnouncementReceived,
    this.onMessageReceived,
    this.onVoiceReceived,
  })  : featureRegistry = featureRegistry ?? ProtocolFeatureRegistry(),
        seenCache = seenCache ?? SeenPacketCache() {
    courierService = CourierService(
      localPeerId: localPeerId,
      transportPort: transportPort,
    );

    noiseSessionManager = keyPair != null
        ? NoiseSessionManager(localIdentity: keyPair!)
        : null;

    panicZeroizationService = PanicZeroizationService(
      transportPort: transportPort,
      courierService: courierService,
      seenPacketCache: this.seenCache,
      noiseSessionManager: noiseSessionManager,
    );

    meshEngine = MeshEngine(
      localPeerId: localPeerId,
      transportPort: transportPort,
      featureRegistry: this.featureRegistry,
      seenCache: this.seenCache,
    );

    // Register Courier DTN module into feature registry
    this.featureRegistry.registerModule(CourierModule(courierService));

    if (onAnnouncementReceived != null) {
      this.featureRegistry.registerModule(AnnouncementModule(onAnnouncementReceived!));
    }
    if (onMessageReceived != null) {
      this.featureRegistry.registerModule(ChatMessageModule(onMessageReceived!));
    }

    voiceMessageModule = VoiceMessageModule(
      onVoiceMessage: (packet, context) {
        if (onVoiceReceived != null) {
          onVoiceReceived!(packet, context);
        } else if (onMessageReceived != null) {
          onMessageReceived!(packet, context);
        }
      },
      onGenericMessage: onMessageReceived,
      onAssembledPacket: (packet, context) => this.featureRegistry.dispatch(packet, context),
    );
    this.featureRegistry.registerModule(voiceMessageModule);

    // Wire Noise_XX E2EE protocol module
    if (noiseSessionManager != null) {
      noiseProtocolModule = NoiseProtocolModule(
        sessionManager: noiseSessionManager!,
        sendDirectedPacket: ({required recipientId, required type, required payload}) async {
          await meshEngine.sendDirectedPacket(
            recipientId: recipientId,
            type: type,
            payload: payload,
          );
        },
        onDecryptedPayload: (packet, context, payloadType, innerPayload) {
          if (payloadType == NoisePayloadType.privateMessage) {
            final decryptedPacket = BitchatPacket(
              version: packet.version,
              type: MessageType.noiseEncrypted,
              ttl: packet.ttl,
              timestamp: packet.timestamp,
              senderId: packet.senderId,
              recipientId: packet.recipientId,
              payload: innerPayload,
            );
            onMessageReceived?.call(decryptedPacket, context);
          } else if (payloadType == NoisePayloadType.voiceFrame) {
            final decryptedPacket = BitchatPacket(
              version: packet.version,
              type: MessageType.noiseEncrypted,
              ttl: packet.ttl,
              timestamp: packet.timestamp,
              senderId: packet.senderId,
              recipientId: packet.recipientId,
              payload: innerPayload,
            );
            onVoiceReceived?.call(decryptedPacket, context);
          }
        },
        onSessionEstablished: (peerId, session) async {
          await _flushPendingOutboundMessages(peerId);
        },
      );
      this.featureRegistry.registerModule(noiseProtocolModule!);
    } else {
      noiseProtocolModule = null;
    }
  }

  bool get isStarted => _isStarted;

  /// Broadcasts our peer presence announcement to the mesh and Nostr transports.
  Future<void> broadcastPresence() async {
    if (keyPair == null || !_isStarted) return;

    final payload = AnnouncementPayload(
      nickname: keyPair!.nickname,
      noisePublicKey: keyPair!.noisePublicKeyBytes,
      signingPublicKey: keyPair!.signingPublicKeyBytes,
      phoneNumber: keyPair!.phoneNumber,
    );

    final wireBytes = AnnouncementCodec.encode(payload);
    if (wireBytes != null) {
      try {
        await meshEngine.sendBroadcastPacket(
          type: MessageType.announce,
          payload: wireBytes,
        );
      } catch (_) {}
    }
  }

  /// Starts the mesh engine, transport ports, and periodic background tasks.
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;
    await meshEngine.start();
    await broadcastPresence();

    _announcementTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      broadcastPresence();
    });
  }

  /// Forces a fresh radio scan burst to discover nearby peers and broadcasts presence.
  Future<void> startScan() async {
    if (!_isStarted) {
      await start();
    }
    seenCache.clear();
    await transportPort.startScan();
    await broadcastPresence();
  }

  /// Stops all radio links, mesh routines, and subscriptions.
  Future<void> stop() async {
    _isStarted = false;
    _announcementTimer?.cancel();
    _announcementTimer = null;
    await meshEngine.stop();
    await courierService.dispose();
  }

  /// Sends an end-to-end encrypted 1-on-1 private message using Noise_XX (ChaCha20-Poly1305).
  ///
  /// If a Noise session is already established, encrypts and transmits immediately.
  /// If no session exists yet, buffers the message and initiates a 3-way mutual authentication handshake.
  Future<void> sendDirectEncryptedMessage({
    required Uint8List recipientId,
    required Uint8List plaintext,
  }) async {
    await _sendDirectEncryptedPayload(
      recipientId: recipientId,
      payloadType: NoisePayloadType.privateMessage,
      payloadData: plaintext,
    );
  }

  /// Sends an end-to-end encrypted Push-to-Talk voice note over the mesh.
  Future<void> sendDirectEncryptedVoice({
    required Uint8List recipientId,
    required Uint8List voiceFrameBytes,
  }) async {
    await _sendDirectEncryptedPayload(
      recipientId: recipientId,
      payloadType: NoisePayloadType.voiceFrame,
      payloadData: voiceFrameBytes,
    );
  }

  Future<void> _sendDirectEncryptedPayload({
    required Uint8List recipientId,
    required NoisePayloadType payloadType,
    required Uint8List payloadData,
  }) async {
    if (noiseSessionManager == null) {
      final msgType = payloadType == NoisePayloadType.voiceFrame
          ? MessageType.voiceFrame
          : MessageType.message;
      await meshEngine.sendDirectedPacket(
        recipientId: recipientId,
        type: msgType,
        payload: payloadData,
      );
      return;
    }

    if (noiseSessionManager!.hasSession(recipientId)) {
      final inner = Uint8List(1 + payloadData.length);
      inner[0] = payloadType.rawValue;
      inner.setRange(1, inner.length, payloadData);
      final ciphertext = await noiseSessionManager!.encryptPayload(recipientId, inner);
      await meshEngine.sendDirectedPacket(
        recipientId: recipientId,
        type: MessageType.noiseEncrypted,
        payload: ciphertext,
      );
    } else {
      final key = _hex(recipientId);
      final list = _pendingOutboundMessages.putIfAbsent(key, () => []);
      list.add(_PendingOutboundMessage(payloadType, payloadData));

      try {
        final step1 = await noiseSessionManager!.initiateHandshake(recipientId);
        await meshEngine.sendDirectedPacket(
          recipientId: recipientId,
          type: MessageType.noiseHandshake,
          payload: step1,
        );
      } catch (_) {}
    }
  }

  Future<void> _flushPendingOutboundMessages(Uint8List peerId) async {
    final key = _hex(peerId);
    final pending = _pendingOutboundMessages.remove(key);
    if (pending == null || pending.isEmpty || noiseSessionManager == null) return;

    for (final item in pending) {
      try {
        final inner = Uint8List(1 + item.data.length);
        inner[0] = item.type.rawValue;
        inner.setRange(1, inner.length, item.data);
        final ciphertext = await noiseSessionManager!.encryptPayload(peerId, inner);
        await meshEngine.sendDirectedPacket(
          recipientId: peerId,
          type: MessageType.noiseEncrypted,
          payload: ciphertext,
        );
      } catch (_) {}
    }
  }

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Executes an unconfirmed emergency panic wipe across all layers.
  Future<void> panicWipe({IdentityKeyPair? activeKeyPair}) async {
    await stop();
    _pendingOutboundMessages.clear();
    voiceMessageModule.clear();
    noiseProtocolModule?.clear();
    await panicZeroizationService.executeZeroization(activeKeyPair: activeKeyPair);
  }
}

class _PendingOutboundMessage {
  final NoisePayloadType type;
  final Uint8List data;
  _PendingOutboundMessage(this.type, this.data);
}


/// Persistent native BLE link adapter provider decoupled from ephemeral identity churn.
final nativeBleLinkAdapterProvider = Provider<NativeBleLinkAdapter>((ref) {
  final ble = NativeBleLinkAdapter();
  ref.onDispose(() {
    ble.dispose();
  });
  return ble;
});

/// Opt-in setting to enable Nostr internet relays alongside offline BLE mesh.
/// Default: false (ensures strict off-grid radio silence and zero IP address leakage).
final internetRelaysEnabledProvider = StateProvider<bool>((ref) => false);

/// Global provider for the transport port (defaults to NostrRelayAdapter on Web, MessageRouter on native).
final transportPortProvider = Provider<TransportPort>((ref) {
  final identity = ref.watch(identityProvider);
  final signingPubHex = identity.keyPair != null
      ? identity.keyPair!.signingPublicKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()
      : identity.peerIdHex.padRight(64, '0');

  final nostr = NostrRelayAdapter(
    relayUrls: const [
      'wss://relay.primal.net',
      'wss://offchain.pub',
      'wss://nos.lol',
    ],
    localPubkeyHex: signingPubHex,
  );

  if (kIsWeb) {
    ref.onDispose(() {
      nostr.stop();
    });
    return nostr;
  }

  final internetEnabled = ref.watch(internetRelaysEnabledProvider);
  final ble = ref.watch(nativeBleLinkAdapterProvider);
  final router = MessageRouter(
    bleTransport: ble,
    nostrTransport: nostr,
    policy: internetEnabled ? RoutingPolicy.dual : RoutingPolicy.bleOnly,
  );

  ref.onDispose(() {
    router.stop();
  });

  return router;
});

/// Global provider for the BitchatCoordinator.
final bitchatCoordinatorProvider = Provider<BitchatCoordinator?>((ref) {
  final identity = ref.watch(identityProvider);
  if (!identity.isInitialized || identity.keyPair == null) {
    return null;
  }

  final transport = ref.watch(transportPortProvider);
  final coordinator = BitchatCoordinator(
    localPeerId: identity.keyPair!.peerId,
    transportPort: transport,
    keyPair: identity.keyPair,
    onAnnouncementReceived: (announcement, senderPeerId, context) {
      final senderHex = senderPeerId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final safetyNumber = identity.keyPair?.computeSafetyNumber(announcement.noisePublicKey);
      ref.read(peersProvider.notifier).updatePresence(
        peerId: senderHex,
        nickname: announcement.nickname,
        phoneNumber: announcement.phoneNumber,
        phoneHash: announcement.phoneHash?.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        noisePublicKey: announcement.noisePublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        signingPublicKey: announcement.signingPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        hops: context.hops,
        medium: context.medium,
        safetyNumber: safetyNumber,
      );

    },
    onMessageReceived: (packet, context) {
      ref.read(timelineProvider.notifier).handleInboundPacket(
        packet,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: context.sourceLinkPeerId,
          medium: context.medium,
        ),
      );
    },
    onVoiceReceived: (packet, context) {
      ref.read(timelineProvider.notifier).handleInboundVoiceFrame(
        packet,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: context.sourceLinkPeerId,
          medium: context.medium,
        ),
      );
    },
  );

  coordinator.start();

  ref.onDispose(() {
    coordinator.stop();
  });
  return coordinator;
});
