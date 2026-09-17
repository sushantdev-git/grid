import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Result returned after successfully finishing a Push-to-Talk audio recording.
class VoiceRecordResult {
  final String filePath;
  final int durationMs;
  final Uint8List waveform;
  final Uint8List audioBytes;

  const VoiceRecordResult({
    required this.filePath,
    required this.durationMs,
    required this.waveform,
    required this.audioBytes,
  });
}

/// Unified cross-platform Push-to-Talk recording, playback, and forensic storage service.
class VoiceService {
  final AudioRecorder? _recorder;
  final AudioPlayer? _player;
  final bool isTestMode;

  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();
  final StreamController<String?> _playingPathController = StreamController<String?>.broadcast();
  final StreamController<PlayerState> _testPlayerStateController = StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _testPositionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _testDurationController = StreamController<Duration>.broadcast();

  StreamSubscription<Amplitude>? _amplitudeSub;
  DateTime? _recordStartTime;
  String? _activeRecordPath;
  final List<int> _recordedAmplitudes = [];

  String? _currentlyPlayingPath;

  VoiceService({
    AudioRecorder? recorder,
    AudioPlayer? player,
    bool? testMode,
  })  : isTestMode = testMode ?? (Platform.environment.containsKey('FLUTTER_TEST') || kIsWeb),
        _recorder = (testMode == true || (testMode == null && (Platform.environment.containsKey('FLUTTER_TEST') || kIsWeb)))
            ? recorder
            : (recorder ?? AudioRecorder()),
        _player = (testMode == true || (testMode == null && (Platform.environment.containsKey('FLUTTER_TEST') || kIsWeb)))
            ? player
            : (player ?? AudioPlayer());

  /// Live normalized amplitude stream (0.0 to 1.0) while actively recording.
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Stream of currently playing audio path (null if stopped/paused).
  Stream<String?> get playingPathStream => _playingPathController.stream;

  /// Player state change stream.
  Stream<PlayerState> get playerStateStream =>
      isTestMode ? _testPlayerStateController.stream : _player!.onPlayerStateChanged;

  /// Position stream for current playback.
  Stream<Duration> get positionStream =>
      isTestMode ? _testPositionController.stream : _player!.onPositionChanged;

  /// Duration stream for current playback.
  Stream<Duration> get durationStream =>
      isTestMode ? _testDurationController.stream : _player!.onDurationChanged;

  String? get currentlyPlayingPath => _currentlyPlayingPath;

  bool get isRecording => _recordStartTime != null;

  /// Resolves the dedicated directory for storing voice notes.
  Future<Directory> getVoiceDirectory() async {
    Directory baseDir;
    try {
      baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = Directory(p.join(Directory.systemTemp.path, 'grid_data'));
    }
    final voiceDir = Directory(p.join(baseDir.path, 'grid_voice_notes'));
    if (!voiceDir.existsSync()) {
      voiceDir.createSync(recursive: true);
    }
    return voiceDir;
  }

  /// Begins audio capture with 16 kHz AAC-LC compression and live amplitude monitoring.
  Future<bool> startRecording() async {
    if (isRecording) return false;

    _recordedAmplitudes.clear();

    if (isTestMode) {
      _recordStartTime = DateTime.now();
      _activeRecordPath = '/tmp/test_voice_${_recordStartTime!.millisecondsSinceEpoch}.m4a';
      return true;
    }

    try {
      final hasPerm = await _recorder!.hasPermission();
      if (!hasPerm) return false;

      final dir = await getVoiceDirectory();
      final filename = 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = p.join(dir.path, filename);
      _activeRecordPath = path;

      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          bitRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      _recordStartTime = DateTime.now();

      _amplitudeSub = _recorder!.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        final db = amp.current;
        final normalized = ((db + 60.0) / 60.0).clamp(0.0, 1.0);
        _recordedAmplitudes.add((normalized * 255).round());
        if (!_amplitudeController.isClosed) {
          _amplitudeController.add(normalized);
        }
      });

