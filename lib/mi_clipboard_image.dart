import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'mi_clipboard_android_channel.dart';

Future<Uint8List?> _readFileFuture(DataReader reader, FileFormat format) async {
  if (!reader.canProvide(format)) return null;
  final c = Completer<Uint8List?>();
  final progress = reader.getFile(
    format,
    (file) async {
      try {
        final all = await file.readAll();
        if (!c.isCompleted) c.complete(all);
      } catch (_) {
        if (!c.isCompleted) c.complete(null);
      }
    },
    onError: (_) {
      if (!c.isCompleted) c.complete(null);
    },
  );
  if (progress == null && !c.isCompleted) {
    c.complete(null);
  }
  return c.future;
}

/// 从剪贴板读取一张位图（优先 PNG，其次 JPEG / GIF / WebP）。
Future<Uint8List?> readClipboardImageBytes() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();
  for (final format in [Formats.png, Formats.jpeg, Formats.gif, Formats.webp]) {
    final bytes = await _readFileFuture(reader, format);
    if (bytes != null && bytes.isNotEmpty) return bytes;
  }
  return null;
}

String _mimeForImageExtension(String ext) {
  switch (ext.trim().toLowerCase().replaceAll('.', '')) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'png':
    default:
      return 'image/png';
  }
}

/// 将图片字节写入系统剪贴板（按格式选择 [Formats.png] / [Formats.jpeg] 等）。
///
/// Android 优先走 [FileProvider] + 系统 [ClipboardManager]，避免 super_clipboard 管道写入在
/// MIUI 等环境下被提前关闭而产生 EPIPE / `Failing to write data`（与录音无关，但易误判为应用故障）。
Future<bool> writeImageBytesToClipboard(Uint8List bytes, {required String extension}) async {
  final ext = extension.trim().toLowerCase().replaceAll('.', '');

  if (defaultTargetPlatform == TargetPlatform.android) {
    final viaFile = await writeClipboardImageViaAndroidFileProvider(
      bytes,
      ext.isEmpty ? 'png' : ext,
      _mimeForImageExtension(ext),
    );
    if (viaFile) return true;
  }

  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('mi_clipboard_image: SystemClipboard unavailable');
    }
    return false;
  }
  final item = DataWriterItem();
  switch (ext) {
    case 'png':
      item.add(Formats.png(bytes));
      break;
    case 'jpg':
    case 'jpeg':
      item.add(Formats.jpeg(bytes));
      break;
    case 'gif':
      item.add(Formats.gif(bytes));
      break;
    case 'webp':
      item.add(Formats.webp(bytes));
      break;
    default:
      item.add(Formats.png(bytes));
      break;
  }
  try {
    await clipboard.write([item]);
    return true;
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('mi_clipboard_image: write failed: $e');
    }
    return false;
  }
}
