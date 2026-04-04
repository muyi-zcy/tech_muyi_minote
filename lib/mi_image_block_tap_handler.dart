import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 块级 [ImageNode] 在 super_editor 中 [isVisualSelectionSupported] 为 false，
/// Android [_onTapUp] 会 [moveSelectionToNearestSelectableNode] 把选区移回正文。
/// 在 [contentTapDelegateFactories] 中置于首位并 [halt]，自行设置选区并弹出工具条。
class MiImageBlockTapHandler extends ContentTapDelegate {
  MiImageBlockTapHandler(
    this._ctx, {
    required this.androidControls,
    required this.iosControls,
  });

  final SuperEditorContext _ctx;
  final SuperEditorAndroidControlsController? androidControls;
  final SuperEditorIosControlsController? iosControls;

  bool _isImageAt(Offset layoutOffset, DocumentLayout layout) {
    final pos = layout.getDocumentPositionNearestToOffset(layoutOffset);
    if (pos == null) return false;
    return _ctx.document.getNodeById(pos.nodeId) is ImageNode;
  }

  void _selectImageBlock(String nodeId) {
    // 扩展的 UpstreamDownstream 选区会让 AndroidHandlesDocumentLayer 走「双柄」分支并调用
    // selectUpstreamPosition，其要求 TextNodePosition，从而在块图上抛错。折叠 + downstream 与
    // getEdgeForPosition 兼容；showCollapsedHandle 避免仍显示扩展柄状态。
    _ctx.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: nodeId,
            nodePosition: const UpstreamDownstreamNodePosition.downstream(),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
    androidControls
      ?..hideExpandedHandles()
      ..showCollapsedHandle()
      ..showToolbar();
    iosControls?.showToolbar();
  }

  @override
  TapHandlingInstruction onTap(DocumentTapDetails details) {
    final layout = details.documentLayout;
    final pos = layout.getDocumentPositionNearestToOffset(details.layoutOffset);
    if (pos == null) return TapHandlingInstruction.continueHandling;
    if (_ctx.document.getNodeById(pos.nodeId) is! ImageNode) {
      return TapHandlingInstruction.continueHandling;
    }
    _selectImageBlock(pos.nodeId);
    return TapHandlingInstruction.halt;
  }

  @override
  TapHandlingInstruction onDoubleTap(DocumentTapDetails details) {
    if (_isImageAt(details.layoutOffset, details.documentLayout)) {
      return TapHandlingInstruction.halt;
    }
    return TapHandlingInstruction.continueHandling;
  }

  @override
  TapHandlingInstruction onTripleTap(DocumentTapDetails details) {
    if (_isImageAt(details.layoutOffset, details.documentLayout)) {
      return TapHandlingInstruction.halt;
    }
    return TapHandlingInstruction.continueHandling;
  }
}
