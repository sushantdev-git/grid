import 'dart:typed_data';

import '../../core/utils/message_padding.dart';
import '../entities/identity_key_pair.dart';
import 'noise_cipher_state.dart';
import 'noise_handshake_state.dart';

/// Represents an established, secure end-to-end encrypted session with a mesh peer.
class NoiseSession {
  final Uint8List peerId;
  final Uint8List remoteNoisePublicKey;
  final NoiseCipherState sendCipher;
  final NoiseCipherState receiveCipher;
  final DateTime establishedAt;
  DateTime lastActivity;

  NoiseSession({
    required this.peerId,
    required this.remoteNoisePublicKey,
    required this.sendCipher,
    required this.receiveCipher,
    DateTime? establishedAt,
  })  : establishedAt = establishedAt ?? DateTime.now(),
        lastActivity = establishedAt ?? DateTime.now();

  /// Encrypts an outgoing transport message using ChaCha20-Poly1305 with PKCS#7 padding
  /// and an extracted 4-byte wire nonce.
  Future<Uint8List> encryptMessage(Uint8List plaintext, {bool pad = true}) async {
    final payloadToEncrypt = pad ? MessagePadding.padToBucket(plaintext) : plaintext;
    final ciphertext = await sendCipher.encrypt(payloadToEncrypt);
    lastActivity = DateTime.now();
    return ciphertext;
  }

  /// Decrypts an incoming transport ciphertext with sliding-window replay protection
  /// and strips PKCS#7 padding.
  Future<Uint8List> decryptMessage(Uint8List ciphertext, {bool unpad = true}) async {
    final decryptedPadded = await receiveCipher.decrypt(ciphertext);
    lastActivity = DateTime.now();
    return unpad ? MessagePadding.unpad(decryptedPadded) : decryptedPadded;
  }

  /// Zeroizes session keys and state.
  void clear() {
    sendCipher.clearSensitiveData();
    receiveCipher.clearSensitiveData();
  }
}

/// Result returned from processing an incoming handshake message.
class HandshakeProcessingResult {
  final Uint8List? responsePayload;
  final bool isSessionEstablished;
  final NoiseSession? session;
  final Uint8List? decryptedHandshakeData;

  const HandshakeProcessingResult({
    this.responsePayload,
    required this.isSessionEstablished,
    this.session,
    this.decryptedHandshakeData,
  });
}

/// Coordinates ephemeral Noise_XX handshakes and manages active E2EE peer sessions.
class NoiseSessionManager {
  final IdentityKeyPair localIdentity;
  final Duration handshakeTimeout;

  final Map<String, NoiseSession> _sessions = {};
  final Map<String, NoiseHandshakeState> _pendingHandshakes = {};
  final Map<String, DateTime> _handshakeTimestamps = {};

  NoiseSessionManager({
    required this.localIdentity,
    this.handshakeTimeout = const Duration(seconds: 30),
  });

  /// Initiates a new Noise_XX handshake with the target peer.
  /// Returns the step 1 handshake packet payload to transmit.
  Future<Uint8List> initiateHandshake(Uint8List peerId, {Uint8List? initialPayload}) async {
    final key = _hex(peerId);

    // Cancel any stale handshake
    _pendingHandshakes[key]?.symmetricState.clear();

    final handshake = NoiseHandshakeState(
      role: NoiseRole.initiator,
      localStaticKeyPair: localIdentity.noiseKeyPair,
    );

    final step1Message = await handshake.writeMessage(payload: initialPayload);
    _pendingHandshakes[key] = handshake;
    _handshakeTimestamps[key] = DateTime.now();

    return step1Message;
  }

