import 'package:flutter/material.dart';

import 'local_image_inner.dart';

/// 行内图：文档中仅存 [ref]（`minote://…` / `blob:`），二进制在附件目录。
@immutable
class MiInlineImagePlaceholder {
  const MiInlineImagePlaceholder({
    required this.ref,
    this.caption = '',
  });

  final String ref;
  final String caption;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MiInlineImagePlaceholder &&
          ref == other.ref &&
          caption == other.caption;

  @override
  int get hashCode => Object.hash(ref, caption);
}

double _lineHeightFor(TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: '字', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.height;
}

/// 置于 [Styles.inlineWidgetBuilders] 首位，优先于网络图占位。
Widget? miInlineImageBuilder(BuildContext context, TextStyle textStyle, Object placeholder) {
  if (placeholder is! MiInlineImagePlaceholder) {
    return null;
  }

  final h = _lineHeightFor(textStyle);
  // 行内 Widget 需要明确宽高，否则在 SuperText 中可能得到零尺寸而不绘制。
  final w = (h * 2.4).clamp(40.0, 132.0);
  Widget core = SizedBox(
    width: w,
    height: h,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: buildLocalImage(
        context,
        placeholder.ref,
        decodeMaxLogical: w,
      ),
    ),
  );
  if (placeholder.caption.trim().isNotEmpty) {
    core = Tooltip(message: placeholder.caption.trim(), child: core);
  }
  return core;
}