      return true;
    } catch (e) {
      _recordStartTime = null;
      _activeRecordPath = null;
      return false;
    }
  }

  /// Stops the active recording and returns the compiled [VoiceRecordResult].
  Future<VoiceRecordResult?> stopRecording() async {
    if (!isRecording) return null;

    final durationMs = DateTime.now().difference(_recordStartTime!).inMilliseconds;
    _recordStartTime = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    if (isTestMode) {
      final fakeWaveform = _generatePreviewWaveform(_recordedAmplitudes);
      final fakeAudio = Uint8List.fromList([0xFF, 0xF1, 0x50, 0x80, 0x01, 0x02, 0x03]);
      return VoiceRecordResult(
        filePath: _activeRecordPath ?? '/tmp/test_voice.m4a',
        durationMs: durationMs > 0 ? durationMs : 1000,
        waveform: fakeWaveform,
        audioBytes: fakeAudio,
      );
    }

    try {
      final outputPath = await _recorder!.stop();
      final path = outputPath ?? _activeRecordPath;
      if (path == null) return null;

      final file = File(path);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      final waveform = _generatePreviewWaveform(_recordedAmplitudes);

      return VoiceRecordResult(
        filePath: path,
        durationMs: durationMs,
        waveform: waveform,
        audioBytes: bytes,
      );
    } catch (_) {
      return null;
    } finally {
      _activeRecordPath = null;
    }
  }

  /// Cancels recording and discards temporary recording file.
  Future<void> cancelRecording() async {
    if (!isRecording) return;
    _recordStartTime = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    if (!isTestMode && _recorder != null) {
      try {
        await _recorder!.stop();
        if (_activeRecordPath != null) {
          final file = File(_activeRecordPath!);
          if (file.existsSync()) {
            file.deleteSync();
          }
        }
      } catch (_) {}
    }
    _activeRecordPath = null;
    _recordedAmplitudes.clear();
  }

  /// Compresses or resamples the amplitude history into a fixed 24-sample preview bar.
  Uint8List _generatePreviewWaveform(List<int> raw, {int targetSamples = 24}) {
    if (raw.isEmpty) {
      return Uint8List.fromList(List.filled(targetSamples, 40));
    }

    final result = Uint8List(targetSamples);
    final bucketSize = raw.length / targetSamples;

    for (int i = 0; i < targetSamples; i++) {
      final start = (i * bucketSize).floor();
      final end = ((i + 1) * bucketSize).ceil().clamp(0, raw.length);

      int maxVal = 0;
      for (int j = start; j < end; j++) {
        if (raw[j] > maxVal) maxVal = raw[j];
      }
      result[i] = maxVal > 0 ? maxVal : 30;
    }

    return result;
  }

  /// Writes audio bytes received over the mesh/network to a local file.
  Future<String> saveReceivedVoiceNote(Uint8List audioBytes, String messageId) async {
    if (isTestMode) {
      return '/tmp/received_voice_$messageId.m4a';
    }

    final dir = await getVoiceDirectory();
    final cleanId = messageId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(p.join(dir.path, 'voice_$cleanId.m4a'));
    await file.writeAsBytes(audioBytes, flush: true);
    return file.path;
  }

  /// Plays a voice note file. Automatically pauses any other active playback.
  Future<void> play(String path) async {
    if (isTestMode) {
      _currentlyPlayingPath = path;
      _playingPathController.add(path);
      _testPlayerStateController.add(PlayerState.playing);
      return;
    }

    try {
      if (_currentlyPlayingPath != null && _currentlyPlayingPath != path) {
        await _player!.stop();
      }
      _currentlyPlayingPath = path;
      _playingPathController.add(path);
      await _player!.play(DeviceFileSource(path));
    } catch (_) {}
  }

  /// Pauses current playback.
  Future<void> pause() async {
    if (isTestMode) {
      _currentlyPlayingPath = null;
      _playingPathController.add(null);
      _testPlayerStateController.add(PlayerState.paused);
      return;
    }
    try {
      await _player!.pause();
      _currentlyPlayingPath = null;
      _playingPathController.add(null);
    } catch (_) {}
  }

  /// Resumes playback on the active audio file.
  Future<void> resume() async {
    if (isTestMode) {
      if (_currentlyPlayingPath != null) {
        _testPlayerStateController.add(PlayerState.playing);
      }
      return;
    }
    try {
      await _player!.resume();
    } catch (_) {}
  }

  /// Stops current playback.
  Future<void> stop() async {
    _currentlyPlayingPath = null;
    _playingPathController.add(null);
    if (isTestMode) {
      _testPlayerStateController.add(PlayerState.stopped);
      return;
    }
    try {
      await _player!.stop();
    } catch (_) {}
  }

  /// Seeks to a specific playback position.
  Future<void> seek(Duration position) async {
    if (isTestMode) {
      _testPositionController.add(position);
      return;
    }
    try {
      await _player!.seek(position);
    } catch (_) {}
  }

  /// Sets audio playback rate (e.g. 1.0, 1.5, 2.0).
  Future<void> setPlaybackRate(double rate) async {
    if (isTestMode) return;
    try {
      await _player!.setPlaybackRate(rate);
    } catch (_) {}
  }

  /// Forensic Panic Wipe: securely overwrites all audio files with zeros before unlinking.
  Future<void> wipeAllVoiceNotes() async {
    await stop();
    await cancelRecording();

    try {
      final dir = await getVoiceDirectory();
      if (dir.existsSync()) {
        final files = dir.listSync();
        for (final entity in files) {
          if (entity is File) {
            try {
              final len = entity.lengthSync();
              if (len > 0) {
                final zeros = Uint8List(len);
                entity.writeAsBytesSync(zeros, flush: true);
              }
              entity.deleteSync();
            } catch (_) {}
          }
        }
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Disposes audio controllers and releases hardware resources.
  Future<void> dispose() async {
    await _amplitudeSub?.cancel();
    await _amplitudeController.close();
    await _playingPathController.close();
    await _testPlayerStateController.close();
    await _testPositionController.close();
    await _testDurationController.close();
    await _recorder?.dispose();
    await _player?.dispose();
  }
}

/// Global provider for the VoiceService.
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = VoiceService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
