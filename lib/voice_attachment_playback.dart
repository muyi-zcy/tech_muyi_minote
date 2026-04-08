import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'mi_app_toast.dart';
import 'note_attachment_store.dart';
import 'voice_attachment_detail_sheet.dart';
import 'voice_player_common.dart';

/// 文档内语音胶囊条（图一）：左侧播放/暂停，其余区域打开详情抽屉（图二）。
class VoiceAttachmentPlaybackTile extends StatefulWidget {
  const VoiceAttachmentPlaybackTile({
    super.key,
    required this.minoteRef,
    required this.displayLabel,
    this.waveformPeaks,
  });

  final String minoteRef;
  final String displayLabel;

  /// 录音时保存的归一化峰值；无则迷你波形用占位样式。
  final List<double>? waveformPeaks;

  @override
  State<VoiceAttachmentPlaybackTile> createState() => _VoiceAttachmentPlaybackTileState();
}

class _VoiceAttachmentPlaybackTileState extends State<VoiceAttachmentPlaybackTile> {
  static const _pillBg = Color(0xFF2B2B2B);
  static const _accent = Color(0xFFE53935);

  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _sourceReady = false;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _ended = true;
      });
    });
    _posSub = _player.onPositionChanged.listen((d) {
      if (!mounted) return;
      setState(() => _position = d);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _completeSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  String _fmtMmSs(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePlayPause() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      if (!_sourceReady) {
        final ok = await prepareVoiceAttachmentPlayer(
          _player,
          widget.minoteRef,
          (msg) {
            if (mounted) {
              showAppToastFail(context, msg);
            }
          },
        );
        if (!ok || !mounted) return;
        _sourceReady = true;
      }
      if (_ended) {
        await _player.seek(Duration.zero);
        _ended = false;
      }
      await _player.resume();
      if (_player.state != PlayerState.playing) {
        if (kIsWeb || widget.minoteRef.startsWith('blob:')) {
          await _player.play(UrlSource(widget.minoteRef));
        } else {
          final path = await NoteAttachmentStore.getReadyLocalPath(widget.minoteRef);
          if (path == null) {
            if (mounted) {
              showAppToastWarning(context, '找不到音频或文件为空');
            }
            return;
          }
          await _player.play(
            DeviceFileSource(path, mimeType: voiceMimeForPath(path)),
            mode: PlayerMode.mediaPlayer,
          );
        }
      }
    } catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'voice_attachment_playback',
        ),
      );
      if (mounted) {
        showAppToastFail(context, '无法播放：$e');
      }
    }
  }

  Future<void> _openDetail() async {
    if (!mounted) return;
    await showVoiceAttachmentDetailSheet(
      context,
      player: _player,
      minoteRef: widget.minoteRef,
      displayLabel: widget.displayLabel,
      waveformPeaks: widget.waveformPeaks,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _pillBg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => unawaited(_togglePlayPause()),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _accent.withValues(alpha: 0.9), width: 1.5),
                      ),
                      child: Icon(
                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => unawaited(_openDetail()),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 14, 8),
                    child: Row(
                      children: [
                        Text(
                          _fmtMmSs(_position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniWaveform(
                            seed: widget.minoteRef.hashCode,
                            playing: _playing,
                            peaks: widget.waveformPeaks,
                            progress: _duration.inMilliseconds > 0
                                ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                : 0.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniWaveform extends StatefulWidget {
  const _MiniWaveform({
    required this.seed,
    required this.playing,
    this.peaks,
    required this.progress,
  });

  final int seed;
  final bool playing;
  final List<double>? peaks;
  final double progress;

  @override
  State<_MiniWaveform> createState() => _MiniWaveformState();
}

class _MiniWaveformState extends State<_MiniWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _tick;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    if (widget.playing && (widget.peaks == null || widget.peaks!.isEmpty)) {
      _tick.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MiniWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool anim(_MiniWaveform w) => w.playing && (w.peaks == null || w.peaks!.isEmpty);
    final need = anim(widget);
    final was = anim(oldWidget);
    if (need && !was) {
      _tick.repeat();
    } else if (!need && was) {
      _tick.stop();
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPeaks = widget.peaks != null && widget.peaks!.isNotEmpty;
    return SizedBox(
      height: 28,
      child: hasPeaks
          ? CustomPaint(
              painter: _MiniWavePainter(
                seed: widget.seed,
                playing: widget.playing,
                phase: 0,
                peaks: widget.peaks!,
                progress: widget.progress,
              ),
              size: Size.infinite,
            )
          : AnimatedBuilder(
              animation: _tick,
              builder: (context, _) {
                return CustomPaint(
                  painter: _MiniWavePainter(
                    seed: widget.seed,
                    playing: widget.playing,
                    phase: _tick.value * 2 * math.pi,
                    peaks: const [],
                    progress: 0,
                  ),
                  size: Size.infinite,
                );
              },
            ),
    );
  }
}

class _MiniWavePainter extends CustomPainter {
  _MiniWavePainter({
    required this.seed,
    required this.playing,
    required this.phase,
    required this.peaks,
    required this.progress,
  });

  final int seed;
  final bool playing;
  final double phase;
  final List<double> peaks;
  final double progress;

  double _samplePeak(int i, int n) {
    if (peaks.isEmpty) return 0.35;
    final t = n <= 1 ? 0.0 : i / (n - 1);
    final x = t * (peaks.length - 1);
    final lo = x.floor().clamp(0, peaks.length - 1);
    final hi = math.min(lo + 1, peaks.length - 1);
    final f = x - lo;
    return peaks[lo] * (1 - f) + peaks[hi] * f;
  }

  static double _visualPeak(double raw) {
    final x = raw.clamp(0.0, 1.0);
    return (math.pow(x, 0.32) * 1.2).clamp(0.0, 1.0).toDouble();
  }

  static double _ampForBarHeight(double boosted) {
    return ((boosted - 0.14) / 0.86).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final n = (size.width / 5).floor().clamp(16, 40);
    final step = size.width / n;
    final mid = size.height / 2;
    final useReal = peaks.isNotEmpty;

    for (var i = 0; i < n; i++) {
      final x = (i + 0.5) * step;
      final t = n <= 1 ? 0.0 : i / (n - 1);
      double h;
      if (useReal) {
        final amp = _ampForBarHeight(_visualPeak(_samplePeak(i, n)));
        h = 1.0 + amp * (size.height * 1.05);
      } else {
        h = 3.0 + rnd.nextDouble() * (size.height * 0.85);
        if (playing) {
          h *= 0.72 + 0.28 * math.sin(phase + i * 0.45);
        }
      }

      final past = t <= progress;
      final a = useReal
          ? (past ? 0.9 : 0.38)
          : 0.82;

      if (i == 0 || i == n - 1) {
        canvas.drawCircle(
          Offset(x, mid),
          1.2,
          Paint()..color = Colors.white.withValues(alpha: past ? 0.75 : 0.35),
        );
      } else {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, mid), width: 1.25, height: h),
          const Radius.circular(0.65),
        );
        canvas.drawRRect(rect, Paint()..color = Colors.white.withValues(alpha: a));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniWavePainter oldDelegate) {
    if (oldDelegate.playing != playing) return true;
    if (oldDelegate.seed != seed) return true;
    if ((oldDelegate.progress - progress).abs() > 0.002) return true;
    if (peaks.length != oldDelegate.peaks.length) return true;
    if (playing && peaks.isEmpty && (oldDelegate.phase - phase).abs() > 0.01) return true;
    return false;
  }
}
