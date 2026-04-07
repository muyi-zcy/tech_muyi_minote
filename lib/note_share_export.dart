import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_editor/super_editor.dart';

import 'note_file_attachment.dart';
import 'share_note_platform.dart';

const _kCopyFormatId = 'minote-copy-v1';

/// 笔记纯文本（标题 + 正文块），用于系统分享。
String buildNotePlainText(String title, Document doc) {
  final buf = StringBuffer();
  final t = title.trim();
  if (t.isNotEmpty) {
    buf.writeln(t);
    buf.writeln();
  }
  for (final node in doc) {
    _appendNodePlain(buf, node);
  }
  return buf.toString().trimRight();
}

void _appendNodePlain(StringBuffer buf, DocumentNode node) {
  if (node is ParagraphNode) {
    final bt = node.getMetadataValue('blockType') as Attribution?;
    var line = node.text.toPlainText().trimRight();
    if (line.isEmpty) {
      buf.writeln();
      return;
    }
    if (bt == blockquoteAttribution) {
      for (final l in line.split('\n')) {
        buf.writeln('> $l');
      }
    } else if (bt == header1Attribution) {
      buf.writeln(line);
      buf.writeln();
    } else if (bt == header2Attribution) {
      buf.writeln(line);
      buf.writeln();
    } else if (bt == header3Attribution) {
      buf.writeln(line);
      buf.writeln();
    } else {
      buf.writeln(line);
    }
    return;
  }
  if (node is ListItemNode) {
    final indent = '  ' * node.indent;
    final plain = node.text.toPlainText().trimRight();
    final bullet = node.type == ListItemType.unordered ? '• ' : '1. ';
    buf.writeln('$indent$bullet$plain');
    return;
  }
  if (node is TaskNode) {
    final mark = node.isComplete ? '[x] ' : '[ ] ';
    buf.writeln('${mark}${node.text.toPlainText().trimRight()}');
    return;
  }
  if (node is ImageNode) {
    final cap = node.altText.trim().isNotEmpty ? node.altText.trim() : '图片';
    buf.writeln('[$cap]');
    return;
  }
  if (node is FileAttachmentNode) {
    buf.writeln('[附件: ${node.displayLabel}]');
    return;
  }
  if (node is HorizontalRuleNode) {
    buf.writeln('---');
    return;
  }
}

/// GitHub 风格 Markdown（结构为主；段落内多为纯文本）。
String buildNoteMarkdown(String title, Document doc) {
  final buf = StringBuffer();
  final t = title.trim();
  if (t.isNotEmpty) {
    buf.writeln('# $t');
    buf.writeln();
  }
  for (final node in doc) {
    _appendNodeMarkdown(buf, node);
  }
  return buf.toString().trimRight();
}

void _appendNodeMarkdown(StringBuffer buf, DocumentNode node) {
  if (node is ParagraphNode) {
    final bt = node.getMetadataValue('blockType') as Attribution?;
    final text = node.text.toPlainText().trimRight();
    if (text.isEmpty) {
      buf.writeln();
      return;
    }
    if (bt == blockquoteAttribution) {
      for (final l in text.split('\n')) {
        buf.writeln('> $l');
      }
      buf.writeln();
      return;
    }
    if (bt == header1Attribution) {
      buf.writeln('# $text');
      buf.writeln();
      return;
    }
    if (bt == header2Attribution) {
      buf.writeln('## $text');
      buf.writeln();
      return;
    }
    if (bt == header3Attribution) {
      buf.writeln('### $text');
      buf.writeln();
      return;
    }
    buf.writeln(text);
    buf.writeln();
    return;
  }
  if (node is ListItemNode) {
    final indent = '  ' * node.indent;
    final plain = node.text.toPlainText().trimRight();
    if (node.type == ListItemType.unordered) {
      buf.writeln('$indent- $plain');
    } else {
      buf.writeln('${indent}1. $plain');
    }
    return;
  }
  if (node is TaskNode) {
    final mark = node.isComplete ? 'x' : ' ';
    buf.writeln('- [$mark] ${node.text.toPlainText().trimRight()}');
    return;
  }
  if (node is ImageNode) {
    final alt = node.altText.trim().isNotEmpty ? node.altText.trim() : 'image';
    buf.writeln('![$alt](${node.imageUrl})');
    buf.writeln();
    return;
  }
  if (node is FileAttachmentNode) {
    buf.writeln('- **附件**: ${node.displayLabel} (`${node.minoteRef}`)');
    buf.writeln();
    return;
  }
  if (node is HorizontalRuleNode) {
    buf.writeln('---');
    buf.writeln();
    return;
  }
}

