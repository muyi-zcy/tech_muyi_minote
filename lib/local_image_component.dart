import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'local_image_inner.dart';
import 'mi_note_image_layout.dart';

/// 与 [ImageComponentBuilder] 相同，但支持 `minote://attachments/…`，并在文档中展示 [ImageNode.altText]（如「手写」）。
///
/// 块图选中由 [MiImageBlockTapHandler]（[contentTapDelegateFactories]）处理，避免 Android 默认把选区挪到正文。
class LocalImageComponentBuilder implements ComponentBuilder {
  const LocalImageComponentBuilder(this.document);

  final Document document;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! ImageNode) {
      return null;
    }

    return ImageComponentViewModel(
      nodeId: node.id,
      imageUrl: node.imageUrl,
      expectedSize: node.expectedBitmapSize,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! ImageComponentViewModel) {
      return null;
    }

    final node = document.getNodeById(componentViewModel.nodeId);
    final caption = node is ImageNode && node.altText.trim().isNotEmpty ? node.altText.trim() : null;

    final image = ImageComponent(
      componentKey: componentContext.componentKey,
      imageUrl: componentViewModel.imageUrl,
      expectedSize: componentViewModel.expectedSize,
      selection: componentViewModel.selection?.nodeSelection as UpstreamDownstreamNodeSelection?,
      selectionColor: componentViewModel.selectionColor,
      imageBuilder: (context, imageUrl) => buildLocalImage(
            context,
            imageUrl,
            decodeMaxLogical: 960,
          ),
    );

    final factor = node is ImageNode ? miImageWidthFactorFromMetadata(node.metadata) : 1.0;
    Widget layoutChild = image;
    if (caption != null) {
      final scheme = Theme.of(componentContext.context).colorScheme;
      layoutChild = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          image,
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(
              caption,
              style: Theme.of(componentContext.context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
            ),
          ),
        ],
      );
    }

    Widget laidOut = layoutChild;
    if (factor < 0.99) {
      laidOut = Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: factor,
          alignment: Alignment.centerLeft,
          child: layoutChild,
        ),
      );
    }

    return laidOut;
  }
}
