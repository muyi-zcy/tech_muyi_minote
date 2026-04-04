import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('com.example.tech_muyi_minote/clipboard_image');

/// Android：用 [FileProvider] + [ClipData] 写剪贴板，避免 super_clipboard 管道被系统/输入法
/// 提前关闭时出现 EPIPE（Log 里 `DataProvider$PipeDataWriter`）。
Future<bool> writeClipboardImageViaAndroidFileProvider(
  Uint8List bytes,
  String fileExtension,
  String mimeType,
) async {
  if (!Platform.isAndroid) return false;
  try {
    final dir = await getTemporaryDirectory();
    final ext = fileExtension.trim().toLowerCase().replaceAll('.', '');
    final safeExt = ext.isEmpty ? 'png' : ext;
    final name = 'mi_clip_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final path = p.join(dir.path, name);
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    final ok = await _channel.invokeMethod<bool>('writeImage', {
      'path': path,
      'mime': mimeType,
    });
    return ok == true;
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('mi_clipboard_android_channel: $e\n$st');
    }
    return false;
  }
}
