import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 优先 [PlatformFile.bytes]；为空时从 [PlatformFile.path] 缓存路径再读（部分 ROM 下常见）。
Future<Uint8List?> readPlatformFileBytes(PlatformFile f) async {
  final b = f.bytes;
  if (b != null && b.isNotEmpty) return b;
  try {
    final p = f.path;
    if (p == null || p.isEmpty) return null;
    return await File(p).readAsBytes();
  } catch (_) {
    return null;
  }
}
