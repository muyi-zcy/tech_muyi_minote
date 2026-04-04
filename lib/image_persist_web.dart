import 'dart:html' as html;
import 'dart:typed_data';

/// Web 无本地文件路径，使用 `blob:` 对象 URL 作为可加载的地址（非 base64）。
Future<String> persistImageBytes(Uint8List bytes, String fileExtension) async {
  var ext = fileExtension.trim().toLowerCase();
  if (ext.startsWith('.')) ext = ext.substring(1);
  final mime = ext == 'png'
      ? 'image/png'
      : (ext == 'jpg' || ext == 'jpeg')
          ? 'image/jpeg'
          : 'image/jpeg';
  final blob = html.Blob([bytes], mime);
  return html.Url.createObjectUrlFromBlob(blob);
}
