import 'dart:io';

import 'package:super_editor/super_editor.dart';

import 'note_attachment_store.dart';

Future<List<int>?> loadImageNodeRawBytes(ImageNode node) async {
  final url = node.imageUrl;
  if (url.startsWith('minote://attachments/')) {
    final mem = NoteAttachmentStore.peekInlineImageBytes(url);
    if (mem != null && mem.isNotEmpty) return mem;
    final path = await NoteAttachmentStore.getLocalPath(url);
    if (path == null) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    return f.readAsBytes();
  }
  return null;
}
