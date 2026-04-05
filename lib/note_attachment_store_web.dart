import 'dart:html' as html;
import 'dart:typed_data';

/// Web 无本地路径，将字节写入 Blob 后使用 `blob:` URL；文档内仅存该 URL 字符串，不存 base64。
class NoteAttachmentStore {
  static Future<void> ensureInitialized() async {}

  static Future<String> saveBytes(Uint8List bytes, String extension) async {
    final mime = _mimeForExt(extension);
    final blob = html.Blob([bytes], mime);
    return html.Url.createObjectUrlFromBlob(blob);
  }

  static Future<String?> getLocalPath(String ref) async => null;

  static Future<String?> getReadyLocalPath(String ref) async => null;

  static String? getLocalPathSync(String ref) => null;

  static Uint8List? peekInlineImageBytes(String _) => null;

  static Future<String> recordingOutputAbsolutePath(String extension) async =>
      'web_recording_placeholder';

  static String documentRefFromRecorderOutput(String stopOutput) => stopOutput;

  static Future<void> deleteByRefIfExists(String ref) async {}

  static String _mimeForExt(String extension) {
    var ext = extension.trim().toLowerCase();
    if (ext.startsWith('.')) ext = ext.substring(1);
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }
}
