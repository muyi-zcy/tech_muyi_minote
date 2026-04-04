import 'package:super_editor/super_editor.dart';

import 'mi_inline_image.dart';

/// 在 [SingleColumnStylesheetStyler] 之后运行，保证所有带文字的块都拿到 [miInlineImageBuilder]。
///
/// 仅靠 [Stylesheet.inlineWidgetBuilders] 时，若合并逻辑或中间阶段得到空链，占位仍会占字数但不会出现 [WidgetSpan]。
class MiInlineImageBuildersPhase extends SingleColumnLayoutStylePhase {
  static final InlineWidgetBuilderChain _fullChain = [
    miInlineImageBuilder,
    ...defaultInlineWidgetBuilderChain,
  ];

  @override
  SingleColumnLayoutViewModel style(Document document, SingleColumnLayoutViewModel viewModel) {
    return SingleColumnLayoutViewModel(
      padding: viewModel.padding,
      componentViewModels: [
        for (final vm in viewModel.componentViewModels) _patch(vm.copy()),
      ],
    );
  }

  SingleColumnLayoutComponentViewModel _patch(SingleColumnLayoutComponentViewModel vm) {
    if (vm is! TextComponentViewModel) return vm;

    final t = vm;
    final cur = t.inlineWidgetBuilders;
    // 用 == 去重，避免不同编译单元下 identical(mi) 失败导致未注入 builder。
    final rest = cur.where((b) => b != miInlineImageBuilder).toList();
    t.inlineWidgetBuilders = cur.isEmpty
        ? List<InlineWidgetBuilder>.from(_fullChain)
        : [miInlineImageBuilder, ...rest];
    return vm;
  }
}