  /// Handles incoming handshake bytes for a peer.
  /// Seamlessly steps through Initiator or Responder roles of the Noise_XX pattern.
  Future<HandshakeProcessingResult> handleIncomingHandshakeMessage(
    Uint8List peerId,
    Uint8List messageBytes,
  ) async {
    final key = _hex(peerId);

    // Check for expired pending handshake
    final timestamp = _handshakeTimestamps[key];
    if (timestamp != null && DateTime.now().difference(timestamp) > handshakeTimeout) {
      _pendingHandshakes[key]?.symmetricState.clear();
      _pendingHandshakes.remove(key);
      _handshakeTimestamps.remove(key);
    }

    final pending = _pendingHandshakes[key];

    if (pending == null) {
      // Step 1: We are the Responder receiving message 1 (-> e)
      final responder = NoiseHandshakeState(
        role: NoiseRole.responder,
        localStaticKeyPair: localIdentity.noiseKeyPair,
      );

      final decryptedData = await responder.readMessage(messageBytes);
      final step2Response = await responder.writeMessage();

      _pendingHandshakes[key] = responder;
      _handshakeTimestamps[key] = DateTime.now();

      return HandshakeProcessingResult(
        responsePayload: step2Response,
        isSessionEstablished: false,
        decryptedHandshakeData: decryptedData,
      );
    } else {
      if (pending.isInitiator && pending.currentStep == 2) {
        // Step 2: We are the Initiator reading message 2 (<- e, ee, s, es)
        final decryptedData = await pending.readMessage(messageBytes);

        // Then writing message 3 (-> s, se)
        final step3Response = await pending.writeMessage();

        // Handshake finished!
        final result = pending.finishHandshake();
        final session = NoiseSession(
          peerId: peerId,
          remoteNoisePublicKey: result.remoteStaticPublicKey,
          sendCipher: result.sendCipher,
          receiveCipher: result.receiveCipher,
        );

        _sessions[key] = session;
        _pendingHandshakes.remove(key);
        _handshakeTimestamps.remove(key);

        return HandshakeProcessingResult(
          responsePayload: step3Response,
          isSessionEstablished: true,
          session: session,
          decryptedHandshakeData: decryptedData,
        );
      } else if (!pending.isInitiator && pending.currentStep == 3) {
        // Step 3: We are the Responder reading message 3 (-> s, se)
        final decryptedData = await pending.readMessage(messageBytes);

        // Handshake finished!
        final result = pending.finishHandshake();
        final session = NoiseSession(
          peerId: peerId,
          remoteNoisePublicKey: result.remoteStaticPublicKey,
          sendCipher: result.sendCipher,
          receiveCipher: result.receiveCipher,
        );

        _sessions[key] = session;
        _pendingHandshakes.remove(key);
        _handshakeTimestamps.remove(key);

        return HandshakeProcessingResult(
          responsePayload: null, // No further message needed
          isSessionEstablished: true,
          session: session,
          decryptedHandshakeData: decryptedData,
        );
      } else {
        throw StateError('Invalid handshake state for step ${pending.currentStep}');
      }
    }
  }

  /// Encrypts application payload for an established peer session.
  Future<Uint8List> encryptPayload(
    Uint8List peerId,
    Uint8List plaintext, {
    bool pad = true,
  }) async {
    final session = getSession(peerId);
    if (session == null) {
      throw StateError('No established Noise session for peer ${_hex(peerId)}');
    }
    return session.encryptMessage(plaintext, pad: pad);
  }

  /// Decrypts transport ciphertext from an established peer session.
  Future<Uint8List> decryptPayload(
    Uint8List peerId,
    Uint8List ciphertext, {
    bool unpad = true,
  }) async {
    final session = getSession(peerId);
    if (session == null) {
      throw StateError('No established Noise session for peer ${_hex(peerId)}');
    }
    return session.decryptMessage(ciphertext, unpad: unpad);
  }

  /// Looks up an active session for the given peer ID.
  NoiseSession? getSession(Uint8List peerId) => _sessions[_hex(peerId)];

  /// Returns true if an encrypted session is actively established with the peer.
  bool hasSession(Uint8List peerId) => _sessions.containsKey(_hex(peerId));

  /// Returns true if a handshake is currently pending with the peer.
  bool hasPendingHandshake(Uint8List peerId) => _pendingHandshakes.containsKey(_hex(peerId));

  /// Discards and zeroizes a specific peer session.
  void removeSession(Uint8List peerId) {
    final key = _hex(peerId);
    _sessions[key]?.clear();
    _sessions.remove(key);
    _pendingHandshakes[key]?.symmetricState.clear();
    _pendingHandshakes.remove(key);
    _handshakeTimestamps.remove(key);
  }

  /// Emergency panic wipe: zeroizes all cryptographic sessions and wipes all in-flight handshakes.
  void clearAllSessions() {
    for (final session in _sessions.values) {
      session.clear();
    }
    _sessions.clear();

    for (final pending in _pendingHandshakes.values) {
      pending.symmetricState.clear();
    }
    _pendingHandshakes.clear();
    _handshakeTimestamps.clear();
  }

  String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
