import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'mi_app_toast.dart';
import 'note_attachment_store.dart';

/// 录音完成结果：附件引用 + 归一化波形峰值（用于正文条与详情页展示）。
class VoiceRecordOutcome {
  const VoiceRecordOutcome({required this.ref, required this.waveformPeaks});

  final String ref;
  final List<double> waveformPeaks;
}

/// 单点振幅样本（时间轴 + 电平），用于按时间绘制实时波形。
class _AmpSample {
  const _AmpSample(this.elapsedMs, this.level);

  final int elapsedMs;
  final double level;
}

/// 底部抽屉：录音 UI；停止后需点「对号」确认才返回并插入文档。
Future<VoiceRecordOutcome?> showVoiceRecordSheet(BuildContext context) {
  return showModalBottomSheet<VoiceRecordOutcome?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _VoiceRecordSheetBody(),
  );
}

class _VoiceRecordSheetBody extends StatefulWidget {
  const _VoiceRecordSheetBody();

  @override
  State<_VoiceRecordSheetBody> createState() => _VoiceRecordSheetBodyState();
}

class _VoiceRecordSheetBodyState extends State<_VoiceRecordSheetBody> {
  static const _cardBg = Color(0xFF222222);
  static const _accentGreen = Color(0xFF00C853);
  static const _discardRed = Color(0xFF8B2E2E);
  /// 录音波形中央指示线（参考设计图为绿色）。
  static const _playheadLine = Color(0xFF69F0AE);

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _sw = Stopwatch();

  final List<_AmpSample> _samples = [];

  StreamSubscription<Amplitude>? _ampStream;
  Timer? _ampPollTimer;
  Timer? _tickTimer;

  bool _recording = false;
  bool _recorderPaused = false;
  bool _awaitingConfirm = false;
  bool _busy = false;
  bool _startFailed = false;
  String? _startError;

  String? _pendingRef;
  Duration _frozenElapsed = Duration.zero;

