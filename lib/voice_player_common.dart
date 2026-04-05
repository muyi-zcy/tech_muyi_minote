import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'note_attachment_store.dart';

String? voiceMimeForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.3gp')) return 'audio/3gpp';
  return null;
}

/// 为 [player] 设置语音附件源（若尚未加载）。成功后可 [AudioPlayer.resume] / [AudioPlayer.seek]。
Future<bool> prepareVoiceAttachmentPlayer(
  AudioPlayer player,
  String minoteRef,
  void Function(String message)? onError,
) async {
  try {
    await NoteAttachmentStore.ensureInitialized();
    // 默认 release 会在播完后清空 source，导致无法再次 play/seek；语音统一用 stop。
    await player.setReleaseMode(ReleaseMode.stop);

    final existing = await player.getDuration();
    if (existing != null && existing > Duration.zero) {
      return true;
    }

    if (kIsWeb || minoteRef.startsWith('blob:')) {
      await player.setSource(UrlSource(minoteRef));
    } else {
      final path = await NoteAttachmentStore.getReadyLocalPath(minoteRef);
      if (path == null) {
        onError?.call('找不到音频或文件为空');
        return false;
      }
      await player.setSource(
        DeviceFileSource(path, mimeType: voiceMimeForPath(path)),
      );
    }
    return true;
  } catch (e, st) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'voice_player_common',
      ),
    );
    onError?.call('无法加载音频：$e');
    return false;
  }
}
