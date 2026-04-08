import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mi_app_toast.dart';
import 'note_attachment_store.dart';
import 'voice_player_common.dart';

/// 等宽数字，避免播放进度更新时时间文字左右抖动。
const _voiceDetailTimeFigures = [FontFeature.tabularFigures()];

/// 语音详情抽屉（参考设计：大计时、波形、进度与控制条），与文档内条共用 [player]。
Future<void> showVoiceAttachmentDetailSheet(
  BuildContext context, {
  required AudioPlayer player,
  required String minoteRef,
  required String displayLabel,
  List<double>? waveformPeaks,
}) async {
  final ok = await prepareVoiceAttachmentPlayer(
    player,
    minoteRef,
    (msg) {
      if (context.mounted) {
        showAppToastFail(context, msg);
      }
    },
  );
  if (!ok || !context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) => _VoiceDetailSheetBody(
      player: player,
      minoteRef: minoteRef,
      displayLabel: displayLabel,
      waveformPeaks: waveformPeaks,
    ),
  );
}

class _VoiceDetailSheetBody extends StatefulWidget {
  const _VoiceDetailSheetBody({
    required this.player,
    required this.minoteRef,
    required this.displayLabel,
    this.waveformPeaks,
  });

  final AudioPlayer player;
  final String minoteRef;
  final String displayLabel;
  final List<double>? waveformPeaks;

  @override
  State<_VoiceDetailSheetBody> createState() => _VoiceDetailSheetBodyState();
}

class _VoiceDetailSheetBodyState extends State<_VoiceDetailSheetBody> {
  static const _bg = Color(0xFF1C1C1C);
  static const _scrubber = Color(0xFF7EC8E3);

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  static const _rates = <double>[1.0, 1.5, 2.0];
  int _rateIndex = 0;

  @override
  void initState() {
    super.initState();
    _posSub = widget.player.onPositionChanged.listen((d) {
      if (mounted) setState(() => _position = d);
    });
    _durSub = widget.player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _stateSub = widget.player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
    _completeSub = widget.player.onPlayerComplete.listen((_) {
      unawaited(_syncAfterComplete());
    });
    unawaited(_refreshFromPlayer());
  }

