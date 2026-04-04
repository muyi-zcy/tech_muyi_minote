import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'note_attachment_store.dart';

/// 语音附件条：使用 [audioplayers]（Android MediaPlayer / iOS AVPlayer），与 ExoPlayer 路线的 [just_audio] 完全分离。
class VoiceAttachmentPlaybackTile extends StatefulWidget {
  const VoiceAttachmentPlaybackTile({
    super.key,
    required this.minoteRef,
    required this.displayLabel,
    required this.borderColor,
    required this.fillColor,
    required this.iconColor,
  });

  final String minoteRef;
  final String displayLabel;
  final Color borderColor;
  final Color fillColor;
  final Color iconColor;

  @override
  State<VoiceAttachmentPlaybackTile> createState() => _VoiceAttachmentPlaybackTileState();
}

class _VoiceAttachmentPlaybackTileState extends State<VoiceAttachmentPlaybackTile> {
  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;
  bool _playing = false;

  static String? _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.3gp')) return 'audio/3gpp';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      await NoteAttachmentStore.ensureInitialized();
      if (kIsWeb || widget.minoteRef.startsWith('blob:')) {
        await _player.play(UrlSource(widget.minoteRef));
      } else {
        final path = await NoteAttachmentStore.getReadyLocalPath(widget.minoteRef);
        if (path == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('找不到音频或文件为空')),
            );
          }
          return;
        }
        await _player.play(
          DeviceFileSource(path, mimeType: _mimeForPath(path)),
          mode: PlayerMode.mediaPlayer,
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法播放：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.fillColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.borderColor),
          ),
          child: Row(
            children: [
              Icon(Icons.mic_rounded, color: widget.iconColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.displayLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Icon(
                _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: widget.iconColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
