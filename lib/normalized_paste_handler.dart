import 'package:super_editor/super_editor.dart';

/// 将剪贴板文本中的换行统一为 `\n`，再交给 [PasteEditorCommand]，以便按行拆成多个 [ParagraphNode]。
///
/// 仅 `split('\\n')` 时，`a\\r\\nb` 能分段，但 `a\\rb`（仅 `\\r`）或 Unicode 行/段分隔符会整段粘贴。
String normalizePastedPlainText(String content) {
  return content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u2028', '\n')
      .replaceAll('\u2029', '\n');
}

/// 放在 [defaultRequestHandlers] 之前：拦截 [PasteEditorRequest] 并规范化换行。
EditCommand? normalizedPasteRequestHandler(Editor editor, EditRequest request) {
  if (request is! PasteEditorRequest) return null;
  final normalized = normalizePastedPlainText(request.content);
  return PasteEditorCommand(
    content: normalized,
    pastePosition: request.pastePosition,
  );
}

/// 系统/IME 粘贴多行时往往走 [InsertTextRequest]（整串含 `\\n` 插入同一节点），不会走 [PasteEditorRequest]。
/// 在「仅一个 `\\n`」之外、且文本中含换行时，改为 [PasteEditorCommand] 按行拆成多个 [ParagraphNode]。
///
/// 须放在 [insertTextNewlineInBlockquoteRequestHandler] 之后：单独按一次换行仍由引用逻辑处理。
EditCommand? insertTextMultilineAsParagraphsHandler(Editor editor, EditRequest request) {
  if (request is! InsertTextRequest) return null;
  final text = normalizePastedPlainText(request.textToInsert);
  if (text == '\n') {
    return null;
  }
  if (!text.contains('\n')) {
    return null;
  }

  final pos = request.documentPosition;
  final node = editor.document.getNodeById(pos.nodeId);
  if (node is! TextNode) {
    return null;
  }

  return PasteEditorCommand(
    content: text,
    pastePosition: pos,
  );
}
