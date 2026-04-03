import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 选区上方浮动条：剪切 / 复制 / 粘贴 / 全选，左侧为图标、右侧为中文标签。
class MiEditorFloatingToolbar extends StatelessWidget {
  const MiEditorFloatingToolbar({
    super.key,
    required this.toolbarKey,
    required this.selectionListenable,
    required this.commonOps,
    required this.onAfterAction,
  });

  final Key? toolbarKey;
  final ValueListenable<DocumentSelection?> selectionListenable;
  final CommonEditorOperations commonOps;
  final VoidCallback onAfterAction;

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
        final hasRange = selection != null && !selection.isCollapsed;
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
                if (hasRange)
                  _item(
                    context,
                    icon: Icons.content_cut_rounded,
                    label: '剪切',
                    onPressed: () {
                      commonOps.cut();
                      onAfterAction();
                    },
                  ),
                if (hasRange)
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
                  onPressed: () {
                    commonOps.paste();
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
