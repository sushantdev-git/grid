import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

import '../../infrastructure/codecs/binary_protocol_codec.dart';
import '../entities/bitchat_packet.dart';
import '../enums/message_type.dart';
import '../ports/transport_port.dart';
import 'feature_registry.dart';
import 'seen_packet_cache.dart';

/// Core routing engine implementing BitChat controlled flooding across multi-hop radio meshes.
///
/// Features:
/// - Deduplication LRU Seen-Set (1,000 packets, 5-minute TTL)
/// - Adaptive TTL Clamping (7 -> 5 in high-density topologies)
/// - Randomized Relay Jitter (10ms - 220ms) with duplicate suppression
/// - Split-Horizon filtering (never reflect packets back on the incoming link)
/// - Degree-based fanout subsetting
/// - Clean separation from protocol features via [ProtocolFeatureRegistry]
class MeshEngine {
  final Uint8List localPeerId;
  final TransportPort transportPort;
  final ProtocolFeatureRegistry featureRegistry;
  final SeenPacketCache seenCache;

  final int initialTtl;
  final int clampedTtl;
  final int highDensityThreshold;
  final Duration minJitter;
  final Duration maxJitter;
  final Random _random;
  final TokenBucketRateLimiter rateLimiter;

  StreamSubscription<TransportPacketEvent>? _transportSubscription;
  final Map<String, Timer> _pendingRelays = {};
  bool _isRunning = false;

  MeshEngine({
    required this.localPeerId,
    required this.transportPort,
    required this.featureRegistry,
    SeenPacketCache? seenCache,
    this.initialTtl = 7,
    this.clampedTtl = 5,
    this.highDensityThreshold = 6,
    this.minJitter = const Duration(milliseconds: 10),
    this.maxJitter = const Duration(milliseconds: 220),
    Random? random,
    TokenBucketRateLimiter? rateLimiter,
  })  : seenCache = seenCache ?? SeenPacketCache(),
        _random = random ?? Random(),
        rateLimiter = rateLimiter ?? TokenBucketRateLimiter();

  bool get isRunning => _isRunning;
  int get pendingRelayCount => _pendingRelays.length;

  /// Starts the mesh engine and begins listening for inbound transport packets.
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    await transportPort.start();

