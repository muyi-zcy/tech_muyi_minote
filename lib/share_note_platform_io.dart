import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

Future<String> savePngBytesToLocal(Uint8List bytes, {String? suggestedBaseName}) async {
  final now = DateTime.now();
  final defaultBase =
      '笔记_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  var base = (suggestedBaseName?.trim().isNotEmpty ?? false) ? suggestedBaseName!.trim() : defaultBase;
  base = base.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_');
  if (base.length > 48) base = base.substring(0, 48);
  final fileName = '$base.png';

  final candidates = <Directory?>[
    await getDownloadsDirectory(),
    await getApplicationDocumentsDirectory(),
    await getTemporaryDirectory(),
  ];
  Directory? targetDir;
  for (final dir in candidates) {
    if (dir == null) continue;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    targetDir = dir;
    break;
  }
  if (targetDir == null) {
    throw Exception('无法定位保存目录');
  }

  final path = '${targetDir.path}/$fileName';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