Map<String, dynamic> buildNoteCopyMap(String title, Document doc) {
  final blocks = <Map<String, dynamic>>[];
  for (final node in doc) {
    final m = _nodeToJson(node);
    if (m != null) blocks.add(m);
  }
  return {
    'format': _kCopyFormatId,
    'title': title,
    'blocks': blocks,
  };
}

Map<String, dynamic>? _nodeToJson(DocumentNode node) {
  if (node is ParagraphNode) {
    final bt = node.getMetadataValue('blockType');
    return {
      'type': 'paragraph',
      'blockType': bt is Attribution ? bt.id : 'paragraph',
      'text': node.text.toPlainText(),
    };
  }
  if (node is ListItemNode) {
    return {
      'type': 'listItem',
      'listType': node.type == ListItemType.ordered ? 'ordered' : 'unordered',
      'indent': node.indent,
      'text': node.text.toPlainText(),
    };
  }
  if (node is TaskNode) {
    return {
      'type': 'task',
      'done': node.isComplete,
      'text': node.text.toPlainText(),
    };
  }
  if (node is ImageNode) {
    return {
      'type': 'image',
      'imageUrl': node.imageUrl,
      'altText': node.altText,
    };
  }
  if (node is FileAttachmentNode) {
    return {
      'type': 'voice',
      'ref': node.minoteRef,
      'label': node.displayLabel,
      if (node.waveformPeaks != null) 'waveformPeaks': node.waveformPeaks,
    };
  }
  if (node is HorizontalRuleNode) {
    return {'type': 'horizontalRule'};
  }
  return null;
}

Future<Uint8List?> _captureSharePng({
  required BuildContext context,
  required String title,
  required String timeText,
  required String cardTypeText,
  required Document doc,
  required ThemeData theme,
  required Stylesheet stylesheet,
  required List<SingleColumnLayoutStylePhase> customStylePhases,
  required List<ComponentBuilder> componentBuilders,
}) async {
  final scheme = theme.colorScheme;
  final captureBg = scheme.surface;
  final subtleText = scheme.onSurface.withValues(alpha: 0.55);

  final titleText = title.trim();
  final headerMeta = [
    if (timeText.trim().isNotEmpty) timeText.trim(),
    if (cardTypeText.trim().isNotEmpty) cardTypeText.trim(),
  ].join(' | ');

  final widget = InheritedTheme.captureAll(
    context,
    MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
        textScaler: TextScaler.noScaling,
      ),
      child: ClipRect(
        child: Material(
          color: captureBg,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 正文段落有额外 16 的块内边距，标题区同步补偿以保持同一左对齐线。
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (titleText.isNotEmpty)
                          Text(
                            titleText,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                              height: 1.28,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        if (headerMeta.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            headerMeta,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: subtleText,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (titleText.isNotEmpty || headerMeta.isNotEmpty) const SizedBox(height: 12),
                  SuperReader(
                    document: doc,
                    stylesheet: stylesheet,
                    customStylePhases: customStylePhases,
                    componentBuilders: componentBuilders,
                    // 导出是纯展示位图，不需要读模式的交互 overlay（句柄/工具条层）；
                    // 该层在离屏长图渲染中会在 (0,0) 残留异常像素。
                    documentOverlayBuilders: const [],
                    selectionStyle: const SelectionStyles(selectionColor: Color(0x00000000)),
                    shrinkWrap: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
  final controller = ScreenshotController();
  return controller.captureFromLongWidget(
    widget,
    context: context,
    delay: const Duration(milliseconds: 180),
    pixelRatio: dpr,
    constraints: const BoxConstraints(maxWidth: 430),
  );
}

Future<void> shareNoteAsPlainText(
  BuildContext context,
  String title,
  Document doc,
) async {
  final text = buildNotePlainText(title, doc);
  if (text.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('笔记为空，无法分享')),
      );
    }
    return;
  }
  try {
    await Share.share(text, subject: title.trim().isEmpty ? '笔记' : title.trim());
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }
}

Future<void> shareNoteAsMarkdownFile(
  BuildContext context,
  String title,
  Document doc,
) async {
  final md = buildNoteMarkdown(title, doc);
  if (md.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('笔记为空，无法导出')),
      );
    }
    return;
  }
  final baseName = title.trim().isEmpty ? '笔记' : title.trim();
  var safe = baseName.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_');
  if (safe.length > 48) safe = safe.substring(0, 48);
  try {
    await shareUtf8TextFile(
      '$safe.md',
      'text/markdown',
      md,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }
}

