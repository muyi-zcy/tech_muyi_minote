import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareUtf8TextFile(String fileName, String mimeType, String content) async {
  final dir = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final path = '${dir.path}/$safeName';
  await File(path).writeAsString(content, encoding: utf8);
  await Share.shareXFiles([XFile(path, mimeType: mimeType)]);
}

Future<void> sharePngBytes(Uint8List bytes) async {
  await Share.shareXFiles([
    XFile.fromData(bytes, name: '笔记.png', mimeType: 'image/png'),
  ]);
}

Future<void> savePngBytesToGallery(Uint8List bytes, {String? suggestedBaseName}) async {
  final now = DateTime.now();
  final defaultBase =
      '笔记_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  var base = (suggestedBaseName?.trim().isNotEmpty ?? false) ? suggestedBaseName!.trim() : defaultBase;
  base = base.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_');
  if (base.length > 48) base = base.substring(0, 48);
  final result = await ImageGallerySaverPlus.saveImage(
    bytes,
    quality: 100,
    name: base,
  );
  final ok = result is Map && (result['isSuccess'] == true || result['success'] == true);
  if (!ok) {
    throw Exception('写入相册失败');
  }
}