  @override
  void dispose() {
    _tickTimer?.cancel();
    _ampPollTimer?.cancel();
    _ampStream?.cancel();
    if (_recording) {
      unawaited(_recorder.cancel());
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<(RecordConfig config, String ext)> _pickEncoder() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
        return (
          const RecordConfig(
            encoder: AudioEncoder.wav,
            numChannels: 1,
            autoGain: true,
          ),
          'wav',
        );
      }
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return (
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          autoGain: true,
        ),
        'm4a',
      );
    }
    return (
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        autoGain: true,
      ),
      'wav',
    );
  }

  void _armTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  /// 流 + 轮询双通道，提高实时波形刷新率。
  void _beginAmplitudeMonitor() {
    _ampStream?.cancel();
    _ampStream = _recorder.onAmplitudeChanged(const Duration(milliseconds: 12)).listen((a) {
      _ingestAmplitudeSample(a);
    });

    _ampPollTimer?.cancel();
    _ampPollTimer = Timer.periodic(const Duration(milliseconds: 18), (_) async {
      if (!mounted || !_recording || _recorderPaused) return;
      try {
        final a = await _recorder.getAmplitude();
        _ingestAmplitudeSample(a);
      } catch (_) {}
    });
  }

  void _ingestAmplitudeSample(Amplitude a) {
    if (!mounted || !_recording || _recorderPaused) return;
    final v = _dbfsToLevel(a);
    final ms = _sw.elapsed.inMilliseconds;
    setState(() {
      // 不按毫秒合并，保留连续采样峰值，波形才跟得上实时音量起伏。
      _samples.add(_AmpSample(ms, v));
      while (_samples.length > 3000) {
        _samples.removeAt(0);
      }
    });
  }

  /// dBFS 转线性幅度再压 gamma，起伏更接近人耳对响度的感知。
  double _dbfsToLevel(Amplitude a) {
    final db = (a.current.isFinite ? a.current : -160.0).clamp(-96.0, 0.0);
    final linear = math.pow(10, db / 20.0).toDouble();
    const noiseFloor = 1.2e-4;
    final norm = ((linear - noiseFloor) / (1.0 - noiseFloor)).clamp(0.0, 1.0);
    return math.pow(norm, 0.58).toDouble();
  }

  List<double> _compressPeaksForSave() {
    if (_samples.isEmpty) return const [];
    final raw = _samples.map((s) => s.level).toList();
    const target = 72;
    if (raw.length <= target) return List<double>.from(raw);
    final out = <double>[];
    for (var i = 0; i < target; i++) {
      final t = i / (target - 1);
      final idx = (t * (raw.length - 1)).round().clamp(0, raw.length - 1);
      out.add(raw[idx]);
    }
    return out;
  }

  Future<void> _autoStart() async {
    if (_busy || _recording || _awaitingConfirm) return;
    setState(() {
      _busy = true;
      _startFailed = false;
      _startError = null;
    });
    try {
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
        if (mounted) {
          setState(() {
            _startFailed = true;
            _startError = '需要麦克风权限才能录音';
          });
        }
        return;
      }
      await NoteAttachmentStore.ensureInitialized();
      final (config, ext) = await _pickEncoder();
      final outPath = await NoteAttachmentStore.recordingOutputAbsolutePath(ext);
      try {
        await _recorder.start(config, path: outPath);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('MiNote record start: $e\n$st');
        }
        if (mounted) {
          setState(() {
            _startFailed = true;
            _startError = '无法开始录音：$e';
          });
        }
        return;
      }
      _samples.clear();
      _sw.reset();
      _sw.start();
      _beginAmplitudeMonitor();
      _armTick();
      if (mounted) {
        setState(() {
          _recording = true;
          _recorderPaused = false;
          _awaitingConfirm = false;
          _pendingRef = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePause() async {
    if (_busy || !_recording || _awaitingConfirm) return;
    setState(() => _busy = true);
    try {
      if (_recorderPaused) {
        await _recorder.resume();
        _sw.start();
        if (mounted) setState(() => _recorderPaused = false);
      } else {
        await _recorder.pause();
        _sw.stop();
        if (mounted) setState(() => _recorderPaused = true);
      }
    } catch (e) {
      if (mounted) {
        showAppToastFail(context, '暂停/继续失败：$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 停止录音，进入「对号 / 叉号」确认界面，不立即插入文档。
  Future<void> _stopRecording() async {
    if (_busy || !_recording || _awaitingConfirm) return;
    setState(() => _busy = true);
    try {
      _tickTimer?.cancel();
      _ampPollTimer?.cancel();
      _ampPollTimer = null;
      _ampStream?.cancel();
      _ampStream = null;
      final frozen = _sw.elapsed;
      _sw.stop();

      final out = await _recorder.stop();
      if (!mounted) return;

      setState(() {
        _recording = false;
        _recorderPaused = false;
      });

      if (out == null || out.isEmpty) {
        if (mounted) {
          showAppToastWarning(context, '未生成录音文件');
        }
        return;
      }

      final ref = NoteAttachmentStore.documentRefFromRecorderOutput(out);
      if (!kIsWeb) {
        final readyPath = await NoteAttachmentStore.getReadyLocalPath(ref);
        if (readyPath == null) {
          if (kDebugMode) {
            debugPrint('MiNote record stop: file missing or empty ref=$ref out=$out');
          }
          if (mounted) {
            showAppToastFail(context, '录音文件未写入或为空，请重试');
          }
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _awaitingConfirm = true;
        _pendingRef = ref;
        _frozenElapsed = frozen;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmInsert() {
    if (_busy || !_awaitingConfirm || _pendingRef == null) return;
    final ref = _pendingRef!;
    final peaks = _compressPeaksForSave();
    if (!mounted) return;
    Navigator.pop(
      context,
      VoiceRecordOutcome(ref: ref, waveformPeaks: peaks),
    );
  }

  Future<void> _discardPending() async {
    final ref = _pendingRef;
    if (ref != null) {
      await NoteAttachmentStore.deleteByRefIfExists(ref);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancelTop() async {
    if (_busy) return;
    if (_awaitingConfirm) {
      await _discardPending();
      return;
    }
    _tickTimer?.cancel();
    _ampPollTimer?.cancel();
    _ampPollTimer = null;
    _ampStream?.cancel();
    _ampStream = null;
    _sw.stop();
    if (_recording) {
      await _recorder.cancel();
    }
    if (mounted) Navigator.pop(context);
  }

  String _fmtMmSs(Duration d) {
    final m = d.inMinutes.remainder(1000);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _todayYmd() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Duration get _shownElapsed {
    if (_awaitingConfirm) return _frozenElapsed;
    if (_recording) return _sw.elapsed;
    return Duration.zero;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_autoStart()));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final elapsed = _shownElapsed;

    final recActive = _recording && !_recorderPaused;
    final dimFuture = !_recording || _recorderPaused;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
        child: Material(
          borderRadius: BorderRadius.circular(22),
          color: _cardBg,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => unawaited(_cancelTop()),
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    ),
                    const Spacer(),
                    if (_busy && (_recording || _awaitingConfirm))
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                      ),
                  ],
                ),
                if (_startFailed) ...[
                  Text(
                    _startError ?? '无法开始录音',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : () => unawaited(_autoStart()),
                    child: const Text('重试'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Text(
                        _awaitingConfirm ? '完成' : 'REC',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: recActive ? const Color(0xFFFF5C4D) : Colors.white24,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _todayYmd(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 88,
                    child: LayoutBuilder(
                      builder: (ctx, c) {
                        return CustomPaint(
                          size: Size(c.maxWidth, 88),
                          painter: _RecordWaveformPainter(
                            samples: List<_AmpSample>.from(_samples),
                            elapsedMs: elapsed.inMilliseconds,
                            dimFuture: dimFuture,
                            playheadColor: _playheadLine,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmtMmSs(elapsed),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                      const Spacer(),
                      if (!_awaitingConfirm)
                        Row(
                          children: [
                            Material(
                              color: const Color(0xFF3A3A3A),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _recording && !_busy ? () => unawaited(_togglePause()) : null,
                                child: SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: Icon(
                                    _recorderPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Material(
                              color: _accentGreen,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _recording && !_busy ? () => unawaited(_stopRecording()) : null,
                                child: const SizedBox(
                                  width: 58,
                                  height: 58,
                                  child: Icon(Icons.stop_rounded, color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Material(
                              color: _discardRed,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _busy ? null : () => unawaited(_discardPending()),
                                child: const SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: Icon(Icons.close_rounded, color: Colors.white, size: 28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Material(
                              color: _accentGreen,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _busy ? null : _confirmInsert,
                                child: const SizedBox(
                                  width: 58,
                                  height: 58,
                                  child: Icon(Icons.check_rounded, color: Colors.white, size: 32),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordWaveformPainter extends CustomPainter {
  _RecordWaveformPainter({
    required this.samples,
    required this.elapsedMs,
    required this.dimFuture,
    required this.playheadColor,
  });

  final List<_AmpSample> samples;
  final int elapsedMs;
  final bool dimFuture;
  final Color playheadColor;

  /// 游标左侧仅展示「最近」这段时间的采样，条更细、起伏更明显，贴近实时电平表。
  static const int _pastWindowMs = 4200;

  static double _levelAtMs(List<_AmpSample> samples, int tMs) {
    if (samples.isEmpty) return 0.04;
    if (tMs <= samples.first.elapsedMs) return samples.first.level;
    if (tMs >= samples.last.elapsedMs) return samples.last.level;
    var lo = 0;
    var hi = samples.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) ~/ 2;
      if (samples[mid].elapsedMs <= tMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = samples[lo];
    final b = samples[hi];
    if (b.elapsedMs <= a.elapsedMs) return a.level;
    final f = (tMs - a.elapsedMs) / (b.elapsedMs - a.elapsedMs);
    return a.level * (1 - f) + b.level * f;
  }

  /// 拉大安静与大声的视觉差距：小声更低、大声更高。
  static double _boostLevel(double raw) {
    final x = raw.clamp(0.0, 1.0);
    final curved = math.pow(x, 0.32).toDouble();
    return (curved * 1.2).clamp(0.0, 1.0);
  }

  /// 压低底噪：去掉一小段最低电平再映射柱高。
  static double _ampForBarHeight(double boosted) {
    return ((boosted - 0.14) / 0.86).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    const barW = 1.8;
    const gap = 1.35;
    final n = (size.width / (barW + gap)).floor().clamp(40, 220);
    final step = size.width / n;
    final midY = size.height / 2;

    for (var i = 0; i < n; i++) {
      final cx = (i + 0.5) * step;
      double h;
      Color col;

      if (cx > centerX) {
        col = Colors.white.withValues(alpha: dimFuture ? 0.14 : 0.22);
        h = 5;
      } else {
        final dist = centerX - cx;
        var tMs = elapsedMs - (dist / centerX * _pastWindowMs).round();
        if (tMs < 0) {
          tMs = 0;
        }
        if (samples.isEmpty) {
          col = Colors.white.withValues(alpha: 0.35);
          h = 1.2;
        } else {
          final boosted = _boostLevel(_levelAtMs(samples, tMs.clamp(0, elapsedMs)));
          final amp = _ampForBarHeight(boosted);
          h = 1.0 + amp * (size.height * 0.78);
          col = Colors.white.withValues(alpha: 0.97);
        }
      }

      final double barH = cx > centerX ? math.min(h, 8).toDouble() : h;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, midY), width: barW, height: barH),
        const Radius.circular(0.9),
      );
      canvas.drawRRect(rect, Paint()..color = col);
    }

    final hx = centerX.clamp(4.0, size.width - 4.0);
    canvas.drawCircle(Offset(hx, 5), 3.8, Paint()..color = playheadColor);
    canvas.drawLine(
      Offset(hx, 8),
      Offset(hx, size.height - 3),
      Paint()
        ..color = playheadColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RecordWaveformPainter oldDelegate) {
    return oldDelegate.elapsedMs != elapsedMs ||
        oldDelegate.dimFuture != dimFuture ||
        oldDelegate.playheadColor != playheadColor ||
        oldDelegate.samples.length != samples.length ||
        (samples.isNotEmpty &&
            oldDelegate.samples.isNotEmpty &&
            (samples.last.elapsedMs != oldDelegate.samples.last.elapsedMs ||
                samples.last.level != oldDelegate.samples.last.level));
  }
}