Future<void> shareNoteAsCopyFile(
  BuildContext context,
  String title,
  Document doc,
) async {
  final map = buildNoteCopyMap(title, doc);
  final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
  final baseName = title.trim().isEmpty ? '笔记副本' : '${title.trim()} 副本';
  final safe = baseName.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_');
  final clipped = safe.length > 48 ? safe.substring(0, 48) : safe;
  try {
    await shareUtf8TextFile(
      '$clipped.json',
      'application/json',
      jsonStr,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享副本失败：$e')),
      );
    }
  }
}

Future<void> shareNoteAsImage(
  BuildContext context,
  String title,
  String timeText,
  String cardTypeText,
  Document doc,
  ThemeData theme,
  Stylesheet stylesheet,
  List<SingleColumnLayoutStylePhase> customStylePhases,
  List<ComponentBuilder> componentBuilders,
) async {
  if (kIsWeb) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网页版暂不支持以图片形式分享')),
      );
    }
    return;
  }

  if (title.trim().isEmpty && doc.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('笔记为空，无法导出图片')),
    );
    return;
  }

  try {
    final png = await _captureSharePng(
      context: context,
      title: title,
      timeText: timeText,
      cardTypeText: cardTypeText,
      doc: doc,
      theme: theme,
      stylesheet: stylesheet,
      customStylePhases: customStylePhases,
      componentBuilders: componentBuilders,
    );
    if (!context.mounted) return;
    if (png == null || png.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成分享图片失败')),
      );
      return;
    }
    await sharePngBytes(png);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享图片失败：$e')),
      );
    }
  }
}

Future<void> saveNoteImageToLocal(
  BuildContext context,
  String title,
  String timeText,
  String cardTypeText,
  Document doc,
  ThemeData theme,
  Stylesheet stylesheet,
  List<SingleColumnLayoutStylePhase> customStylePhases,
  List<ComponentBuilder> componentBuilders,
) async {
  if (title.trim().isEmpty && doc.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('笔记为空，无法保存图片')),
    );
    return;
  }

  try {
    final png = await _captureSharePng(
      context: context,
      title: title,
      timeText: timeText,
      cardTypeText: cardTypeText,
      doc: doc,
      theme: theme,
      stylesheet: stylesheet,
      customStylePhases: customStylePhases,
      componentBuilders: componentBuilders,
    );
    if (!context.mounted) return;
    if (png == null || png.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('生成图片失败')),
      );
      return;
    }
    final safeTitle = title.trim().replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_');
    final path = await savePngBytesToLocal(
      png,
      suggestedBaseName: safeTitle.isEmpty ? null : safeTitle,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('图片已保存到本地：$path')),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存图片失败：$e')),
      );
    }
  }
}
