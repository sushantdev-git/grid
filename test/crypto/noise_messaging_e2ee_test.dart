import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/application/bitchat_coordinator.dart';
import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/entities/identity_key_pair.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/infrastructure/adapters/simulated_link_adapter.dart';
import 'package:grid/infrastructure/codecs/voice_frame_codec.dart';

void main() {
  group('Noise_XX End-to-End Cryptographic Messaging & Voice Integration Tests', () {
    late SimulatedMeshNetwork network;
    late IdentityKeyPair aliceKeys;
    late IdentityKeyPair bobKeys;

    late SimulatedLinkAdapter aliceAdapter;
    late SimulatedLinkAdapter bobAdapter;

    late BitchatCoordinator aliceCoordinator;
    late BitchatCoordinator bobCoordinator;

    late List<BitchatPacket> bobReceivedMessages;
    late List<BitchatPacket> bobReceivedVoice;
    late List<BitchatPacket> aliceReceivedMessages;

    setUp(() async {
      network = SimulatedMeshNetwork(
        minLatency: const Duration(milliseconds: 1),
        maxLatency: const Duration(milliseconds: 3),
      );

      aliceKeys = await IdentityKeyPair.generate(nickname: 'Alice');
      bobKeys = await IdentityKeyPair.generate(nickname: 'Bob');

      aliceAdapter = SimulatedLinkAdapter(
        nodeId: aliceKeys.peerIdHex,
        network: network,
      );
      bobAdapter = SimulatedLinkAdapter(
        nodeId: bobKeys.peerIdHex,
        network: network,
      );

      bobReceivedMessages = [];
      bobReceivedVoice = [];
      aliceReceivedMessages = [];

      aliceCoordinator = BitchatCoordinator(
        localPeerId: aliceKeys.peerId,
        transportPort: aliceAdapter,
        keyPair: aliceKeys,
        onMessageReceived: (packet, context) {
          aliceReceivedMessages.add(packet);
        },
      );

      bobCoordinator = BitchatCoordinator(
        localPeerId: bobKeys.peerId,
        transportPort: bobAdapter,
        keyPair: bobKeys,
        onMessageReceived: (packet, context) {
          bobReceivedMessages.add(packet);
        },
        onVoiceReceived: (packet, context) {
          bobReceivedVoice.add(packet);
        },
      );

      await aliceCoordinator.start();
      await bobCoordinator.start();

      // Establish simulated radio link
      network.addLink(aliceKeys.peerIdHex, bobKeys.peerIdHex);
    });

    tearDown(() async {
      await aliceCoordinator.stop();
      await bobCoordinator.stop();
      aliceAdapter.dispose();
      bobAdapter.dispose();
      network.clear();
    });

    test('Automatic 3-way Noise_XX handshake and encrypted message exchange', () async {
      const secretMessage = 'Top secret off-grid message for Bob!';
      final messageBytes = Uint8List.fromList(utf8.encode(secretMessage));

      // Alice sends direct encrypted message to Bob before any handshake exists
      await aliceCoordinator.sendDirectEncryptedMessage(
        recipientId: bobKeys.peerId,
        plaintext: messageBytes,
      );

      // Wait for handshake and message delivery (up to 1s)
      for (int i = 0; i < 50 && bobReceivedMessages.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // Verify that both Alice and Bob established Noise sessions
      expect(aliceCoordinator.noiseSessionManager!.hasSession(bobKeys.peerId), isTrue);
      expect(bobCoordinator.noiseSessionManager!.hasSession(aliceKeys.peerId), isTrue);

      // Verify that Bob received and decrypted the message
      expect(bobReceivedMessages.length, equals(1));
      final received = bobReceivedMessages.first;
      expect(received.type, equals(MessageType.noiseEncrypted));
      expect(utf8.decode(received.payload), equals(secretMessage));
      expect(received.senderId, equals(aliceKeys.peerId));

      // Bob sends an encrypted reply back to Alice
      const secretReply = 'Acknowledged Alice, transmission secured.';
      await bobCoordinator.sendDirectEncryptedMessage(
        recipientId: aliceKeys.peerId,
        plaintext: Uint8List.fromList(utf8.encode(secretReply)),
      );

      for (int i = 0; i < 50 && aliceReceivedMessages.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(aliceReceivedMessages.length, equals(1));
      final aliceMsg = aliceReceivedMessages.first;
      expect(aliceMsg.type, equals(MessageType.noiseEncrypted));
      expect(utf8.decode(aliceMsg.payload), equals(secretReply));
      expect(aliceMsg.senderId, equals(bobKeys.peerId));
    });

    test('Encrypted Push-to-Talk voice note transmission over Noise_XX', () async {
      final voicePayload = VoiceFramePayload(
        durationMs: 1500,
        codec: VoiceCodecType.aacLc,
        waveform: Uint8List.fromList([10, 50, 100, 80, 20]),
        audioData: Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]),
      );
      final voiceBytes = VoiceFrameCodec.encode(voicePayload);

      // Alice sends direct encrypted voice note to Bob
      await aliceCoordinator.sendDirectEncryptedVoice(
        recipientId: bobKeys.peerId,
        voiceFrameBytes: voiceBytes,
      );

      for (int i = 0; i < 50 && bobReceivedVoice.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // Bob receives the encrypted voice frame
      expect(bobReceivedVoice.length, equals(1));
      final receivedVoice = bobReceivedVoice.first;
      expect(receivedVoice.type, equals(MessageType.noiseEncrypted));

      final decodedPayload = VoiceFrameCodec.decode(receivedVoice.payload);
      expect(decodedPayload, isNotNull);
      expect(decodedPayload!.durationMs, equals(1500));
      expect(decodedPayload.waveform, equals(voicePayload.waveform));
      expect(decodedPayload.audioData, equals(voicePayload.audioData));
    });

    test('Panic wipe zeroizes active Noise sessions on coordinator', () async {
      // First establish session
      await aliceCoordinator.sendDirectEncryptedMessage(
        recipientId: bobKeys.peerId,
        plaintext: Uint8List.fromList(utf8.encode('Pre-wipe handshake')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(aliceCoordinator.noiseSessionManager!.hasSession(bobKeys.peerId), isTrue);

      // Execute panic wipe
      await aliceCoordinator.panicWipe(activeKeyPair: aliceKeys);

      // Active session must be zeroized and removed
      expect(aliceCoordinator.noiseSessionManager!.hasSession(bobKeys.peerId), isFalse);
    });
  });
}
