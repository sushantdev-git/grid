import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/enums/transport_medium.dart';
import '../../infrastructure/services/local_storage_service.dart';
import '../models/peer_model.dart';

/// State holding all discovered and verified peers on the network.
class PeersState {
  final Map<String, PeerModel> peers;

  const PeersState({this.peers = const {}});

  List<PeerModel> get allPeers => peers.values.toList()
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  List<PeerModel> get directPeers =>
      peers.values.where((p) => p.isDirectNeighbor).toList();

  List<PeerModel> get verifiedPeers =>
      peers.values.where((p) => p.isVerified).toList();

  PeerModel? getPeer(String peerId) => peers[peerId.toLowerCase()];

  PeersState copyWith({Map<String, PeerModel>? peers}) {
    return PeersState(peers: peers ?? this.peers);
  }
}

/// StateNotifier managing peer discovery, signal strengths, safety verification, and persistence.
class PeersNotifier extends StateNotifier<PeersState> {
  final LocalStorageService? storageService;

  PeersNotifier([PeersState? initial, this.storageService])
      : super(initial ?? const PeersState());

  /// Initializes by restoring previously discovered peers from persistent storage.
  Future<void> initialize() async {
    if (storageService == null) return;
    try {
      final loaded = await storageService!.loadPeers();
      if (loaded != null && loaded.isNotEmpty) {
        final map = <String, PeerModel>{};
        for (final p in loaded) {
          map[p.peerId.toLowerCase()] = p;
        }
        if (mounted) {
          state = state.copyWith(peers: map);
        }
      }
    } catch (_) {}
  }

  void _persistPeers() {
    if (storageService != null) {
      try {
        storageService!.savePeers(state.peers.values.toList());
      } catch (_) {}
    }
  }

  /// Updates or registers a peer presence announcement.
  /// Deduplicates across restarts by matching either peerId or noisePublicKey.
  void updatePresence({
    required String peerId,
    required String nickname,
    String? phoneHash,
    String? noisePublicKey,
    String? signingPublicKey,
    int? rssi,
    int hops = 0,
    TransportMedium medium = TransportMedium.bleMesh,
    String? safetyNumber,
  }) {
    final cleanId = peerId.toLowerCase();

    // Secondary deduplication: check by peerId first, then by noisePublicKey
    PeerModel? existing = state.peers[cleanId];
    String effectivePeerId = cleanId;

    if (existing == null && noisePublicKey != null && noisePublicKey.isNotEmpty) {
      final cleanNoise = noisePublicKey.toLowerCase();
      for (final entry in state.peers.entries) {
        if (entry.value.noisePublicKey != null &&
            entry.value.noisePublicKey!.toLowerCase() == cleanNoise) {
          existing = entry.value;
          effectivePeerId = entry.key;
          break;
        }
      }
    }

    final updated = PeerModel(
      peerId: effectivePeerId,
      nickname: nickname.trim().isNotEmpty ? nickname : (existing?.nickname ?? effectivePeerId.substring(0, 8)),
      phoneHash: phoneHash ?? existing?.phoneHash,
      noisePublicKey: noisePublicKey ?? existing?.noisePublicKey,
      signingPublicKey: signingPublicKey ?? existing?.signingPublicKey,
      rssi: rssi ?? existing?.rssi,
      hops: hops,
      lastSeen: DateTime.now(),
      isDirectNeighbor: hops == 0,
      isVerified: existing?.isVerified ?? false,
      medium: medium,
      safetyNumber: safetyNumber ?? existing?.safetyNumber,
    );

    final newMap = Map<String, PeerModel>.from(state.peers);
    newMap[effectivePeerId] = updated;
    state = state.copyWith(peers: newMap);
    _persistPeers();
  }

  /// Toggles whether a peer is marked as cryptographically verified via safety numbers.
  void toggleVerification(String peerId) {
    final cleanId = peerId.toLowerCase();
    final existing = state.peers[cleanId];
    if (existing == null) return;

    final updated = existing.copyWith(isVerified: !existing.isVerified);
    final newMap = Map<String, PeerModel>.from(state.peers);
    newMap[cleanId] = updated;
    state = state.copyWith(peers: newMap);
    _persistPeers();
  }

  /// Emergency panic wipe: clears all discovered peers from volatile memory and disk.
  void clear() {
    state = const PeersState(peers: {});
    if (storageService != null) {
      try {
        storageService!.deletePeers();
      } catch (_) {}
    }
  }
}

/// Global provider for network peers.
final peersProvider = StateNotifierProvider<PeersNotifier, PeersState>((ref) {
  final storage = ref.watch(localStorageServiceProvider);
  final notifier = PeersNotifier(null, storage);
  notifier.initialize();
  return notifier;
});
