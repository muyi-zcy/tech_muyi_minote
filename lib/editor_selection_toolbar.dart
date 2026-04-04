import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'mi_note_image_layout.dart';

/// 选区上方浮动条：文本选区为 剪切/复制/粘贴/全选；单张块图选区为 半宽·全宽/复制(真实图片)/粘贴/全选。
class MiEditorFloatingToolbar extends StatelessWidget {
  const MiEditorFloatingToolbar({
    super.key,
    required this.toolbarKey,
    required this.selectionListenable,
    required this.document,
    required this.commonOps,
    required this.onAfterAction,
    required this.onPasteWithImageFirst,
    required this.onCopyImagePixels,
    required this.onToggleImageHalfFullWidth,
  });

  final Key? toolbarKey;
  final ValueListenable<DocumentSelection?> selectionListenable;
  final Document document;
  final CommonEditorOperations commonOps;
  final VoidCallback onAfterAction;

  /// 先尝试剪贴板图片插入，否则走系统文本粘贴。
  final Future<void> Function() onPasteWithImageFirst;

  /// 将当前选中的块图以像素数据写入剪贴板（非 URL 文本）。
  final Future<void> Function() onCopyImagePixels;

  /// 当前选中块图时在半宽 / 全宽之间切换。
  final VoidCallback onToggleImageHalfFullWidth;

  static bool _isSingleImageSelection(Document doc, DocumentSelection? sel) {
    if (sel == null) return false;
    final nodes = doc.getNodesInside(sel.base, sel.extent);
    if (nodes.length != 1) return false;
    return nodes.first is ImageNode;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final surface = brightness == Brightness.dark
        ? scheme.surfaceContainerHigh
        : scheme.surface;

    return ValueListenableBuilder<DocumentSelection?>(
      valueListenable: selectionListenable,
      builder: (context, selection, _) {
        final imageMode = _isSingleImageSelection(document, selection);
        final hasTextRange = selection != null && !selection.isCollapsed && !imageMode;

        double? widthFactor;
        if (imageMode && selection != null) {
          final node = document.getNodeById(selection.extent.nodeId);
          if (node is ImageNode) {
            widthFactor = miImageWidthFactorFromMetadata(node.metadata);
          }
        }
        final showFullWidthAction = widthFactor != null && widthFactor < 0.75;

        return Material(
          key: toolbarKey,
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          color: surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (imageMode) ...[
                  _item(
                    context,
                    icon: showFullWidthAction ? Icons.open_in_full_rounded : Icons.picture_in_picture_alt_rounded,
                    label: showFullWidthAction ? '全宽' : '半宽',
                    onPressed: () {
                      onToggleImageHalfFullWidth();
                      onAfterAction();
                    },
                  ),
                  _item(
                    context,
                    icon: Icons.content_copy_rounded,
                    label: '复制',
                    onPressed: () async {
                      await onCopyImagePixels();
                      onAfterAction();
                    },
                  ),
                ],
                if (hasTextRange)
                  _item(
                    context,
                    icon: Icons.content_cut_rounded,
                    label: '剪切',
                    onPressed: () {
                      commonOps.cut();
                      onAfterAction();
                    },
                  ),
                if (hasTextRange)
                  _item(
                    context,
                    icon: Icons.content_copy_rounded,
                    label: '复制',
                    onPressed: () {
                      commonOps.copy();
                      onAfterAction();
                    },
                  ),
                _item(
                  context,
                  icon: Icons.content_paste_rounded,
                  label: '粘贴',
                  onPressed: () async {
                    await onPasteWithImageFirst();
                    onAfterAction();
                  },
                ),
                _item(
                  context,
                  icon: Icons.select_all_rounded,
                  label: '全选',
                  onPressed: () {
                    commonOps.selectAll();
                    onAfterAction();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.87);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
