import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// 与 [TaskComponentBuilder] 一致；勾选框用与正文 [fontSize] 匹配的图标，并在首行行高内垂直居中。
class MiTaskComponentBuilder implements ComponentBuilder {
  MiTaskComponentBuilder(this._editor);

  final Editor _editor;

  @override
  TaskComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! TaskNode) {
      return null;
    }

    final textDirection = getParagraphDirection(node.text.toPlainText());

    return TaskComponentViewModel(
      nodeId: node.id,
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) {
        _editor.execute([
          ChangeTaskCompletionRequest(
            nodeId: node.id,
            isComplete: isComplete,
          ),
        ]);
      },
      text: node.text,
      textDirection: textDirection,
      textAlignment: textDirection == TextDirection.ltr ? TextAlign.left : TextAlign.right,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! TaskComponentViewModel) {
      return null;
    }

    return MiTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
    );
  }
}

class MiTaskComponent extends StatefulWidget {
  const MiTaskComponent({
    super.key,
    required this.viewModel,
    this.showDebugPaint = false,
  });

  final TaskComponentViewModel viewModel;
  final bool showDebugPaint;

  @override
  State<MiTaskComponent> createState() => _MiTaskComponentState();
}

class _MiTaskComponentState extends State<MiTaskComponent>
    with ProxyDocumentComponent<MiTaskComponent>, ProxyTextComposable {
  final _textKey = GlobalKey();

  @override
  GlobalKey<State<StatefulWidget>> get childDocumentComponentKey => _textKey;

  @override
  TextComposable get childTextComposable => childDocumentComponentKey.currentState as TextComposable;

  TextStyle _computeStyles(Set<Attribution> attributions) {
    final style = widget.viewModel.textStyleBuilder(attributions);
    return widget.viewModel.isComplete
        ? style.copyWith(
            decoration: style.decoration == null
                ? TextDecoration.lineThrough
                : TextDecoration.combine([TextDecoration.lineThrough, style.decoration!]),
          )
        : style;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle = widget.viewModel.textStyleBuilder({});
    final tp = TextPainter(
      text: TextSpan(text: '字', style: baseStyle),
      textDirection: widget.viewModel.textDirection,
    )..layout();
    final lineH = tp.height;
    final iconSize = (baseStyle.fontSize ?? 17) * 1.12;

    final done = widget.viewModel.isComplete;
    final toggle = widget.viewModel.setComplete;

    return Directionality(
      textDirection: widget.viewModel.textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: widget.viewModel.indentCalculator(
              widget.viewModel.textStyleBuilder({}),
              widget.viewModel.indent,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 6),
            child: SizedBox(
              height: lineH,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: toggle != null ? () => toggle(!done) : null,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: iconSize + 8,
                      height: iconSize + 8,
                      child: Center(
                        child: Icon(
                          done ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: iconSize,
                          color: done ? scheme.primary : scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: TextComponent(
              key: _textKey,
              text: widget.viewModel.text,
              textDirection: widget.viewModel.textDirection,
              textAlign: widget.viewModel.textAlignment,
              textStyleBuilder: _computeStyles,
              inlineWidgetBuilders: widget.viewModel.inlineWidgetBuilders,
              textSelection: widget.viewModel.selection,
              selectionColor: widget.viewModel.selectionColor,
              highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
              underlines: widget.viewModel.createUnderlines(),
              showDebugPaint: widget.showDebugPaint,
            ),
          ),
        ],
      ),
    );
  }
}
