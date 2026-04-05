import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 应用文档目录下 `minote_attachments/`，笔记中只保存 `minote://attachments/<文件名>` 引用。
class NoteAttachmentStore {
  static Directory? _root;

  /// 刚写入附件的字节缓存，供行内图首帧 [Image.memory] 使用（不依赖磁盘同步与 [getLocalPathSync]）。
  static final List<String> _inlineBytesLru = [];
  static final Map<String, Uint8List> _inlineBytesByRef = {};
  static const int _inlineBytesMaxEntries = 48;

  static Uint8List? peekInlineImageBytes(String ref) {
    if (!ref.startsWith('minote://attachments/')) return null;
    return _inlineBytesByRef[ref];
  }

  static void _rememberInlineImageBytes(String ref, Uint8List bytes) {
    final copy = Uint8List.fromList(bytes);
    _inlineBytesLru.remove(ref);
    _inlineBytesLru.add(ref);
    _inlineBytesByRef[ref] = copy;
    while (_inlineBytesLru.length > _inlineBytesMaxEntries) {
      final evict = _inlineBytesLru.removeAt(0);
      _inlineBytesByRef.remove(evict);
    }
  }

  static Future<Directory> _dir() async {
    if (_root != null) return _root!;
    final base = await getApplicationDocumentsDirectory();
    _root = Directory('${base.path}/minote_attachments')..createSync(recursive: true);
    return _root!;
  }

  static Future<void> ensureInitialized() async {
    await _dir();
  }

  static Future<String> saveBytes(Uint8List bytes, String extension) async {
    final dir = await _dir();
    var ext = extension.trim().toLowerCase();
    if (ext.startsWith('.')) ext = ext.substring(1);
    if (ext.isEmpty) ext = 'bin';
    final name = '${const Uuid().v4()}.$ext';
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    final ref = 'minote://attachments/$name';
    _rememberInlineImageBytes(ref, bytes);
    return ref;
  }

  /// 将文档中的 [ref] 解析为本地绝对路径；非 `minote://` 或文件不存在时返回 null。
  static Future<String?> getLocalPath(String ref) async {
    if (!ref.startsWith('minote://attachments/')) return null;
    final name = ref.substring('minote://attachments/'.length);
    final root = await _dir();
    final f = File(p.join(root.path, name));
    if (f.existsSync()) return f.path;
    return null;
  }

  /// 路径存在且文件非空（录音刚落盘、ExoPlayer 对 0 字节易失败）。
  ///
  /// 停止录制后极短窗口内可能尚未刷盘，做几次短延迟重试再判定。
  static Future<String?> getReadyLocalPath(String ref) async {
    const delaysMs = <int>[0, 40, 100, 200, 350];
    for (final wait in delaysMs) {
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      final path = await getLocalPath(ref);
      if (path == null) continue;
      try {
        final len = await File(path).length();
        if (len > 0) return path;
      } catch (_) {}
    }
    return null;
  }

  /// 在 [ensureInitialized] / [saveBytes] 之后可在同步布局中解析路径（行内图等）。
  static String? getLocalPathSync(String ref) {
    if (!ref.startsWith('minote://attachments/')) return null;
    final root = _root;
    if (root == null) return null;
    final name = ref.substring('minote://attachments/'.length);
    final f = File(p.join(root.path, name));
    return f.existsSync() ? f.path : null;
  }

  /// 录音文件直接写入附件目录，停止录制后配合 [documentRefFromRecorderOutput] 得到文档引用。
  static Future<String> recordingOutputAbsolutePath(String extension) async {
    final dir = await _dir();
    var ext = extension.trim().toLowerCase();
    if (ext.startsWith('.')) ext = ext.substring(1);
    if (ext.isEmpty) ext = 'm4a';
    final name = '${const Uuid().v4()}.$ext';
    return p.join(dir.path, name);
  }

  /// 删除 [ref] 对应的附件文件（若存在）。用于取消未插入正文的录音等。
  static Future<void> deleteByRefIfExists(String ref) async {
    final path = await getLocalPath(ref);
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// [stopOutput] 为 `AudioRecorder.stop()` 的返回值（IO 为绝对路径，Web 为 `blob:` URL）。
  static String documentRefFromRecorderOutput(String stopOutput) {
    if (stopOutput.startsWith('blob:') || stopOutput.startsWith('http')) {
      return stopOutput;
    }
    return 'minote://attachments/${p.basename(stopOutput)}';
  }
}
