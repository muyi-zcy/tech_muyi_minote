import 'package:flutter/material.dart';

/// 正文内可用的富文本操作（底部二级菜单与浮动菜单共用）。
enum NoteEditorFormat {
  h1,
  h2,
  h3,
  bold,
  italic,
  underline,
  strikethrough,
  bulletList,
  numberedList,
  horizontalRule,
  blockquote,
  alignLeft,
  alignCenter,
  alignRight,
  indent,
  outdent,
}

/// 小米风格：白底圆角条 + 阴影，内嵌横向滚动的二级格式按钮行。
class NoteEditorFormatPill extends StatelessWidget {
  const NoteEditorFormatPill({
    super.key,
    this.toolbarKey,
    required this.onAction,
    required this.onClose,
    this.showClose = true,
  });

  final Key? toolbarKey;
  final void Function(NoteEditorFormat action) onAction;
  final VoidCallback onClose;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final iconColor = scheme.onSurface.withValues(alpha: 0.88);
    final subtle = scheme.onSurface.withValues(alpha: 0.45);

    final bg = brightness == Brightness.dark ? scheme.surfaceContainerHigh : Colors.white;

    Widget miniLabel(String text, NoteEditorFormat kind) {
      return InkWell(
        onTap: () => onAction(kind),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: iconColor,
            ),
          ),
        ),
      );
    }

    Widget ib(IconData icon, String tip, NoteEditorFormat kind, Color color) {
      return IconButton(
        onPressed: () => onAction(kind),
        icon: Icon(icon, size: 22, color: color),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        tooltip: tip,
      );
    }

    return Material(
      key: toolbarKey,
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 48),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: brightness == Brightness.dark ? 0.35 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    miniLabel('H1', NoteEditorFormat.h1),
                    miniLabel('H2', NoteEditorFormat.h2),
                    miniLabel('H3', NoteEditorFormat.h3),
                    ib(Icons.format_bold_rounded, '加粗', NoteEditorFormat.bold, iconColor),
                    ib(Icons.format_italic_rounded, '斜体', NoteEditorFormat.italic, iconColor),
                    ib(Icons.format_underlined_rounded, '下划线', NoteEditorFormat.underline, iconColor),
                    ib(Icons.strikethrough_s_rounded, '删除线', NoteEditorFormat.strikethrough, iconColor),
                    ib(Icons.format_list_bulleted_rounded, '无序列表', NoteEditorFormat.bulletList, iconColor),
                    ib(Icons.format_list_numbered_rounded, '有序列表', NoteEditorFormat.numberedList, iconColor),
                    ib(Icons.horizontal_rule_rounded, '分割线', NoteEditorFormat.horizontalRule, iconColor),
                    ib(Icons.format_quote_rounded, '引用', NoteEditorFormat.blockquote, iconColor),
                    ib(Icons.format_align_left_rounded, '左对齐', NoteEditorFormat.alignLeft, iconColor),
                    ib(Icons.format_align_center_rounded, '居中', NoteEditorFormat.alignCenter, iconColor),
                    ib(Icons.format_align_right_rounded, '右对齐', NoteEditorFormat.alignRight, iconColor),
                    ib(Icons.format_indent_increase_rounded, '增加缩进', NoteEditorFormat.indent, iconColor),
                    ib(Icons.format_indent_decrease_rounded, '减少缩进', NoteEditorFormat.outdent, subtle),
                  ],
                ),
              ),
            ),
            if (showClose) ...[
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: scheme.outline.withValues(alpha: 0.35),
              ),
              IconButton(
                onPressed: onClose,
                tooltip: '关闭',
                icon: Icon(Icons.close_rounded, color: iconColor, size: 22),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
