import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 带左上角装饰双引号的引用块（参考小米笔记样式）。
class MiBlockquoteComponentBuilder implements ComponentBuilder {
  const MiBlockquoteComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! ParagraphNode) return null;
    if (node.getMetadataValue('blockType') != blockquoteAttribution) return null;

    final textDirection = getParagraphDirection(node.text.toPlainText());

    TextAlign textAlign = (textDirection == TextDirection.ltr) ? TextAlign.left : TextAlign.right;
    final textAlignName = node.getMetadataValue('textAlign');
    switch (textAlignName) {
      case 'left':
        textAlign = TextAlign.left;
      case 'center':
        textAlign = TextAlign.center;
      case 'right':
        textAlign = TextAlign.right;
      case 'justify':
        textAlign = TextAlign.justify;
    }

    return BlockquoteComponentViewModel(
      nodeId: node.id,
      text: node.text,
      textStyleBuilder: noStyleBuilder,
      indent: node.indent,
      backgroundColor: const Color(0x00000000),
      borderRadius: BorderRadius.zero,
      textDirection: textDirection,
      textAlignment: textAlign,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! BlockquoteComponentViewModel) return null;

    return _MiBlockquoteComponent(
      textKey: componentContext.componentKey,
      text: componentViewModel.text,
      styleBuilder: componentViewModel.textStyleBuilder,
      indent: componentViewModel.indent,
      indentCalculator: componentViewModel.indentCalculator,
      backgroundColor: componentViewModel.backgroundColor,
      borderRadius: componentViewModel.borderRadius,
      textSelection: componentViewModel.selection,
      selectionColor: componentViewModel.selectionColor,
      highlightWhenEmpty: componentViewModel.highlightWhenEmpty,
      underlines: componentViewModel.createUnderlines(),
      textAlign: componentViewModel.textAlignment,
      textDirection: componentViewModel.textDirection,
      inlineWidgetBuilders: componentViewModel.inlineWidgetBuilders,
    );
  }
}

class _MiBlockquoteComponent extends StatelessWidget {
  const _MiBlockquoteComponent({
    required this.textKey,
    required this.text,
    required this.styleBuilder,
    required this.indent,
    required this.indentCalculator,
    required this.backgroundColor,
    required this.borderRadius,
    this.textSelection,
    required this.selectionColor,
    required this.highlightWhenEmpty,
    required this.underlines,
    required this.textAlign,
    required this.textDirection,
    required this.inlineWidgetBuilders,
  });

  final GlobalKey textKey;
  final AttributedText text;
  final AttributionStyleBuilder styleBuilder;
  final int indent;
  final TextBlockIndentCalculator indentCalculator;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final TextSelection? textSelection;
  final Color selectionColor;
  final bool highlightWhenEmpty;
  final List<Underlines> underlines;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final InlineWidgetBuilderChain inlineWidgetBuilders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quoteColor = scheme.onSurface.withValues(alpha: 0.28);

    // 与默认 [BlockquoteComponent] 一致：整块不参与命中测试，由 SuperEditor 文档手势层处理
    // 选区/拖动；否则左侧装饰字会抢走命中，导致引用内无法选中文字。
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: backgroundColor,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 0),
              child: Text(
                '\u201C',
                style: TextStyle(
                  fontSize: 36,
                  height: 1.0,
                  fontWeight: FontWeight.w200,
                  color: quoteColor,
                ),
              ),
            ),
            SizedBox(
              width: indentCalculator(
                styleBuilder({}),
                indent,
              ),
            ),
            Expanded(
              child: TextComponent(
                key: textKey,
                text: text,
                textAlign: textAlign,
                textDirection: textDirection,
                textStyleBuilder: styleBuilder,
                inlineWidgetBuilders: inlineWidgetBuilders,
                metadata: const {'blockType': blockquoteAttribution},
                textSelection: textSelection,
                selectionColor: selectionColor,
                highlightWhenEmpty: highlightWhenEmpty,
                underlines: underlines,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
