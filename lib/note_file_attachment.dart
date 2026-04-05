import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'voice_attachment_playback.dart';

/// 语音等附件：仅引用 [minoteRef]（或 Web 的 `blob:`），二进制在专用目录 / Blob，不在文档 JSON 内嵌。
@immutable
class FileAttachmentNode extends BlockNode {
  FileAttachmentNode({
    required this.id,
    required this.minoteRef,
    required this.displayLabel,
    this.waveformPeaks,
    super.metadata,
  }) {
    initAddToMetadata({'blockType': const NamedAttribution('fileAttachment')});
  }

  @override
  final String id;

  final String minoteRef;
  final String displayLabel;

  /// 录音时采样的归一化峰值（约 72 点），用于波形展示；旧笔记为 null。
  final List<double>? waveformPeaks;

  @override
  String? copyContent(NodeSelection selection) {
    if (selection is! UpstreamDownstreamNodeSelection) {
      throw Exception('FileAttachmentNode expects UpstreamDownstreamNodeSelection');
    }
    return !selection.isCollapsed ? displayLabel : null;
  }

  @override
  bool hasEquivalentContent(DocumentNode other) {
    return other is FileAttachmentNode &&
        minoteRef == other.minoteRef &&
        listEquals(waveformPeaks, other.waveformPeaks);
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return FileAttachmentNode(
      id: id,
      minoteRef: minoteRef,
      displayLabel: displayLabel,
      waveformPeaks: waveformPeaks,
      metadata: {...metadata, ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return FileAttachmentNode(
      id: id,
      minoteRef: minoteRef,
      displayLabel: displayLabel,
      waveformPeaks: waveformPeaks,
      metadata: newMetadata,
    );
  }

  FileAttachmentNode copy() {
    return FileAttachmentNode(
      id: id,
      minoteRef: minoteRef,
      displayLabel: displayLabel,
      waveformPeaks: waveformPeaks == null ? null : List<double>.from(waveformPeaks!),
      metadata: Map.from(metadata),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileAttachmentNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          minoteRef == other.minoteRef &&
          displayLabel == other.displayLabel &&
          listEquals(waveformPeaks, other.waveformPeaks);

  @override
  int get hashCode => Object.hash(
        id,
        minoteRef,
        displayLabel,
        Object.hashAll(waveformPeaks ?? const <double>[]),
      );
}

class FileAttachmentComponentBuilder implements ComponentBuilder {
  const FileAttachmentComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! FileAttachmentNode) {
      return null;
    }
    return FileAttachmentComponentViewModel(
      nodeId: node.id,
      minoteRef: node.minoteRef,
      displayLabel: node.displayLabel,
      waveformPeaks: node.waveformPeaks,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! FileAttachmentComponentViewModel) {
      return null;
    }
    return FileAttachmentComponent(
      componentKey: componentContext.componentKey,
      minoteRef: componentViewModel.minoteRef,
      displayLabel: componentViewModel.displayLabel,
      waveformPeaks: componentViewModel.waveformPeaks,
      selection: componentViewModel.selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
      selectionColor: componentViewModel.selectionColor,
    );
  }
}

class FileAttachmentComponentViewModel extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  FileAttachmentComponentViewModel({
    required super.nodeId,
    super.maxWidth,
    super.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    required this.minoteRef,
    required this.displayLabel,
    this.waveformPeaks,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) {
    this.selection = selection;
    this.selectionColor = selectionColor;
  }

  final String minoteRef;
  final String displayLabel;
  final List<double>? waveformPeaks;

  @override
  FileAttachmentComponentViewModel copy() {
    return FileAttachmentComponentViewModel(
      nodeId: nodeId,
      maxWidth: maxWidth,
      padding: padding,
      minoteRef: minoteRef,
      displayLabel: displayLabel,
      waveformPeaks: waveformPeaks,
      selection: selection,
      selectionColor: selectionColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is FileAttachmentComponentViewModel &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          minoteRef == other.minoteRef &&
          displayLabel == other.displayLabel &&
          listEquals(waveformPeaks, other.waveformPeaks) &&
          selection == other.selection &&
          selectionColor == other.selectionColor;

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        nodeId,
        minoteRef,
        displayLabel,
        Object.hashAll(waveformPeaks ?? const <double>[]),
        selection,
        selectionColor,
      );
}

class FileAttachmentComponent extends StatelessWidget {
  const FileAttachmentComponent({
    super.key,
    required this.componentKey,
    required this.minoteRef,
    required this.displayLabel,
    this.waveformPeaks,
    this.selectionColor = Colors.blue,
    this.selection,
  });

  final GlobalKey componentKey;
  final String minoteRef;
  final String displayLabel;
  final List<double>? waveformPeaks;
  final Color selectionColor;
  final UpstreamDownstreamNodeSelection? selection;

  @override
  Widget build(BuildContext context) {
    // 不可使用 [SelectableBox]：其实现为 `IgnorePointer` 包住子组件，触摸永远不会到达
    // [VoiceAttachmentPlaybackTile] 的 [InkWell]（故「点了没反应、也无日志」）。
    // 选区高亮用顶层 `IgnorePointer` 装饰，使点击穿透到下方语音条。
    final isSelected = selection != null && !selection!.isCollapsed;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        BoxComponent(
          key: componentKey,
          child: VoiceAttachmentPlaybackTile(
            minoteRef: minoteRef,
            displayLabel: displayLabel,
            waveformPeaks: waveformPeaks,
          ),
        ),
        if (isSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selectionColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
