import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/bitchat_coordinator.dart';
import '../../domain/entities/mesh_traffic_entry.dart';

/// Available filters for the mesh traffic telemetry stream.
enum MeshTrafficFilter {
  all,
  relayed,
  inbound,
  outbound,
  dropped,
}

/// State holding in-memory ring-buffer of mesh traffic entries, telemetry counters, and UI filters.
class MeshTrafficState {
  final List<MeshTrafficEntry> entries;
  final bool isPaused;
  final MeshTrafficFilter filter;
  final int totalCount;
  final int relayedCount;
  final int inboundCount;
  final int outboundCount;
  final int droppedCount;

  const MeshTrafficState({
    this.entries = const [],
    this.isPaused = false,
    this.filter = MeshTrafficFilter.all,
    this.totalCount = 0,
    this.relayedCount = 0,
    this.inboundCount = 0,
    this.outboundCount = 0,
    this.droppedCount = 0,
  });

  /// Returns entries filtered by the active [MeshTrafficFilter].
  List<MeshTrafficEntry> get filteredEntries {
    switch (filter) {
      case MeshTrafficFilter.all:
        return entries;
      case MeshTrafficFilter.relayed:
        return entries.where((e) => e.direction == MeshTrafficDirection.relayed).toList();
      case MeshTrafficFilter.inbound:
        return entries.where((e) => e.direction == MeshTrafficDirection.inbound).toList();
      case MeshTrafficFilter.outbound:
        return entries.where((e) => e.direction == MeshTrafficDirection.outbound).toList();
      case MeshTrafficFilter.dropped:
        return entries.where((e) => e.direction == MeshTrafficDirection.dropped).toList();
    }
  }

  MeshTrafficState copyWith({
    List<MeshTrafficEntry>? entries,
    bool? isPaused,
    MeshTrafficFilter? filter,
    int? totalCount,
    int? relayedCount,
    int? inboundCount,
    int? outboundCount,
    int? droppedCount,
  }) {
    return MeshTrafficState(
      entries: entries ?? this.entries,
      isPaused: isPaused ?? this.isPaused,
      filter: filter ?? this.filter,
      totalCount: totalCount ?? this.totalCount,
      relayedCount: relayedCount ?? this.relayedCount,
      inboundCount: inboundCount ?? this.inboundCount,
      outboundCount: outboundCount ?? this.outboundCount,
      droppedCount: droppedCount ?? this.droppedCount,
    );
  }
}

/// StateNotifier maintaining a bounded circular ring buffer of the last 200 MeshTrafficEntry events.
class MeshTrafficNotifier extends StateNotifier<MeshTrafficState> {
  static const int maxCapacity = 200;
  StreamSubscription<MeshTrafficEntry>? _subscription;

  MeshTrafficNotifier(Stream<MeshTrafficEntry>? stream) : super(const MeshTrafficState()) {
    if (stream != null) {
      bindStream(stream);
    }
  }

  /// Subscribes to the mesh engine's traffic telemetry broadcast stream.
  void bindStream(Stream<MeshTrafficEntry> stream) {
    _subscription?.cancel();
    _subscription = stream.listen(addEntry);
  }

  /// Appends an entry to the ring buffer (newest at index 0) and updates cumulative metrics.
  void addEntry(MeshTrafficEntry entry) {
    final total = state.totalCount + 1;
    final relayed = state.relayedCount + (entry.direction == MeshTrafficDirection.relayed ? 1 : 0);
    final inbound = state.inboundCount + (entry.direction == MeshTrafficDirection.inbound ? 1 : 0);
    final outbound = state.outboundCount + (entry.direction == MeshTrafficDirection.outbound ? 1 : 0);
    final dropped = state.droppedCount + (entry.direction == MeshTrafficDirection.dropped ? 1 : 0);

    if (state.isPaused) {
      state = state.copyWith(
        totalCount: total,
        relayedCount: relayed,
        inboundCount: inbound,
        outboundCount: outbound,
        droppedCount: dropped,
      );
      return;
    }

    final newEntries = List<MeshTrafficEntry>.from(state.entries)..insert(0, entry);
    if (newEntries.length > maxCapacity) {
      newEntries.removeLast();
    }

    state = state.copyWith(
      entries: newEntries,
      totalCount: total,
      relayedCount: relayed,
      inboundCount: inbound,
      outboundCount: outbound,
      droppedCount: dropped,
    );
  }

  /// Changes the active display filter.
  void setFilter(MeshTrafficFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// Pauses incoming additions to the visual buffer while continuing telemetry counting.
  void pause() {
    state = state.copyWith(isPaused: true);
  }

  /// Resumes visual updates from incoming traffic.
  void resume() {
    state = state.copyWith(isPaused: false);
  }

  /// Toggles pause/resume state.
  void togglePause() {
    state = state.copyWith(isPaused: !state.isPaused);
  }

  /// Clears all recorded entries and resets telemetry counters.
  void clear() {
    state = state.copyWith(
      entries: const [],
      totalCount: 0,
      relayedCount: 0,
      inboundCount: 0,
      outboundCount: 0,
      droppedCount: 0,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Global provider for the MeshTrafficNotifier.
final meshTrafficProvider = StateNotifierProvider<MeshTrafficNotifier, MeshTrafficState>((ref) {
  final coordinator = ref.watch(bitchatCoordinatorProvider);
  final notifier = MeshTrafficNotifier(coordinator?.meshEngine.trafficStream);
  return notifier;
});
