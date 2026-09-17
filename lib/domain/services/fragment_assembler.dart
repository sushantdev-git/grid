import 'dart:typed_data';
import '../../infrastructure/codecs/fragment_codec.dart';

/// Represents an in-flight reassembly session for a fragmented packet.
class FragmentSession {
  final String fragmentIdHex;
  final int total;
  final DateTime createdAt;
  final Map<int, Uint8List> receivedChunks = {};

  FragmentSession({
    required this.fragmentIdHex,
    required this.total,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isComplete => receivedChunks.length == total;

  /// Progress fraction between 0.0 and 1.0.
  double get progress => total > 0 ? (receivedChunks.length / total) : 0.0;
}

/// Generic protocol service that tracks, stores, and reconstructs multi-packet
/// fragments received over BLE mesh or Nostr transports.
class FragmentAssembler {
  final Map<String, FragmentSession> _sessions = {};
  final Duration maxSessionAge;

  FragmentAssembler({
    this.maxSessionAge = const Duration(seconds: 45),
  });

  /// Total currently active assembly sessions.
  int get activeSessionCount => _sessions.length;

  /// Ingests a [FragmentPayload].
  ///
  /// Returns the complete reassembled [Uint8List] if this fragment completed
  /// the sequence, or `null` if more chunks are still pending.
  Uint8List? ingestFragment(FragmentPayload fragment) {
    pruneStaleSessions();

    final hexId = fragment.fragmentId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    if (fragment.total <= 0 || fragment.index >= fragment.total) {
      return null;
    }

    final session = _sessions.putIfAbsent(
      hexId,
      () => FragmentSession(
        fragmentIdHex: hexId,
        total: fragment.total,
      ),
    );

    // Guard against mismatching total for same ID
    if (session.total != fragment.total) {
      return null;
    }

    session.receivedChunks[fragment.index] = fragment.chunk;

    if (session.isComplete) {
      _sessions.remove(hexId);
      return _assemble(session);
    }

    return null;
  }

  /// Concatenates all chunks in strict 0..(total - 1) index order.
  Uint8List _assemble(FragmentSession session) {
    int totalBytes = 0;
    for (int i = 0; i < session.total; i++) {
      totalBytes += session.receivedChunks[i]?.length ?? 0;
    }

    final assembled = Uint8List(totalBytes);
    int offset = 0;

    for (int i = 0; i < session.total; i++) {
      final chunk = session.receivedChunks[i];
      if (chunk != null && chunk.isNotEmpty) {
        assembled.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
    }

    return assembled;
  }

  /// Returns current reassembly progress for a given [fragmentId] (0.0 to 1.0),
  /// or null if no session exists.
  double? getProgress(Uint8List fragmentId) {
    final hexId = fragmentId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _sessions[hexId]?.progress;
  }

  /// Cleans up incomplete assemblies older than [maxSessionAge].
  void pruneStaleSessions() {
    final now = DateTime.now();
    _sessions.removeWhere((_, session) => now.difference(session.createdAt) > maxSessionAge);
  }

  /// Clears all in-memory assembly state (e.g. on panic wipe).
  void clear() {
    _sessions.clear();
  }
}