    _transportSubscription = transportPort.incomingPackets.listen(
      _handleInboundEvent,
      onError: (error, stackTrace) {
        // Log transport stream error without crashing engine
      },
    );
  }

  /// Stops the mesh engine, cancels pending relay timers, and halts subscriptions.
  Future<void> stop() async {
    _isRunning = false;
    await _transportSubscription?.cancel();
    _transportSubscription = null;
    cancelAllPendingRelays();
  }

  /// Computes a deterministic 16-byte hex hash for packet deduplication:
  /// `SHA-256(senderId + timestamp + type + payload)[0..16]`.
  String computePacketId(BitchatPacket packet) {
    final tsBytes = Uint8List(8);
    ByteData.sublistView(tsBytes).setUint64(0, packet.timestamp, Endian.big);

    final input = Uint8List(
      packet.senderId.length + tsBytes.length + 1 + packet.payload.length,
    );
    int offset = 0;

    input.setRange(offset, offset + packet.senderId.length, packet.senderId);
    offset += packet.senderId.length;

    input.setRange(offset, offset + tsBytes.length, tsBytes);
    offset += tsBytes.length;

    input[offset] = packet.type.rawValue;
    offset += 1;

    input.setRange(offset, offset + packet.payload.length, packet.payload);

    final digest = crypto.sha256.convert(input).bytes;
    return digest
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Originates and broadcasts a new packet across the mesh.
  Future<void> sendBroadcastPacket({
    required MessageType type,
    required Uint8List payload,
    List<Uint8List>? route,
    Uint8List? signature,
  }) async {
    final packet = BitchatPacket(
      type: type,
      ttl: initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: localPeerId,
      recipientId: null,
      route: route,
      payload: payload,
      signature: signature,
    );

    await broadcastRawPacket(packet);
  }

  /// Originates and transmits a directed packet toward a specific recipient.
  Future<void> sendDirectedPacket({
    required Uint8List recipientId,
    required MessageType type,
    required Uint8List payload,
    List<Uint8List>? route,
    Uint8List? signature,
  }) async {
    final packet = BitchatPacket(
      type: type,
      ttl: initialTtl,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: localPeerId,
      recipientId: recipientId,
      route: route,
      payload: payload,
      signature: signature,
    );

    await broadcastRawPacket(packet);
  }

  /// Transmits a pre-formed [BitchatPacket] over the transport port.
  Future<void> broadcastRawPacket(BitchatPacket packet) async {
    final packetId = computePacketId(packet);

    // Register into local seen cache so we never echo our own packets back
    seenCache.checkAndAdd(packetId);

    final wireBytes = BinaryProtocolCodec.encode(packet);
    if (wireBytes == null) {
      throw StateError('Failed to serialize packet for broadcast');
    }

    await transportPort.sendBroadcast(wireBytes);
  }

  /// Internal handler for raw inbound transport packet events.
  Future<void> _handleInboundEvent(TransportPacketEvent event) async {
    final packet = BinaryProtocolCodec.decode(event.packetBytes);
    if (packet == null) {
      return; // Malformed packet discarded
    }

    // 0. Token-Bucket Rate Limiter Check (Vampire DoS & Flood Protection)
    final rateLimitKey = event.sourcePeerId.isNotEmpty
        ? event.sourcePeerId
        : packet.senderId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (!rateLimiter.allow(rateLimitKey)) {
      return; // Exceeded rate limit, drop packet to preserve battery
    }

    final packetId = computePacketId(packet);

    // 1. Deduplication LRU Seen-Set Check
    final isNewPacket = seenCache.checkAndAdd(packetId);
    if (!isNewPacket) {
      // Incoming duplicate! Cancel any pending relay timer for this packetId (Duplicate suppression!)
      _cancelPendingRelay(packetId);
      return;
    }

    // 2. Local Delivery (Is this packet for us?)
    final isForUs = packet.recipientId == null ||
        _bytesEqual(packet.recipientId!, localPeerId) ||
        packet.type == MessageType.courierEnvelope;
    if (isForUs) {
      final hops = max(0, initialTtl - packet.ttl);
      final context = PacketContext(
        sourceLinkPeerId: event.sourcePeerId,
        medium: event.medium,
        hops: hops,
      );
      await featureRegistry.dispatch(packet, context);
    }

    // 3. Controlled Flooding Relay Evaluation
    _evaluateAndScheduleRelay(packet, packetId, event.sourcePeerId);
  }

  /// Evaluates whether an inbound packet should be relayed and schedules randomized jitter.
  void _evaluateAndScheduleRelay(
    BitchatPacket packet,
    String packetId,
    String incomingLinkPeerId,
  ) {
    // Courier envelopes are handled via DTN store-and-forward, not broadcast flooding
    if (packet.type == MessageType.courierEnvelope) {
      return;
    }

    // Condition A: Packet originated from us -> do NOT relay
    if (_bytesEqual(packet.senderId, localPeerId)) {
      return;
    }

    // Condition B: Reached maximum hop life (TTL <= 1) -> do NOT relay
    if (packet.ttl <= 1) {
      return;
    }

    // Condition C: Directed packet reached its final recipient -> do NOT relay
    if (packet.recipientId != null && _bytesEqual(packet.recipientId!, localPeerId)) {
      return;
    }

    // Condition D: Split-Horizon rule -> target links must exclude the arrival link
    final connectedPeers = transportPort.connectedPeerIds;
    final candidates = connectedPeers.where((peer) => peer != incomingLinkPeerId).toList();
    if (candidates.isEmpty) {
      return; // Nowhere to forward
    }

    // 4. Adaptive TTL Clamping
    int nextTtl = packet.ttl - 1;
    if (connectedPeers.length >= highDensityThreshold && nextTtl > clampedTtl) {
      nextTtl = clampedTtl;
    }

    // 5. Degree-Based Fanout Subsetting
    final targetPeers = _selectFanoutTargets(candidates, packetId);

    // 6. Randomized Relay Jitter (10ms - 220ms)
    final jitterMillis = minJitter.inMilliseconds +
        _random.nextInt(max(1, maxJitter.inMilliseconds - minJitter.inMilliseconds));
    final jitterDuration = Duration(milliseconds: jitterMillis);

    // Schedule relay timer
    _pendingRelays[packetId] = Timer(jitterDuration, () async {
      _pendingRelays.remove(packetId);

      final relayedPacket = packet.copyWith(ttl: nextTtl);
      final wireBytes = BinaryProtocolCodec.encode(relayedPacket);
      if (wireBytes == null) return;

      if (targetPeers.length == candidates.length) {
        // Forwarding to all candidates (or broadcast with split-horizon)
        await transportPort.sendBroadcast(wireBytes);
      } else {
        // Forwarding to fanout subset
        for (final target in targetPeers) {
          await transportPort.sendDirected(target, wireBytes);
        }
      }
    });
  }

  /// Selects a deterministic pseudo-random subset of peers when network density is high.
  List<String> _selectFanoutTargets(List<String> candidates, String packetId) {
    if (candidates.length <= 4) {
      return candidates; // In sparse topologies, use full fanout
    }

    // Subsetting: targetSize ≈ ceil(log2(degree)) + 1
    final targetSize = (log(candidates.length) / ln2).ceil() + 1;
    final subset = List<String>.from(candidates);
    
    // Deterministic shuffle seeded by packetId hash
    final seed = packetId.hashCode;
    final prng = Random(seed);
    subset.shuffle(prng);

    return subset.take(targetSize).toList();
  }

  void _cancelPendingRelay(String packetId) {
    final timer = _pendingRelays.remove(packetId);
    timer?.cancel();
  }

  /// Cancels all pending jitter relays.
  void cancelAllPendingRelays() {
    for (final timer in _pendingRelays.values) {
      timer.cancel();
    }
    _pendingRelays.clear();
  }

  /// Panic wipe: clears seen cache, cancels timers, and wipes state.
  void clear() {
    cancelAllPendingRelays();
    seenCache.clear();
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Token-bucket rate limiter defending against high-frequency RF flooding and Vampire DoS attacks.
class TokenBucketRateLimiter {
  final double capacity;
  final double fillRate;
  final Map<String, _Bucket> _buckets = {};

  TokenBucketRateLimiter({this.capacity = 20.0, this.fillRate = 10.0});

  bool allow(String key) {
    if (_buckets.length > 500) {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
      _buckets.removeWhere((_, b) => b.lastRefill.isBefore(cutoff));
    }
    final bucket = _buckets.putIfAbsent(
      key,
      () => _Bucket(capacity: capacity, fillRate: fillRate),
    );
    return bucket.consume();
  }

  void clear() => _buckets.clear();
}

class _Bucket {
  double tokens;
  DateTime lastRefill;
  final double capacity;
  final double fillRate;

  _Bucket({required this.capacity, required this.fillRate})
      : tokens = capacity,
        lastRefill = DateTime.now();

  bool consume() {
    final now = DateTime.now();
    final elapsedSec = now.difference(lastRefill).inMilliseconds / 1000.0;
    tokens = min(capacity, tokens + elapsedSec * fillRate);
    lastRefill = now;
    if (tokens >= 1.0) {
      tokens -= 1.0;
      return true;
    }
    return false;
  }
}
