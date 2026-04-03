import 'package:flutter/painting.dart';
import 'package:super_editor/super_editor.dart';

/// 将换行规范为 `\n` 后再判断「是否仅一个换行」「是否以双换行结尾」。
String _normalizeNewlines(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

bool _normalizedIsOnlySingleLineBreak(String raw) => _normalizeNewlines(raw) == '\n';

bool _normalizedEndsWithDoubleLineBreak(String raw) => _normalizeNewlines(raw).endsWith('\n\n');

/// [raw] 中向前累计 [normTarget] 个「规范化字符」（`\r\n` 计 1 个换行）后的 UTF-16 下标。
int _rawOffsetAtNormalizedIndex(String raw, int normTarget) {
  if (normTarget <= 0) return 0;
  var ri = 0;
  var ni = 0;
  while (ri < raw.length && ni < normTarget) {
    if (raw.startsWith('\r\n', ri)) {
      ri += 2;
    } else {
      ri += 1;
    }
    ni += 1;
  }
  return ri;
}

/// 在默认 [defaultRequestHandlers] 之前注册：仅当光标在引用块内时接管回车（[InsertNewlineAtCaretRequest]）。
EditCommand? insertNewlineInBlockquoteRequestHandler(Editor editor, EditRequest request) {
  if (request is! InsertNewlineAtCaretRequest) return null;
  final selection = editor.composer.selection;
  if (selection == null) return null;
  final node = editor.document.getNodeById(selection.extent.nodeId);
  if (node is! ParagraphNode) return null;
  if (node.getMetadataValue('blockType') != blockquoteAttribution) return null;
  return InsertNewlineInBlockquoteAtCaretCommand(request.newNodeId);
}

/// 部分平台（或 IME）用 [InsertTextRequest] 插入 `\n` 而不是 [InsertNewlineAtCaretRequest]，需同样接管。
EditCommand? insertTextNewlineInBlockquoteRequestHandler(Editor editor, EditRequest request) {
  if (request is! InsertTextRequest) return null;
  var ins = request.textToInsert;
  if (ins == '\r\n' || ins == '\r') {
    ins = '\n';
  }
  if (ins != '\n') return null;

  final sel = editor.composer.selection;
  if (sel == null || !sel.isCollapsed) return null;

  final extent = sel.extent;
  if (extent.nodeId != request.documentPosition.nodeId) return null;

  final node = editor.document.getNodeById(extent.nodeId);
  if (node is! ParagraphNode) return null;
  if (node.getMetadataValue('blockType') != blockquoteAttribution) return null;

  return const BlockquoteNewlineFromInsertTextCommand();
}

/// 引用内回车：同一 [ParagraphNode] 内插入 `\n`，只显示一个「"」；
/// 光标在**段末**且正文已以 `\n\n` 结尾（或整段仅为 `\n`）时再按一次则退出引用。
class InsertNewlineInBlockquoteAtCaretCommand extends BaseInsertNewlineAtCaretCommand {
  const InsertNewlineInBlockquoteAtCaretCommand(this.newNodeId);

  final String newNodeId;

  @override
  void doInsertNewline(
    EditContext context,
    CommandExecutor executor,
    DocumentPosition caretPosition,
    NodePosition caretNodePosition,
  ) {
    insertBlockquoteNewline(
      context,
      executor,
      caretPosition,
      caretNodePosition,
      newNodeId,
    );
  }
}

/// 与 [InsertNewlineInBlockquoteAtCaretCommand] 相同逻辑，但从 [InsertTextRequest]（插入 `\n`）进入。
class BlockquoteNewlineFromInsertTextCommand extends EditCommand {
  const BlockquoteNewlineFromInsertTextCommand();

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) {
    final documentSelection = context.composer.selection;
    if (documentSelection == null) return;

    final selectedNodes = context.document.getNodesInside(documentSelection.base, documentSelection.extent);
    for (final node in selectedNodes) {
      if (!node.isDeletable) return;
    }

    if (!documentSelection.isCollapsed) {
      executor.executeCommand(DeleteSelectionCommand(affinity: TextAffinity.downstream));
    }

    final caret = context.composer.selection?.extent;
    if (caret == null) return;
    final caretNodePosition = caret.nodePosition;

    insertBlockquoteNewline(
      context,
      executor,
      caret,
      caretNodePosition,
      Editor.createNodeId(),
    );
  }
}

