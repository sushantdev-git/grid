import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/infrastructure/codecs/voice_frame_codec.dart';
import 'package:grid/infrastructure/services/local_storage_service.dart';
import 'package:grid/infrastructure/services/voice_service.dart';
import 'package:grid/presentation/models/chat_message.dart';
import 'package:grid/presentation/state/identity_state.dart';
import 'package:grid/presentation/state/timeline_notifier.dart';
import 'package:grid/presentation/widgets/message_bubble.dart';
import 'package:grid/presentation/widgets/voice_bubble_content.dart';
import 'package:grid/presentation/views/chat_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatMessage Voice Extensions', () {
    test('isVoice returns true when mediaPath or mediaDurationMs is present', () {
      final msgWithAudio = ChatMessage(
        id: '1',
        senderId: 'alice',
        senderNickname: 'Alice',
        content: '[Voice Note: 3.5s]',
        timestamp: DateTime.now(),
        isOutgoing: true,
        channelOrPeerId: '#mesh',
        mediaPath: '/path/to/voice.m4a',
        mediaDurationMs: 3500,
        waveformSamples: [10, 20, 30],
      );

      expect(msgWithAudio.isVoice, isTrue);
      expect(msgWithAudio.mediaDurationMs, equals(3500));
      expect(msgWithAudio.waveformSamples, equals([10, 20, 30]));

      final regularMsg = ChatMessage(
        id: '2',
        senderId: 'bob',
        senderNickname: 'Bob',
        content: 'Hello world',
        timestamp: DateTime.now(),
        isOutgoing: false,
        channelOrPeerId: '#mesh',
      );

      expect(regularMsg.isVoice, isFalse);
    });

    test('serializes and deserializes media fields to and from JSON', () {
      final original = ChatMessage(
        id: 'voice_123',
        senderId: 'peer_abc',
        senderNickname: 'Charlie',
        content: '[Voice Note: 5.0s]',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1720000000000),
        isOutgoing: false,
        channelOrPeerId: 'peer_abc',
        mediaPath: '/data/user/0/grid/voice_123.m4a',
        mediaDurationMs: 5000,
        waveformSamples: [255, 128, 64, 32],
      );

      final json = original.toJson();
      expect(json['mediaPath'], equals('/data/user/0/grid/voice_123.m4a'));
      expect(json['mediaDurationMs'], equals(5000));
      expect(json['waveformSamples'], equals([255, 128, 64, 32]));

      final restored = ChatMessage.fromJson(json);
      expect(restored.isVoice, isTrue);
      expect(restored.mediaPath, equals(original.mediaPath));
      expect(restored.mediaDurationMs, equals(5000));
      expect(restored.waveformSamples, equals([255, 128, 64, 32]));
    });
  });

  group('VoiceService & Storage', () {
    test('startRecording and stopRecording produce result in test mode', () async {
      final service = VoiceService(testMode: true);

      expect(service.isRecording, isFalse);
      final started = await service.startRecording();
      expect(started, isTrue);
      expect(service.isRecording, isTrue);

      final result = await service.stopRecording();
      expect(result, isNotNull);
      expect(result!.filePath, contains('test_voice'));
      expect(result.durationMs, greaterThanOrEqualTo(0));
      expect(result.waveform.length, equals(24));
      expect(result.audioBytes.isNotEmpty, isTrue);
      expect(service.isRecording, isFalse);
    });

    test('cancelRecording discards active session', () async {
      final service = VoiceService(testMode: true);
      await service.startRecording();
      expect(service.isRecording, isTrue);

      await service.cancelRecording();
      expect(service.isRecording, isFalse);
    });

    test('saveReceivedVoiceNote and wipeAllVoiceNotes', () async {
      final tempDir = Directory.systemTemp.createTempSync('grid_voice_test_');
      final service = VoiceService(testMode: false);

      // Create dummy audio note
      final dummyDir = Directory('${tempDir.path}/grid_voice_notes');
      dummyDir.createSync(recursive: true);
      final testFile = File('${dummyDir.path}/rec_dummy.m4a');
      testFile.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5, 6]));

      expect(testFile.existsSync(), isTrue);

      // Forensic wipe
      await service.wipeAllVoiceNotes();

      // Clean up temp
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('TimelineNotifier PTT Voice Integration', () {
    late Directory testDir;
    late LocalStorageService storage;
    late ProviderContainer container;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('grid_timeline_voice_');
      storage = LocalStorageService(customDir: testDir);

      container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          voiceServiceProvider.overrideWithValue(VoiceService(testMode: true)),
        ],
      );

      await container.read(identityProvider.notifier).initialize(nickname: 'TestHero');
    });

    tearDown(() async {
      container.dispose();
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    });

    test('sendVoiceMessage adds playable voice note to timeline', () async {
      final notifier = container.read(timelineProvider.notifier);

      final waveform = Uint8List.fromList([10, 50, 100, 200, 150, 80]);
      final audioBytes = Uint8List.fromList(List.generate(200, (i) => i % 256));

      await notifier.sendVoiceMessage(
        channelOrPeerId: '#mesh',
        audioPath: '/tmp/my_recording.m4a',
        durationMs: 2500,
        waveform: waveform,
        audioBytes: audioBytes,
      );

      final messages = container.read(timelineProvider).getMessages('#mesh');
      expect(messages.length, equals(1));

      final msg = messages.first;
      expect(msg.isVoice, isTrue);
      expect(msg.mediaPath, equals('/tmp/my_recording.m4a'));
      expect(msg.mediaDurationMs, equals(2500));
      expect(msg.isOutgoing, isTrue);
      expect(msg.content, contains('2.5s'));
    });

    test('handleInboundVoiceFrame decodes and saves incoming voice memo', () async {
      final notifier = container.read(timelineProvider.notifier);

      final originalPayload = VoiceFramePayload(
        durationMs: 4100,
        codec: VoiceCodecType.aacLc,
        waveform: Uint8List.fromList([20, 60, 180, 220]),
        audioData: Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]),
      );
      final wireBytes = VoiceFrameCodec.encode(originalPayload);

      final senderId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final packet = BitchatPacket(
        version: 1,
        type: MessageType.voiceFrame,
        ttl: 7,
        timestamp: 1726000000000,
        senderId: senderId,
        payload: wireBytes,
      );

      await notifier.handleInboundVoiceFrame(
        packet,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: 'neighbor_1',
          medium: TransportMedium.bleMesh,
        ),
      );

      final messages = container.read(timelineProvider).getMessages('#mesh');
      expect(messages.length, equals(1));

      final msg = messages.first;
      expect(msg.isVoice, isTrue);
      expect(msg.isOutgoing, isFalse);
      expect(msg.mediaDurationMs, equals(4100));
      expect(msg.content, contains('4.1s'));
      expect(msg.waveformSamples, equals([20, 60, 180, 220]));
    });
  });

  group('Voice UI Widgets', () {
    testWidgets('VoiceBubbleContent renders waveform and play button', (tester) async {
      final msg = ChatMessage(
        id: 'voice_widget_test',
        senderId: 'peer_1',
        senderNickname: 'Alice',
        content: '[Voice Note: 3.0s]',
        timestamp: DateTime.now(),
        isOutgoing: false,
        channelOrPeerId: '#mesh',
        mediaPath: '/tmp/test_widget.m4a',
        mediaDurationMs: 3000,
        waveformSamples: [50, 120, 200, 255, 180, 90, 40],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceServiceProvider.overrideWithValue(VoiceService(testMode: true)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: msg,
                position: BubblePosition.single,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify VoiceBubbleContent is rendered
      expect(find.byType(VoiceBubbleContent), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('00:03'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);

      // Tap Play button
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
    });

    test('cancelRecording allows clean subsequent startRecording without errors', () async {
      final service = VoiceService(testMode: true);
      expect(await service.startRecording(), isTrue);
      expect(service.isRecording, isTrue);

      await service.cancelRecording();
      expect(service.isRecording, isFalse);

      // Subsequent recording should start immediately without permission errors
      expect(await service.hasPermission(), isTrue);
      expect(await service.startRecording(), isTrue);
      expect(service.isRecording, isTrue);

      final result = await service.stopRecording();
      expect(result, isNotNull);
      expect(service.isRecording, isFalse);
    });

    testWidgets('ChatScreen shows Cancel and Send buttons when recording and can send or cancel', (tester) async {
      final storage = LocalStorageService(customDir: Directory.systemTemp.createTempSync('grid_ptt_cs_'));
      final voice = VoiceService(testMode: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            voiceServiceProvider.overrideWithValue(voice),
          ],
          child: const MaterialApp(
            home: ChatScreen(channelOrPeerId: '#mesh'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find mic button and tap it to start recording
      final micFinder = find.byIcon(Icons.mic_none_rounded);
      expect(micFinder, findsOneWidget);
      await tester.tap(micFinder);
      await tester.pump();

      // Verify recording composer is displayed with Cancel and Send buttons
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

      // Tap Cancel button
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should return to standard composer with mic button
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

      // Tap mic again to record and send
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Timeline should now contain the voice message bubble
      expect(find.byType(VoiceBubbleContent), findsOneWidget);
    });
  });
}
