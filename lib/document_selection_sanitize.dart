import 'package:super_editor/super_editor.dart';

/// 保证 [DocumentSelection] 与当前 [Document] 中节点类型一致，避免
/// `TextComponent` 收到 [UpstreamDownstreamNodePosition] 或块节点收到 [TextNodePosition] 而抛错。
DocumentSelection? sanitizeDocumentSelection(
  Document document,
  DocumentSelection? selection,
) {
  if (selection == null) return null;

  DocumentPosition? fix(DocumentPosition p) {
    final node = document.getNodeById(p.nodeId);
    if (node == null) return null;
    if (node.containsPosition(p.nodePosition)) return p;

    if (node is TextNode) {
      final len = node.text.length;
      var offset = 0;
      final np = p.nodePosition;
      if (np is TextNodePosition) {
        offset = np.offset.clamp(0, len);
      }
      return DocumentPosition(
        nodeId: p.nodeId,
        nodePosition: TextNodePosition(offset: offset),
      );
    }

    if (node is BlockNode) {
      return DocumentPosition(
        nodeId: p.nodeId,
        nodePosition: const UpstreamDownstreamNodePosition.downstream(),
      );
    }

    return DocumentPosition(
      nodeId: p.nodeId,
      nodePosition: node.endPosition,
    );
  }

  final base = fix(selection.base);
  final extent = fix(selection.extent);

  if (base == null && extent == null) {
    return _fallbackCaretInFirstTextNode(document);
  }
  if (base == null) {
    return DocumentSelection.collapsed(position: extent!);
  }
  if (extent == null) {
    return DocumentSelection.collapsed(position: base);
  }

  if (selection.isCollapsed || (base.nodeId == extent.nodeId && base == extent)) {
    return DocumentSelection.collapsed(position: base);
  }

  return DocumentSelection(base: base, extent: extent);
}

DocumentSelection? _fallbackCaretInFirstTextNode(Document document) {
  for (final node in document) {
    if (node is TextNode) {
      return DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: node.text.length),
        ),
      );
    }
  }
  return null;
}
