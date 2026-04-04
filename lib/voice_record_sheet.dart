import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import 'note_attachment_store.dart';

/// 底部抽屉：录音写入 [NoteAttachmentStore]；播放由 [VoiceAttachmentPlaybackTile]（audioplayers）负责。
Future<String?> showVoiceRecordSheet(BuildContext context) {
  return showModalBottomSheet<String?>(
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
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _busy = false;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<(RecordConfig config, String ext)> _pickEncoder() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (await _recorder.isEncoderSupported(AudioEncoder.wav)) {
        return (const RecordConfig(encoder: AudioEncoder.wav), 'wav');
      }
    }
    if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      return (const RecordConfig(encoder: AudioEncoder.aacLc), 'm4a');
    }
    return (const RecordConfig(encoder: AudioEncoder.wav), 'wav');
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要麦克风权限才能录音')),
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法开始录音：$e')),
          );
        }
        return;
      }
      if (mounted) setState(() => _recording = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopAndFinish() async {
    if (_busy || !_recording) return;
    setState(() => _busy = true);
    try {
      final out = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (out == null || out.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未生成录音文件')),
          );
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('录音文件未写入或为空，请重试')),
            );
          }
          return;
        }
      }
      if (!mounted) return;
      Navigator.pop(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_recording) {
      await _recorder.cancel();
    }
    if (mounted) {
      setState(() => _recording = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
        child: Material(
          borderRadius: BorderRadius.circular(20),
          color: scheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '语音笔记',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _recording ? '正在录音… 点「停止并完成」插入到正文' : '点「开始录音」后说话，停止后将插入语音条。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _busy ? null : (_recording ? null : _start),
                        child: const Text('开始录音'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy || !_recording ? null : _stopAndFinish,
                        child: const Text('停止并完成'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
