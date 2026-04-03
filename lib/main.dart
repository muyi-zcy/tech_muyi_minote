import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'blockquote_newline_command.dart';
import 'editor_selection_toolbar.dart';
import 'normalized_paste_handler.dart';
import 'mi_blockquote_component.dart';
import 'note_editor_format.dart';

void main() {
  runApp(const MyApp());
}

/// 跟随系统深浅色；默认（浅色）为白底。
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiNote',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006B5C),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006B5C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const XiaomiStyleNoteEditorPage(),
    );
  }
}

class XiaomiStyleNoteEditorPage extends StatefulWidget {
  const XiaomiStyleNoteEditorPage({super.key});

  @override
  State<XiaomiStyleNoteEditorPage> createState() => _XiaomiStyleNoteEditorPageState();
}

class _XiaomiStyleNoteEditorPageState extends State<XiaomiStyleNoteEditorPage>
    with WidgetsBindingObserver {
  final GlobalKey _docLayoutKey = GlobalKey();
  final TextEditingController _titleController = TextEditingController();

  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final CommonEditorOperations _commonOps;
  late final EditListener _editListener;

  late final FocusNode _titleFocusNode;
  late final FocusNode _editorFocusNode;
  late final ScrollController _scrollController;

  /// 底部「TT」展开的二级文本菜单；有选区时会自动为 true。
  bool _textFormatMenuOpen = false;

  /// 上一轮是否为展开选区，用于在收起选区时自动退回一级菜单，且不误伤「仅点 TT 打开二级」的情况。
  bool _selectionWasExpanded = false;

  late final SuperEditorAndroidControlsController _androidEditControls;
  late final SuperEditorIosControlsController _iosEditControls;

  /// 仅正文 [SuperEditor] 聚焦时显示底部工具栏（标题聚焦不显示）。
  bool get _bodyHasEditorFocus => _editorFocusNode.hasFocus;

  /// 标题或正文任一聚焦时显示顶部「编辑」工具栏；否则为笔记「功能」工具栏（分享、主题、更多）。
  bool get _topBarEditingMode =>
      _titleFocusNode.hasFocus || _editorFocusNode.hasFocus;

  /// 笔记卡片类型展示文案（顶部返回键右侧），默认闪念卡。
  String _noteCardTypeLabel = '闪念卡';

  /// 上一轮键盘遮挡高度，用于检测键盘收起。
  double _lastKeyboardInsetBottom = 0;

  /// 与引擎同步的底部键盘遮挡（逻辑像素），避免 [didChangeMetrics] 时 [MediaQuery] 尚未更新。
  double _keyboardInsetBottomSynced() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) {
      return 0;
    }
    return views.first.viewInsets.bottom;
  }

  /// 合并 [MediaQuery] 与平台视图，取较大值以兼容不同刷新时机。
  double _keyboardInsetBottomResolved() {
    if (!mounted) return 0;
    final mq = MediaQuery.viewInsetsOf(context).bottom;
    final fromView = _keyboardInsetBottomSynced();
    return mq > fromView ? mq : fromView;
  }

  void _scheduleKeyboardInsetSyncAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastKeyboardInsetBottom = _keyboardInsetBottomResolved();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _document = MutableDocument(
      nodes: [
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(),
          metadata: {'blockType': paragraphAttribution},
        ),
      ],
    );
    _composer = MutableDocumentComposer();
    _editor = Editor(
      editables: {
        Editor.documentKey: _document,
        Editor.composerKey: _composer,
      },
      requestHandlers: [
        normalizedPasteRequestHandler,
        insertTextNewlineInBlockquoteRequestHandler,
        insertTextMultilineAsParagraphsHandler,
        insertNewlineInBlockquoteRequestHandler,
        ...defaultRequestHandlers,
      ],
      historyGroupingPolicy: defaultMergePolicy,
      reactionPipeline: List.from(defaultEditorReactions),
      isHistoryEnabled: true,
    );
    _commonOps = CommonEditorOperations(
      editor: _editor,
      document: _document,
      composer: _composer,
      documentLayoutResolver: () => _docLayoutKey.currentState! as DocumentLayout,
    );

    _editListener = FunctionalEditListener((_) {
      if (mounted) setState(() {});
    });
    _editor.addListener(_editListener);

    _titleController.addListener(() {
      if (mounted) setState(() {});
    });

    _titleFocusNode = FocusNode();
    _editorFocusNode = FocusNode();
    _scrollController = ScrollController();

    _androidEditControls = SuperEditorAndroidControlsController(
      controlsColor: const Color(0xFFFF9100),
      toolbarBuilder: (context, mobileToolbarKey, focalPoint) {
        return MiEditorFloatingToolbar(
          toolbarKey: mobileToolbarKey,
          selectionListenable: _composer.selectionNotifier,
          commonOps: _commonOps,
          onAfterAction: _androidEditControls.hideToolbar,
        );
      },
    );
    _iosEditControls = SuperEditorIosControlsController(
      handleColor: const Color(0xFFFF9100),
      toolbarBuilder: (context, mobileToolbarKey, focalPoint) {
        return MiEditorFloatingToolbar(
          toolbarKey: mobileToolbarKey,
          selectionListenable: _composer.selectionNotifier,
          commonOps: _commonOps,
          onAfterAction: _iosEditControls.hideToolbar,
        );
      },
    );

    void onEditorFocusChange() {
      if (!mounted) return;
      if (!_editorFocusNode.hasFocus) {
        setState(() {
          _textFormatMenuOpen = false;
          _androidEditControls.hideToolbar();
          _iosEditControls.hideToolbar();
        });
        return;
      }
      _scheduleKeyboardInsetSyncAfterFrame();
      final sel = _composer.selection;
      final expanded = sel != null && !sel.isCollapsed;
      setState(() {
        if (expanded) {
          _textFormatMenuOpen = true;
        }
        _selectionWasExpanded = expanded;
      });
    }

    _titleFocusNode.addListener(() {
      if (!mounted) return;
      if (_titleFocusNode.hasFocus) {
        _scheduleKeyboardInsetSyncAfterFrame();
      }
      setState(() {});
    });
    _editorFocusNode.addListener(onEditorFocusChange);
    _composer.selectionNotifier.addListener(_onComposerSelectionChanged);
  }

  void _onComposerSelectionChanged() {
    if (!_editorFocusNode.hasFocus) return;
    final sel = _composer.selection;
    final expanded = sel != null && !sel.isCollapsed;
    if (expanded) {
      setState(() {
        _textFormatMenuOpen = true;
        _selectionWasExpanded = true;
      });
    } else if (_selectionWasExpanded) {
      setState(() {
        _textFormatMenuOpen = false;
        _selectionWasExpanded = false;
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    // 本帧内 MediaQuery 往往仍是旧值，放到帧末再读；并与 PlatformDispatcher 对齐。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bottom = _keyboardInsetBottomResolved();
      if (_lastKeyboardInsetBottom > 0 && bottom == 0) {
        _titleFocusNode.unfocus();
        _editorFocusNode.unfocus();
      }
      _lastKeyboardInsetBottom = bottom;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composer.selectionNotifier.removeListener(_onComposerSelectionChanged);
    _editor.removeListener(_editListener);
    _androidEditControls.dispose();
    _iosEditControls.dispose();
    _titleController.dispose();
    _scrollController.dispose();
    _titleFocusNode.dispose();
    _editorFocusNode.dispose();
    _editor.dispose();
    _composer.dispose();
    super.dispose();
  }

  String _formatNow() {
    final n = DateTime.now();
    return '${n.month}月${n.day}日 ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  int _characterCount() {
    var n = _titleController.text.length;
    for (final node in _document) {
      if (node is TextNode) {
        n += node.text.toPlainText().length;
      }
    }
    return n;
  }

  bool _isBodyEmpty() {
    for (final node in _document) {
      if (node is TextNode) {
        if (node.text.toPlainText().trim().isNotEmpty) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  bool get _canUndo => _editor.history.isNotEmpty;
  bool get _canRedo => _editor.future.isNotEmpty;

  void _refocusEditor() => _editorFocusNode.requestFocus();

  /// 将列表项等转为普通段落，便于改 blockType / 对齐。
  void _ensureParagraphForBlockOps() {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    final node = _document.getNodeById(sel.extent.nodeId);
    if (node is ListItemNode) {
      _commonOps.convertToParagraph();
    }
  }

  Stylesheet _stylesheetForTheme(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return defaultStylesheet.copyWith(
        documentPadding: EdgeInsets.zero,
        addRulesAfter: [
          StyleRule(
            BlockSelector.all,
            (doc, node) => {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFE6E6E6),
                fontSize: 16,
                height: 1.78,
              ),
              Styles.padding: const CascadingPadding.symmetric(horizontal: 16, vertical: 6),
            },
          ),
          StyleRule(
            const BlockSelector('header1'),
            (doc, node) => {
              Styles.textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            },
          ),
          StyleRule(
            const BlockSelector('header2'),
            (doc, node) => {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFF0F0F0),
                fontSize: 20,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            },
          ),
          StyleRule(
            const BlockSelector('header3'),
            (doc, node) => {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFE8E8E8),
                fontSize: 18,
                height: 1.42,
                fontWeight: FontWeight.w600,
              ),
            },
          ),
          StyleRule(
            const BlockSelector('blockquote'),
            (doc, node) => {
              Styles.textStyle: const TextStyle(
                color: Color(0xFFB8B8B8),
                fontSize: 16,
                height: 1.78,
                fontWeight: FontWeight.normal,
              ),
            },
          ),
        ],
      );
    }
    return defaultStylesheet.copyWith(
      documentPadding: EdgeInsets.zero,
      addRulesAfter: [
        StyleRule(
          BlockSelector.all,
          (doc, node) => {
            Styles.textStyle: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 17,
              height: 1.78,
            ),
            Styles.padding: const CascadingPadding.symmetric(horizontal: 16, vertical: 6),
          },
        ),
        StyleRule(
          const BlockSelector('header1'),
          (doc, node) => {
            Styles.textStyle: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 36,
              height: 1.25,
              fontWeight: FontWeight.bold,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('header2'),
          (doc, node) => {
            Styles.textStyle: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 24,
              height: 1.3,
              fontWeight: FontWeight.bold,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('header3'),
          (doc, node) => {
            Styles.textStyle: const TextStyle(
              color: Color(0xFF333333),
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.bold,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('blockquote'),
          (doc, node) => {
            Styles.textStyle: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 17,
              height: 1.78,
              fontWeight: FontWeight.normal,
            ),
          },
        ),
      ],
    );
  }

  void _applyBlockType(Attribution blockType) {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    _ensureParagraphForBlockOps();
    final id = sel.extent.nodeId;
    final node = _document.getNodeById(id);
    if (node is! ParagraphNode) return;
    _editor.execute([
      ChangeParagraphBlockTypeRequest(nodeId: id, blockType: blockType),
    ]);
    setState(() {});
    _refocusEditor();
  }

  void _applyAlignment(TextAlign alignment) {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    _ensureParagraphForBlockOps();
    final id = sel.extent.nodeId;
    final node = _document.getNodeById(id);
    if (node is! ParagraphNode) return;
    _editor.execute([
      ChangeParagraphAlignmentRequest(nodeId: id, alignment: alignment),
    ]);
    setState(() {});
    _refocusEditor();
  }

  void _toggleInline(Set<Attribution> attrs) {
    _commonOps.toggleAttributionsOnSelection(attrs);
    setState(() {});
    _refocusEditor();
  }

  void _convertToList(ListItemType type) {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    final node = _document.getNodeById(sel.extent.nodeId);
    if (node is! TextNode) return;
    _commonOps.convertToListItem(type, node.text);
    setState(() {});
    _refocusEditor();
  }

  void _insertDivider() {
    _ensureParagraphForBlockOps();
    _commonOps.insertHorizontalRule();
    setState(() {});
    _refocusEditor();
  }

  /// 列表项用 super_editor 列表缩进；正文/标题/引用等 [ParagraphNode] 用段落 indent。
  void _applyIndent() {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    final node = _document.getNodeById(sel.extent.nodeId);
    if (node is ListItemNode) {
      if (_commonOps.indentListItem()) {
        setState(() {});
        _refocusEditor();
      }
      return;
    }
    if (node is ParagraphNode) {
      _editor.execute([IndentParagraphRequest(node.id)]);
      setState(() {});
      _refocusEditor();
    }
  }

  void _applyOutdent() {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    final node = _document.getNodeById(sel.extent.nodeId);
    if (node is ListItemNode) {
      if (_commonOps.unindentListItem()) {
        setState(() {});
        _refocusEditor();
      }
      return;
    }
    if (node is ParagraphNode) {
      _editor.execute([UnIndentParagraphRequest(node.id)]);
      setState(() {});
      _refocusEditor();
    }
  }

  /// 引用开关：非引用段落 → 引用；已在引用内 → 恢复为正文段落（保留换行与正文）。
  void _toggleBlockquote() {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    final node = _document.getNodeById(sel.extent.nodeId);
    if (node is! ParagraphNode) return;
    if (node.getMetadataValue('blockType') == blockquoteAttribution) {
      _editor.execute([
        ChangeParagraphBlockTypeRequest(nodeId: node.id, blockType: paragraphAttribution),
      ]);
    } else {
      _commonOps.convertToBlockquote(node.text);
    }
    setState(() {});
    _refocusEditor();
  }

  void _onNoteFormat(NoteEditorFormat kind) {
    switch (kind) {
      case NoteEditorFormat.h1:
        _applyBlockType(header1Attribution);
        return;
      case NoteEditorFormat.h2:
        _applyBlockType(header2Attribution);
        return;
      case NoteEditorFormat.h3:
        _applyBlockType(header3Attribution);
        return;
      case NoteEditorFormat.bold:
        _toggleInline({boldAttribution});
        return;
      case NoteEditorFormat.italic:
        _toggleInline({italicsAttribution});
        return;
      case NoteEditorFormat.underline:
        _toggleInline({underlineAttribution});
        return;
      case NoteEditorFormat.strikethrough:
        _toggleInline({strikethroughAttribution});
        return;
      case NoteEditorFormat.bulletList:
        _convertToList(ListItemType.unordered);
        return;
      case NoteEditorFormat.numberedList:
        _convertToList(ListItemType.ordered);
        return;
      case NoteEditorFormat.horizontalRule:
        _insertDivider();
        return;
      case NoteEditorFormat.blockquote:
        _toggleBlockquote();
        return;
      case NoteEditorFormat.alignLeft:
        _applyAlignment(TextAlign.left);
        return;
      case NoteEditorFormat.alignCenter:
        _applyAlignment(TextAlign.center);
        return;
      case NoteEditorFormat.alignRight:
        _applyAlignment(TextAlign.right);
        return;
      case NoteEditorFormat.indent:
        _applyIndent();
        return;
      case NoteEditorFormat.outdent:
        _applyOutdent();
        return;
    }
  }

  SelectionStyles _selectionStyles(Brightness brightness, ColorScheme scheme) {
    if (brightness == Brightness.dark) {
      return const SelectionStyles(
        selectionColor: Color(0x6641E8D8),
      );
    }
    return const SelectionStyles(
      selectionColor: Color(0x99FFF3C4),
    );
  }

  List<SuperEditorLayerBuilder> _caretOverlays(Brightness brightness) {
    final caretColor = brightness == Brightness.dark
        ? const Color(0xFFFFB74D)
        : const Color(0xFF1565C0);
    return [
      ...defaultSuperEditorDocumentOverlayBuilders.sublist(0, 4),
      DefaultCaretOverlayBuilder(
        caretStyle: CaretStyle(
          width: brightness == Brightness.dark ? 2.5 : 2,
          color: caretColor,
        ),
        displayOnAllPlatforms: true,
      ),
    ];
  }

  /// 在 [SuperEditor] 外侧挂载移动端控制器：自定义手柄色与中文+图标选区浮动条。
  Widget _wrapEditorWithMobileScopes(Widget editor) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return SuperEditorAndroidControlsScope(
          controller: _androidEditControls,
          child: editor,
        );
      case TargetPlatform.iOS:
        return SuperEditorIosControlsScope(
          controller: _iosEditControls,
          child: editor,
        );
      default:
        return editor;
    }
  }

  /// 分享：底部圆角白卡片 + 半透明遮罩（对齐系统笔记样式）。
  void _showShareNoteSheet(BuildContext pageContext) {
    final theme = Theme.of(pageContext);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final sheetSurface = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final cancelFill = isDark ? const Color(0xFF3D3D3D) : const Color(0xFFEFEFEF);

    showModalBottomSheet<void>(
      context: pageContext,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      isScrollControlled: true,
      builder: (sheetContext) {
        Widget option(String label) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.pop(sheetContext);
                if (!pageContext.mounted) return;
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(content: Text('$label 为占位功能')),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 24),
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: sheetSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 22),
                  Text(
                    '分享笔记',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  option('以文字形式分享'),
                  option('以图片形式分享'),
                  option('以副本形式分享'),
                  option('以 Markdown 格式导出'),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: cancelFill,
                        borderRadius: BorderRadius.circular(24),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.pop(sheetContext),
                          borderRadius: BorderRadius.circular(24),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: Center(
                              child: Text(
                                '取消',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 笔记「更多」：三点入口；[showGeneralDialog] 使用与分享抽屉相同的 barrier，菜单较窄。
  Widget _buildNoteMoreMenu(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF323232) : Colors.white;
    final borderColor = scheme.outline.withValues(alpha: isDark ? 0.14 : 0.10);
    const menuWidth = 152.0;
    const barrierAlpha = 0.4;

    Future<void> openMenu(BuildContext buttonContext) async {
      final button = buttonContext.findRenderObject()! as RenderBox;
      final overlayBox =
          Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
      final topLeft = button.localToGlobal(Offset.zero, ancestor: overlayBox);
      final size = button.size;
      final overlaySize = overlayBox.size;

      var menuLeft = topLeft.dx + size.width - menuWidth;
      if (menuLeft < 8) menuLeft = 8;
      if (menuLeft + menuWidth > overlaySize.width - 8) {
        menuLeft = overlaySize.width - menuWidth - 8;
      }
      final menuTop = topLeft.dy + size.height + 6;

      const labels = <String>[
        '设置提醒',
        '设为私密',
        '发送到桌面',
        '移动到',
        '删除',
      ];

      final selected = await showGeneralDialog<String>(
        context: buttonContext,
        barrierDismissible: true,
        barrierLabel:
            MaterialLocalizations.of(buttonContext).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: barrierAlpha),
        transitionDuration: Duration.zero,
        pageBuilder: (dialogContext, _, __) {
          TextStyle? itemStyle() => theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.2,
              );

          Widget menuRow(String label) {
            return InkWell(
              onTap: () => Navigator.pop(dialogContext, label),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(label, style: itemStyle()),
                ),
              ),
            );
          }

          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(dialogContext),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: menuLeft,
                  top: menuTop,
                  width: menuWidth,
                  child: Material(
                    color: menuBg,
                    elevation: 10,
                    shadowColor:
                        Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: borderColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Theme(
                      data: theme.copyWith(
                        splashColor: scheme.primary.withValues(alpha: 0.10),
                        highlightColor:
                            scheme.primary.withValues(alpha: 0.06),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final label in labels) menuRow(label),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (!buttonContext.mounted || selected == null) return;
      ScaffoldMessenger.of(buttonContext).showSnackBar(
        SnackBar(content: Text('$selected 为占位功能')),
      );
    }

    return Builder(
      builder: (buttonContext) {
        return IconButton(
          tooltip: '更多',
          icon: Icon(Icons.more_vert, color: scheme.onSurface),
          onPressed: () => openMenu(buttonContext),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleSpacing: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _noteCardTypeLabel,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
          ),
        ),
        actions: _topBarEditingMode
            ? [
                IconButton(
                  icon: const Icon(Icons.undo_rounded),
                  onPressed: _canUndo
                      ? () {
                          _editor.undo();
                          setState(() {});
                        }
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo_rounded),
                  onPressed: _canRedo
                      ? () {
                          _editor.redo();
                          setState(() {});
                        }
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: '分享',
                  onPressed: () => _showShareNoteSheet(context),
                ),
                IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: '笔记样式',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('笔记背景/样式为占位功能')),
                    );
                  },
                ),
                _buildNoteMoreMenu(context),
              ],
      ),
      body: ColoredBox(
        color: scheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              focusNode: _titleFocusNode,
              controller: _titleController,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '标题',
                hintStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.38),
                    ),
                contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${_formatNow()} | ${_characterCount()}字',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: _wrapEditorWithMobileScopes(
                      SuperEditor(
                        editor: _editor,
                        focusNode: _editorFocusNode,
                        scrollController: _scrollController,
                        documentLayoutKey: _docLayoutKey,
                        stylesheet: _stylesheetForTheme(brightness),
                        selectionStyle: _selectionStyles(brightness, scheme),
                        documentOverlayBuilders: _caretOverlays(brightness),
                        componentBuilders: [
                          const MiBlockquoteComponentBuilder(),
                          ...defaultComponentBuilders.skip(1),
                          TaskComponentBuilder(_editor),
                          const UnknownComponentBuilder(),
                        ],
                      ),
                    ),
                  ),
                  if (_isBodyEmpty())
                    Positioned(
                      top: 6,
                      left: 20,
                      right: 20,
                      child: IgnorePointer(
                        child: Text(
                          '开始书写',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.38),
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _BottomFormatToolbar(
              visible: _bodyHasEditorFocus,
              textMenuOpen: _textFormatMenuOpen,
              onToggleTextMenu: () {
                setState(() {
                  _textFormatMenuOpen = !_textFormatMenuOpen;
                });
              },
              onCloseTextMenu: () {
                setState(() {
                  _textFormatMenuOpen = false;
                });
              },
              onInsertPlaceholder: (label) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label 为占位功能')),
                );
              },
              onTextFormat: _onNoteFormat,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomFormatToolbar extends StatelessWidget {
  const _BottomFormatToolbar({
    required this.visible,
    required this.textMenuOpen,
    required this.onToggleTextMenu,
    required this.onCloseTextMenu,
    required this.onInsertPlaceholder,
    required this.onTextFormat,
  });

  static const double _barHeight = 48;

  final bool visible;
  final bool textMenuOpen;
  final VoidCallback onToggleTextMenu;
  final VoidCallback onCloseTextMenu;
  final void Function(String label) onInsertPlaceholder;
  final void Function(NoteEditorFormat) onTextFormat;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 6 + bottomInset * 0.25),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return SizedBox(
                height: _barHeight,
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      IgnorePointer(
                        ignoring: textMenuOpen,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          offset: textMenuOpen ? const Offset(-1, 0) : Offset.zero,
                          child: SizedBox(
                            width: w,
                            height: _barHeight,
                            child: _buildPrimaryRow(context, scheme),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: !textMenuOpen,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          offset: textMenuOpen ? Offset.zero : const Offset(1, 0),
                          child: SizedBox(
                            width: w,
                            height: _barHeight,
                            child: _buildSubmenuRow(context, scheme),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryRow(BuildContext context, ColorScheme scheme) {
    final iconColor = scheme.onSurface.withValues(alpha: 0.88);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _tb(icon: Icons.auto_fix_high_rounded, color: iconColor, onTap: () => onInsertPlaceholder('智能排版')),
        _tb(icon: Icons.mic_none_rounded, color: iconColor, onTap: () => onInsertPlaceholder('语音')),
        _tb(icon: Icons.image_outlined, color: iconColor, onTap: () => onInsertPlaceholder('图片')),
        _tb(icon: Icons.gesture_rounded, color: iconColor, onTap: () => onInsertPlaceholder('手写')),
        _tb(icon: Icons.check_box_outlined, color: iconColor, onTap: () => onInsertPlaceholder('待办')),
        _tb(
          icon: Icons.text_fields_rounded,
          color: scheme.primary,
          onTap: onToggleTextMenu,
        ),
      ],
    );
  }

  /// 与一级同高的横向图标区：左侧可滚动，右侧竖线 + 关闭。
  Widget _buildSubmenuRow(BuildContext context, ColorScheme scheme) {
    final iconColor = scheme.onSurface.withValues(alpha: 0.88);
    final subtle = scheme.onSurface.withValues(alpha: 0.45);

    Widget miniLabel(String text, NoteEditorFormat kind) {
      return InkWell(
        onTap: () => onTextFormat(kind),
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

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: false,
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                miniLabel('H1', NoteEditorFormat.h1),
                miniLabel('H2', NoteEditorFormat.h2),
                miniLabel('H3', NoteEditorFormat.h3),
                _ib(Icons.format_bold_rounded, '加粗', NoteEditorFormat.bold, iconColor),
                _ib(Icons.format_italic_rounded, '斜体', NoteEditorFormat.italic, iconColor),
                _ib(Icons.format_underlined_rounded, '下划线', NoteEditorFormat.underline, iconColor),
                _ib(Icons.strikethrough_s_rounded, '删除线', NoteEditorFormat.strikethrough, iconColor),
                _ib(Icons.format_list_bulleted_rounded, '无序列表', NoteEditorFormat.bulletList, iconColor),
                _ib(Icons.format_list_numbered_rounded, '有序列表', NoteEditorFormat.numberedList, iconColor),
                _ib(Icons.horizontal_rule_rounded, '分割线', NoteEditorFormat.horizontalRule, iconColor),
                _ib(Icons.format_quote_rounded, '引用', NoteEditorFormat.blockquote, iconColor),
                _ib(Icons.format_align_left_rounded, '左对齐', NoteEditorFormat.alignLeft, iconColor),
                _ib(Icons.format_align_center_rounded, '居中', NoteEditorFormat.alignCenter, iconColor),
                _ib(Icons.format_align_right_rounded, '右对齐', NoteEditorFormat.alignRight, iconColor),
                _ib(Icons.format_indent_increase_rounded, '增加缩进', NoteEditorFormat.indent, iconColor),
                _ib(Icons.format_indent_decrease_rounded, '减少缩进', NoteEditorFormat.outdent, subtle),
              ],
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: scheme.outline.withValues(alpha: 0.35),
        ),
        IconButton(
          onPressed: onCloseTextMenu,
          tooltip: '关闭',
          icon: Icon(Icons.close_rounded, color: iconColor, size: 22),
        ),
      ],
    );
  }

  Widget _ib(IconData icon, String tip, NoteEditorFormat kind, Color color) {
    return IconButton(
      onPressed: () => onTextFormat(kind),
      icon: Icon(icon, size: 22, color: color),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      tooltip: tip,
    );
  }

  Widget _tb({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 24),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}
