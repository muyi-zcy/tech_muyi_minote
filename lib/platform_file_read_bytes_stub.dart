import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Web 等无 dart:io 时仅使用 [PlatformFile.bytes]。
Future<Uint8List?> readPlatformFileBytes(PlatformFile f) async {
  final b = f.bytes;
  if (b != null && b.isNotEmpty) return b;
  return null;
}