  Future<void> _syncAfterComplete() async {
    final d = await widget.player.getDuration();
    final p = await widget.player.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _playerState = PlayerState.completed;
      if (d != null && d > Duration.zero) _duration = d;
      if (p != null) _position = p;
    });
  }

  Future<void> _refreshFromPlayer() async {
    final p = await widget.player.getCurrentPosition();
    final d = await widget.player.getDuration();
    if (!mounted) return;
    setState(() {
      if (p != null) _position = p;
      if (d != null) _duration = d;
      _playerState = widget.player.state;
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    super.dispose();
  }

  String _fmtWithCentiseconds(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final cs = (d.inMilliseconds % 1000) ~/ 10;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.'
        '${cs.toString().padLeft(2, '0')}';
  }

  String _fmtHms(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _playFromSource() async {
    if (kIsWeb || widget.minoteRef.startsWith('blob:')) {
      await widget.player.play(
        UrlSource(widget.minoteRef),
        mode: PlayerMode.mediaPlayer,
      );
    } else {
      final path = await NoteAttachmentStore.getReadyLocalPath(widget.minoteRef);
      if (path != null) {
        await widget.player.play(
          DeviceFileSource(path, mimeType: voiceMimeForPath(path)),
          mode: PlayerMode.mediaPlayer,
        );
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_playerState == PlayerState.playing) {
      await widget.player.pause();
      await _refreshFromPlayer();
      return;
    }

    final dur = _duration;
    final atEnd = _playerState == PlayerState.completed ||
        (dur > Duration.zero &&
            _position >= dur - const Duration(milliseconds: 350));

    if (atEnd) {
      await widget.player.seek(Duration.zero);
    }

    await widget.player.resume();

    // 播完后在 release 模式下 source 会被清空，resume 无效，需重新 play。
    if (widget.player.state != PlayerState.playing) {
      await _playFromSource();
    }
    await _refreshFromPlayer();
  }

  Future<void> _seekBy(int seconds) async {
    final dur = _duration;
    var next = _position + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (dur > Duration.zero && next > dur) next = dur;
    await widget.player.seek(next);
    await _refreshFromPlayer();
  }

  Future<void> _cycleRate() async {
    HapticFeedback.selectionClick();
    _rateIndex = (_rateIndex + 1) % _rates.length;
    final r = _rates[_rateIndex];
    await widget.player.setPlaybackRate(r);
    if (mounted) setState(() {});
  }

  String _rateLabel(double r) {
    if (r == r.roundToDouble()) return '${r.toInt()}x';
    return '${r}x';
  }

  Future<void> _onScrub(double? v) async {
    if (v == null || _duration <= Duration.zero) return;
    await widget.player.seek(Duration(milliseconds: (v * _duration.inMilliseconds).round()));
    await _refreshFromPlayer();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height * 0.88;

    final playing = _playerState == PlayerState.playing;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: h,
        child: Material(
          color: _bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '录音',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.displayLabel.isNotEmpty)
                              Text(
                                widget.displayLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: 200,
                      child: Text(
                        _fmtWithCentiseconds(_position),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.5,
                          fontFeatures: _voiceDetailTimeFigures,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 72,
                    child: LayoutBuilder(
                      builder: (ctx, c) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) {
                            final x = d.localPosition.dx;
                            final f = (x / c.maxWidth).clamp(0.0, 1.0);
                            unawaited(_onScrub(f));
                          },
                          child: CustomPaint(
                            size: Size(c.maxWidth, 72),
                            painter: _DetailWaveformPainter(
                              progress: progress,
                              scrubberColor: _scrubber,
                              peaks: widget.waveformPeaks,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(5, (i) {
                        if (_duration <= Duration.zero) {
                          return Text(
                            '00:0$i',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 11,
                              fontFeatures: _voiceDetailTimeFigures,
                            ),
                          );
                        }
                        final t = Duration(
                          milliseconds: (_duration.inMilliseconds * i ~/ 4).round(),
                        );
                        final sec = t.inSeconds;
                        return Text(
                          '00:${sec.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                            fontFeatures: _voiceDetailTimeFigures,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF333333),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      ),
                      onPressed: () {
                        showAppToast(context, '暂无语音转文字');
                      },
                      child: const Text('显示文本'),
                    ),
                  ),
                  const Spacer(),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.white54,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: _duration > Duration.zero ? _onScrub : null,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmtHms(_position),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontFeatures: _voiceDetailTimeFigures,
                          ),
                        ),
                        Text(
                          _fmtHms(_duration),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontFeatures: _voiceDetailTimeFigures,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: () {
                          showAppToast(context, '书签功能开发中');
                        },
                        icon: Icon(Icons.outlined_flag, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      IconButton(
                        tooltip: '快退 3 秒',
                        onPressed: () => unawaited(_seekBy(-3)),
                        icon: const _SeekThreeIcon(forward: false),
                      ),
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => unawaited(_togglePlay()),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: Icon(
                              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 36,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '快进 3 秒',
                        onPressed: () => unawaited(_seekBy(3)),
                        icon: const _SeekThreeIcon(forward: true),
                      ),
                      TextButton(
                        onPressed: () => unawaited(_cycleRate()),
                        child: Text(
                          _rateLabel(_rates[_rateIndex]),
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekThreeIcon extends StatelessWidget {
  const _SeekThreeIcon({required this.forward});

  final bool forward;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(
            forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
            color: Colors.white70,
            size: 28,
          ),
          Positioned(
            bottom: 2,
            child: Text(
              '3',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailWaveformPainter extends CustomPainter {
  _DetailWaveformPainter({
    required this.progress,
    required this.scrubberColor,
    this.peaks,
  });

  final double progress;
  final Color scrubberColor;
  final List<double>? peaks;

  double _samplePeak(int i, int n, List<double> p) {
    if (p.isEmpty) return 0.4;
    final t = n <= 1 ? 0.0 : i / (n - 1);
    final x = t * (p.length - 1);
    final lo = x.floor().clamp(0, p.length - 1);
    final hi = math.min(lo + 1, p.length - 1);
    final f = x - lo;
    return p[lo] * (1 - f) + p[hi] * f;
  }

  /// 与录音条一致：小声更低、大声更突出。
  static double _visualPeak(double raw) {
    final x = raw.clamp(0.0, 1.0);
    final curved = math.pow(x, 0.32).toDouble();
    return (curved * 1.2).clamp(0.0, 1.0);
  }

  static double _ampForBarHeight(double boosted) {
    return ((boosted - 0.14) / 0.86).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = 52;
    final w = size.width / n;
    final midY = size.height / 2;
    final playX = size.width * progress;
    final p = peaks;

    for (var i = 0; i < n; i++) {
      final cx = (i + 0.5) * w;
      final raw = p != null && p.isNotEmpty
          ? _samplePeak(i, n, p)
          : 0.35 + 0.65 * ((i * 17 % 13) / 13.0);
      final base = _ampForBarHeight(_visualPeak(raw));
      final h = 1.0 + base * (size.height * 0.72);
      final past = cx <= playX;
      final color = past
          ? Colors.white.withValues(alpha: 0.97)
          : Colors.white.withValues(alpha: 0.14);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, midY), width: 2.0, height: h),
        const Radius.circular(0.85),
      );
      canvas.drawRRect(rect, Paint()..color = color);
    }

    final scrubX = playX.clamp(4.0, size.width - 4.0);
    canvas.drawLine(
      Offset(scrubX, 4),
      Offset(scrubX, size.height - 4),
      Paint()
        ..color = scrubberColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _DetailWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.peaks?.length != peaks?.length;
  }
}
