import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalFileBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