void insertBlockquoteNewline(
  EditContext context,
  CommandExecutor executor,
  DocumentPosition caretPosition,
  NodePosition caretNodePosition,
  String newNodeId,
) {
  if (caretNodePosition is! UpstreamDownstreamNodePosition && caretNodePosition is! TextNodePosition) {
    return;
  }

  if (caretNodePosition is UpstreamDownstreamNodePosition) {
    _insertNewlineAtBlockEdge(context, executor, caretPosition, caretNodePosition, newNodeId);
    return;
  }

  final node = context.document.getNodeById(caretPosition.nodeId);
  if (caretNodePosition is TextNodePosition && node is TextNode) {
    _insertInBlockquoteText(context, executor, node, caretPosition, caretNodePosition, newNodeId);
  }
}

void _insertNewlineAtBlockEdge(
  EditContext context,
  CommandExecutor executor,
  DocumentPosition caretPosition,
  UpstreamDownstreamNodePosition caretNodePosition,
  String newNodeId,
) {
  if (caretNodePosition.affinity == TextAffinity.upstream) {
    executor
      ..executeCommand(
        InsertNodeBeforeNodeCommand(
          existingNodeId: caretPosition.nodeId,
          newNode: ParagraphNode(
            id: newNodeId,
            text: AttributedText(),
          ),
        ),
      )
      ..executeCommand(
        ChangeSelectionCommand(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: newNodeId,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      );
  } else {
    executor
      ..executeCommand(
        InsertNodeAfterNodeCommand(
          existingNodeId: caretPosition.nodeId,
          newNode: ParagraphNode(
            id: newNodeId,
            text: AttributedText(),
          ),
        ),
      )
      ..executeCommand(
        ChangeSelectionCommand(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: newNodeId,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      );
  }
}

void _insertInBlockquoteText(
  EditContext context,
  CommandExecutor executor,
  TextNode textNode,
  DocumentPosition caretPosition,
  TextNodePosition caretTextPosition,
  String newSiblingNodeId,
) {
  final raw = textNode.text.toPlainText();
  final offset = caretTextPosition.offset;
  final atEnd = offset == raw.length;

  if (atEnd && (_normalizedIsOnlySingleLineBreak(raw) || _normalizedEndsWithDoubleLineBreak(raw))) {
    if (raw.trim().isEmpty || _normalizedIsOnlySingleLineBreak(raw)) {
      executor.executeCommand(
        ReplaceNodeWithEmptyParagraphWithCaretCommand(nodeId: caretPosition.nodeId),
      );
      return;
    }

    if (_normalizedEndsWithDoubleLineBreak(raw)) {
      final n = _normalizeNewlines(raw);
      final normKeepLen = n.length - 2;
      final splitRawOffset = _rawOffsetAtNormalizedIndex(raw, normKeepLen);
      if (splitRawOffset <= 0) {
        executor.executeCommand(
          ReplaceNodeWithEmptyParagraphWithCaretCommand(nodeId: caretPosition.nodeId),
        );
        return;
      }

      executor
        ..executeCommand(
          SplitParagraphCommand(
            nodeId: textNode.id,
            splitPosition: TextNodePosition(offset: splitRawOffset),
            newNodeId: newSiblingNodeId,
            replicateExistingMetadata: false,
          ),
        )
        ..executeCommand(
          ReplaceNodeCommand(
            existingNodeId: newSiblingNodeId,
            newNode: ParagraphNode(
              id: newSiblingNodeId,
              text: AttributedText(),
            ),
          ),
        );
      return;
    }
  }

  executor.executeCommand(
    InsertTextCommand(
      documentPosition: caretPosition,
      textToInsert: '\n',
      attributions: {},
    ),
  );
}
