import 'dart:io' show File;

import 'package:flutter/material.dart';

import 'note_attachment_store.dart';

int _decodeCacheWidthPx(BuildContext context, double decodeMaxLogical) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  return (decodeMaxLogical * dpr).round().clamp(48, 4096);
}

/// [decodeMaxLogical]：按逻辑像素限制解码宽度，避免大图在主线程解码卡死（微信导出图常见）。
Widget buildLocalImage(
  BuildContext context,
  String imageUrl, {
  double decodeMaxLogical = 720,
}) {
  final cacheW = _decodeCacheWidthPx(context, decodeMaxLogical);

  if (imageUrl.startsWith('minote://attachments/')) {
    // 优先磁盘：`Image.memory` 在 SuperText 的 WidgetSpan 里常出现首帧不刷新，重启后走 file 才正常。
    final syncPath = NoteAttachmentStore.getLocalPathSync(imageUrl);
    if (syncPath != null) {
      return Image.file(
        File(syncPath),
        key: ValueKey(imageUrl),
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image_outlined, size: 24),
      );
    }
    final mem = NoteAttachmentStore.peekInlineImageBytes(imageUrl);
    if (mem != null && mem.isNotEmpty) {
      return Image.memory(
        mem,
        key: ValueKey('mem_$imageUrl'),
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image_outlined, size: 24),
      );
    }
    return FutureBuilder<String?>(
      future: NoteAttachmentStore.getLocalPath(imageUrl),
      builder: (context, snap) {
        final path = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (path == null) {
          return const Icon(Icons.broken_image_outlined, size: 24);
        }
        return Image.file(
          File(path),
          key: ValueKey(imageUrl),
          fit: BoxFit.cover,
          cacheWidth: cacheW,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image_outlined, size: 24),
        );
      },
    );
  }
  return Image.network(
    imageUrl,
    fit: BoxFit.cover,
    cacheWidth: cacheW,
    errorBuilder: (context, error, stackTrace) =>
        const Icon(Icons.broken_image_outlined, size: 24),
  );
}
