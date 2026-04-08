import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> shareUtf8TextFile(String fileName, String mimeType, String content) async {
  await Share.share(content, subject: fileName);
}

Future<void> sharePngBytes(Uint8List bytes) async {
  await Share.shareXFiles([
    XFile.fromData(bytes, name: '笔记.png', mimeType: 'image/png'),
  ]);
}

Future<void> savePngBytesToGallery(Uint8List bytes, {String? suggestedBaseName}) async {
  throw UnsupportedError('当前平台暂不支持保存图片到相册');
}
