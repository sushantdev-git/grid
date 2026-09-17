import 'dart:typed_data';
import 'package:collection/collection.dart';
import '../../core/utils/binary_reader.dart';
import '../../core/utils/binary_writer.dart';

/// Supported audio codec identifiers for voice frame wire payloads.
enum VoiceCodecType {
  aacLc(0x01),
  opus(0x02);

  final int rawValue;
  const VoiceCodecType(this.rawValue);

  static VoiceCodecType fromRaw(int value) {
    for (final t in VoiceCodecType.values) {
      if (t.rawValue == value) return t;
    }
    return VoiceCodecType.aacLc;
  }
}

/// Represents an unencrypted or decrypted Push-to-Talk voice memo payload.
class VoiceFramePayload {
  /// Total audio duration in milliseconds.
  final int durationMs;

  /// Audio compression format identifier.
  final VoiceCodecType codec;

  /// Normalized peak amplitude preview levels (0-255) used to render the
  /// waveform immediately without decoding the underlying audio file.
  final Uint8List waveform;

  /// Raw compressed audio container bytes (e.g. AAC .m4a or Opus).
  final Uint8List audioData;

  const VoiceFramePayload({
    required this.durationMs,
    this.codec = VoiceCodecType.aacLc,
    required this.waveform,
    required this.audioData,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final eq = const ListEquality().equals;
    return other is VoiceFramePayload &&
        other.durationMs == durationMs &&
        other.codec == codec &&
        eq(other.waveform, waveform) &&
        eq(other.audioData, audioData);
  }

  @override
  int get hashCode => Object.hash(
        durationMs,
        codec,
        const ListEquality().hash(waveform),
        const ListEquality().hash(audioData),
      );
}

/// Compact binary encoder/decoder for [VoiceFramePayload].
///
/// Binary Wire Layout:
/// - 4 bytes: duration in milliseconds (big-endian uint32)
/// - 1 byte:  codec identifier (0x01 = AAC-LC, 0x02 = Opus)
/// - 1 byte:  waveform samples length (N <= 255)
/// - N bytes: waveform peak amplitude bytes (0-255)
/// - Remainder: compressed audio stream bytes
class VoiceFrameCodec {
  static const int minHeaderLength = 6; // 4 + 1 + 1

  /// Serializes a [VoiceFramePayload] into compact wire bytes.
  static Uint8List encode(VoiceFramePayload payload) {
    final writer = BinaryWriter(
      initialCapacity: minHeaderLength + payload.waveform.length + payload.audioData.length,
    );

    // 4-byte duration
    writer.writeUint32(payload.durationMs);

    // 1-byte codec
    writer.writeUint8(payload.codec.rawValue);

    // 1-byte waveform sample count (capped at 255)
    final wfLen = payload.waveform.length > 255 ? 255 : payload.waveform.length;
    writer.writeUint8(wfLen);

    // Waveform bytes
    if (wfLen > 0) {
      writer.writeBytes(payload.waveform.sublist(0, wfLen));
    }

    // Audio data
    writer.writeBytes(payload.audioData);

    return writer.toBytes();
  }

  /// Deserializes wire bytes into a [VoiceFramePayload].
  /// Returns null if the byte buffer is malformed or truncated.
  static VoiceFramePayload? decode(Uint8List bytes) {
    if (bytes.length < minHeaderLength) {
      return null;
    }

    final reader = BinaryReader(bytes);
    try {
      final durationMs = reader.readUint32();
      final codecRaw = reader.readUint8();
      final wfLen = reader.readUint8();

      if (reader.remaining < wfLen) {
        return null;
      }

      final waveform = reader.readBytes(wfLen);
      final audioData = reader.readRemaining();

      if (audioData.isEmpty) {
        return null;
      }

      return VoiceFramePayload(
        durationMs: durationMs,
        codec: VoiceCodecType.fromRaw(codecRaw),
        waveform: waveform,
        audioData: audioData,
      );
    } catch (_) {
      return null;
    }
  }
}
