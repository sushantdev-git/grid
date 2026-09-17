import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/services/voice_service.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

/// Minimalist in-bubble audio player widget featuring an interactive waveform,
/// play/pause toggle, duration tracking, and speed multiplier.
class VoiceBubbleContent extends ConsumerStatefulWidget {
  final ChatMessage message;

  const VoiceBubbleContent({
    super.key,
    required this.message,
  });

  @override
  ConsumerState<VoiceBubbleContent> createState() => _VoiceBubbleContentState();
}

class _VoiceBubbleContentState extends ConsumerState<VoiceBubbleContent> {
  double _playbackRate = 1.0;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<String?>? _pathSub;

  @override
  void initState() {
    super.initState();
    final initialMs = widget.message.mediaDurationMs ?? 0;
    _totalDuration = Duration(milliseconds: initialMs);
    _initSubscriptions();
  }

  void _initSubscriptions() {
    final voiceService = ref.read(voiceServiceProvider);

    _pathSub = voiceService.playingPathStream.listen((path) {
      if (!mounted) return;
      final isThisMessage = path != null && path == widget.message.mediaPath;
      if (!isThisMessage && _isPlaying) {
        setState(() {
          _isPlaying = false;
        });
      }
    });

    _posSub = voiceService.positionStream.listen((pos) {
      if (!mounted) return;
      if (voiceService.currentlyPlayingPath == widget.message.mediaPath) {
        setState(() {
          _currentPosition = pos;
        });
      }
    });

    _stateSub = voiceService.playerStateStream.listen((state) {
      if (!mounted) return;
      if (voiceService.currentlyPlayingPath == widget.message.mediaPath) {
        setState(() {
          _isPlaying = (state == PlayerState.playing);
          if (state == PlayerState.completed) {
            _isPlaying = false;
            _currentPosition = Duration.zero;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _pathSub?.cancel();
    super.dispose();
  }

  void _togglePlay() async {
    final voiceService = ref.read(voiceServiceProvider);
    final path = widget.message.mediaPath;
    if (path == null) return;

    if (_isPlaying) {
      await voiceService.pause();
      setState(() => _isPlaying = false);
    } else {
      await voiceService.play(path);
      await voiceService.setPlaybackRate(_playbackRate);
      setState(() => _isPlaying = true);
    }
  }

  void _cycleSpeed() async {
    final speeds = [1.0, 1.5, 2.0];
    final nextIndex = (speeds.indexOf(_playbackRate) + 1) % speeds.length;
    final nextSpeed = speeds[nextIndex];

    setState(() {
      _playbackRate = nextSpeed;
    });

    if (_isPlaying) {
      final voiceService = ref.read(voiceServiceProvider);
      await voiceService.setPlaybackRate(nextSpeed);
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.message.isOutgoing;
    final waveform = widget.message.waveformSamples ?? const [];
    final sampleCount = waveform.isNotEmpty ? waveform.length : 24;

    final progress = _totalDuration.inMilliseconds > 0
        ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Play / Pause Circle
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _togglePlay,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _isPlaying ? AppTheme.primaryAccent : AppTheme.darkCardElevated,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isPlaying ? AppTheme.primaryAccent : AppTheme.darkBorderSubtle,
                        width: 1.0,
                      ),
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: _isPlaying ? AppTheme.onPrimaryAccent : AppTheme.textPrimary,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Interactive Waveform Visualizer
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const barWidth = 3.0;
                      const spacing = 2.0;
                      final visibleBars = (constraints.maxWidth / (barWidth + spacing)).floor();
                      final count = visibleBars.clamp(12, 36);

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          if (_totalDuration.inMilliseconds <= 0) return;
                          final fraction = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                          final targetMs = (_totalDuration.inMilliseconds * fraction).round();
                          ref.read(voiceServiceProvider).seek(Duration(milliseconds: targetMs));
                          setState(() {
                            _currentPosition = Duration(milliseconds: targetMs);
                          });
                        },
                        onTapDown: (details) {
                          if (_totalDuration.inMilliseconds <= 0) return;
                          final fraction = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                          final targetMs = (_totalDuration.inMilliseconds * fraction).round();
                          ref.read(voiceServiceProvider).seek(Duration(milliseconds: targetMs));
                          setState(() {
                            _currentPosition = Duration(milliseconds: targetMs);
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(count, (i) {
                            final sampleIdx = (i * sampleCount / count).floor().clamp(0, sampleCount - 1);
                            final rawVal = (waveform.isNotEmpty && sampleIdx < waveform.length)
                                ? waveform[sampleIdx]
                                : 50;

                            // Normalize 0-255 to bar height between 5 and 30
                            final normalizedHeight = ((rawVal / 255.0) * 25.0 + 5.0).clamp(5.0, 30.0);

                            final barProgress = i / count;
                            final isPlayed = barProgress <= progress;

                            return Container(
                              width: barWidth,
                              height: normalizedHeight,
                              decoration: BoxDecoration(
                                color: isPlayed
                                    ? AppTheme.primaryAccent
                                    : (isOutgoing
                                        ? AppTheme.textMuted.withValues(alpha: 0.6)
                                        : AppTheme.darkBorder),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Duration & Speed controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isPlaying
                    ? '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}'
                    : _formatDuration(_totalDuration),
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: _cycleSpeed,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCardElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.darkBorderSubtle, width: 0.6),
                  ),
                  child: Text(
                    '${_playbackRate.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
