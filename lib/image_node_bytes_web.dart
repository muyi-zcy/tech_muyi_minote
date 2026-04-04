import 'dart:html' as html;

import 'package:super_editor/super_editor.dart';

Future<List<int>?> loadImageNodeRawBytes(ImageNode node) async {
  final url = node.imageUrl;
  if (url.startsWith('blob:') || url.startsWith('http://') || url.startsWith('https://')) {
    try {
      final r = await html.HttpRequest.request(
        url,
        responseType: 'arraybuffer',
      );
      return r.response as List<int>?;
    } catch (_) {
      return null;
    }
  }
  return null;
}
