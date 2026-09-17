import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid/infrastructure/codecs/voice_frame_codec.dart';

void main() {
  group('VoiceFrameCodec', () {
    test('encodes and decodes voice frame payload with waveform', () {
      final waveform = Uint8List.fromList([10, 45, 120, 255, 180, 90, 30, 0]);
      final audioData = Uint8List.fromList(List.generate(250, (i) => (i * 7) % 256));

      final original = VoiceFramePayload(
        durationMs: 3450,
        codec: VoiceCodecType.aacLc,
        waveform: waveform,
        audioData: audioData,
      );

      final encoded = VoiceFrameCodec.encode(original);
      expect(encoded, isNotNull);
      expect(encoded.length, equals(VoiceFrameCodec.minHeaderLength + waveform.length + audioData.length));

      final decoded = VoiceFrameCodec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.durationMs, equals(3450));
      expect(decoded.codec, equals(VoiceCodecType.aacLc));
      expect(decoded.waveform, equals(waveform));
      expect(decoded.audioData, equals(audioData));
    });

    test('handles empty waveform gracefully', () {
      final audioData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final original = VoiceFramePayload(
        durationMs: 1200,
        codec: VoiceCodecType.opus,
        waveform: Uint8List(0),
        audioData: audioData,
      );

      final encoded = VoiceFrameCodec.encode(original);
      final decoded = VoiceFrameCodec.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.durationMs, equals(1200));
      expect(decoded.codec, equals(VoiceCodecType.opus));
      expect(decoded.waveform.length, equals(0));
      expect(decoded.audioData, equals(audioData));
    });

    test('returns null on truncated header', () {
      final truncated = Uint8List.fromList([0, 0, 1]); // < 6 bytes
      expect(VoiceFrameCodec.decode(truncated), isNull);
    });

    test('returns null on missing audio payload', () {
      // Header with 0 waveform length and 0 audio data
      final emptyAudio = Uint8List.fromList([0, 0, 1, 0, 1, 0]);
      expect(VoiceFrameCodec.decode(emptyAudio), isNull);
    });
  });
}
