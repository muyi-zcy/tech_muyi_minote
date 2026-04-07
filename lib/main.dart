import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_editor/super_editor.dart';

import 'blockquote_newline_command.dart';
import 'document_selection_sanitize.dart';
import 'editor_selection_toolbar.dart';
import 'mi_floating_toolbar_clamp.dart';
import 'mi_image_block_tap_handler.dart';
import 'mi_clipboard_image.dart';
import 'mi_http_fetch_bytes.dart';
import 'mi_io_file_bytes.dart';
import 'mi_note_image_layout.dart';
import 'local_image_component.dart';
import 'mi_blockquote_component.dart';
import 'mi_inline_image.dart';
import 'mi_inline_image_builders_phase.dart';
import 'mi_task_component.dart';
import 'normalized_paste_handler.dart';
import 'note_attachment_store.dart';
import 'platform_file_read_bytes.dart';
import 'note_editor_format.dart';
import 'note_file_attachment.dart';
import 'note_share_export.dart';
import 'voice_record_sheet.dart';

void main() {
  runApp(const MyApp());
}

/// 底部主工具栏「智能排版 / 语音 / 图片 / 手写 / 待办」。
enum NoteEditorBottomAction {
  smartLayout,
  voice,
  image,
  handwriting,
  todo,
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
  /// 正文编辑区（含滚动），用于将选区浮动菜单限制在可视编辑范围内。
  final GlobalKey _editorBodyKey = GlobalKey();
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

  final MiInlineImageBuildersPhase _inlineImageBuildersPhase = MiInlineImageBuildersPhase();

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
    NoteAttachmentStore.ensureInitialized();
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
      // 不合并「纯选区/ composing」到上一条内容事务，避免撤销重放后选区类型与节点不一致
      //（例如正文节点 id + UpstreamDownstreamNodePosition 导致 TextComponent 抛错）。
      historyGroupingPolicy: const HistoryGroupingPolicyList([
        mergeRapidTextInputPolicy,
      ]),
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
      final cur = _composer.selection;
      final fixed = sanitizeDocumentSelection(_document, cur);
      if (fixed != cur) {
        _composer.setSelectionWithReason(fixed, SelectionReason.contentChange);
      }
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
        return MiFloatingToolbarClamp(
          editorBodyKey: _editorBodyKey,
          scrollController: _scrollController,
          child: MiEditorFloatingToolbar(
            toolbarKey: mobileToolbarKey,
            selectionListenable: _composer.selectionNotifier,
            document: _document,
            commonOps: _commonOps,
            onAfterAction: _androidEditControls.hideToolbar,
            onPasteWithImageFirst: _pasteFromToolbar,
            onCopyImagePixels: _toolbarCopyImagePixels,
            onToggleImageHalfFullWidth: _toggleSelectedImageWidthHalfFull,
          ),
        );
      },
    );
    _iosEditControls = SuperEditorIosControlsController(
      handleColor: const Color(0xFFFF9100),
      toolbarBuilder: (context, mobileToolbarKey, focalPoint) {
        return MiFloatingToolbarClamp(
          editorBodyKey: _editorBodyKey,
          scrollController: _scrollController,
          child: MiEditorFloatingToolbar(
            toolbarKey: mobileToolbarKey,
            selectionListenable: _composer.selectionNotifier,
            document: _document,
            commonOps: _commonOps,
            onAfterAction: _iosEditControls.hideToolbar,
            onPasteWithImageFirst: _pasteFromToolbar,
            onCopyImagePixels: _toolbarCopyImagePixels,
            onToggleImageHalfFullWidth: _toggleSelectedImageWidthHalfFull,
          ),
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
      } else if (node is ImageNode || node is FileAttachmentNode) {
        n += 1;
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

  /// 合并连续空段落（保留每段的第一块空段落）。
  void _applySmartLayout() {
    final toDelete = <String>[];
    ParagraphNode? prevEmptyPara;
    for (final node in _document) {
      if (node is! ParagraphNode) {
        prevEmptyPara = null;
        continue;
      }
      if (node.getMetadataValue('blockType') != paragraphAttribution) {
        prevEmptyPara = null;
        continue;
      }
      final empty = node.text.toPlainText().trim().isEmpty;
      if (empty) {
        if (prevEmptyPara != null) {
          toDelete.add(node.id);
        } else {
          prevEmptyPara = node;
        }
      } else {
        prevEmptyPara = null;
      }
    }
    if (toDelete.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有需要合并的连续空段落')),
        );
      }
      return;
    }
    for (final id in toDelete) {
      _editor.execute([DeleteNodeRequest(nodeId: id)]);
    }
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已合并 ${toDelete.length} 处连续空段落')),
      );
    }
  }

  /// Android（尤其 HyperOS 系统相册）上 [ImagePicker] 易触发转场异常；改用 [FilePicker] 走文档选择器。
  Future<({Uint8List bytes, String ext})?> _pickGalleryImage() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return null;
      // 默认压缩会在公共 Pictures 目录 createTempFile，分区存储下常 Permission denied 崩溃。
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowCompression: false,
      );
      if (result == null || result.files.isEmpty) return null;
      final f = result.files.single;
      final bytes = await readPlatformFileBytes(f);
      if (bytes != null && bytes.isNotEmpty) {
        return (bytes: bytes, ext: _extensionFromPlatformFile(f));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能读取图片数据，请换一张图或稍后重试')),
        );
      }
      return null;
    }

    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    return (bytes: bytes, ext: _guessImageExtension(x.path, x.mimeType));
  }

  String _extensionFromPlatformFile(PlatformFile f) {
    var e = (f.extension ?? '').toLowerCase();
    if (e.startsWith('.')) e = e.substring(1);
    if (e.isNotEmpty) return e;
    final name = f.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1);
    }
    return 'jpg';
  }

  /// 系统相册返回后 [MutableDocumentComposer.selection] 常被清空，插入命令会静默失败。
  DocumentSelection? _fallbackCaretLastTextNode() {
    TextNode? last;
    for (final node in _document) {
      if (node is TextNode) last = node;
    }
    if (last == null) return null;
    return DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: last.id,
        nodePosition: last.endPosition,
      ),
    );
  }

  /// 在选区处插入块级节点（图、语音条、待办等）。
  ///
  /// 相册 / 录音抽屉关闭后 [MutableDocumentComposer.selection] 常被清空；若先 [execute] 恢复选区、
  /// 再 [execute] 插入，会变成**两次**撤销且第二次仍可能因选区未就绪而静默失败。此处把「恢复选区 + 插入」
  /// 放进**同一次** [Editor.execute]，保证单步撤销且与 [InsertNodeAtCaretCommand] 行为一致。
  ///
  /// 返回是否实际执行了 [Editor.execute]（未插入时为 `false`）。
  bool _insertBlockNodeWithResolvedSelection({
    required DocumentNode blockNode,
    required DocumentSelection? selectionBeforeAsync,
    required String needCaretHint,
  }) {
    if (!mounted) return false;

    final requests = <EditRequest>[];

    final rawSelection = _composer.selection;
    DocumentSelection? anchor = rawSelection;
    if (anchor == null) {
      anchor = selectionBeforeAsync ?? _fallbackCaretLastTextNode();
    }
    anchor = sanitizeDocumentSelection(_document, anchor);
    if (anchor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(needCaretHint)),
      );
      return false;
    }
    if (rawSelection == null || rawSelection != anchor) {
      requests.add(
        ChangeSelectionRequest(
          anchor,
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      );
    }

    if (_editorFocusNode.canRequestFocus) {
      _editorFocusNode.requestFocus();
    }

    final anchorId = anchor.extent.nodeId;
    final selectedNode = _document.getNodeById(anchorId);
    if (selectedNode == null) return false;

    // 与官方示例一致：块级节点 + [InsertNodeAtCaretRequest]；非 [ParagraphNode] 时用 [InsertNodeAfterNodeRequest]。
    if (!anchor.isCollapsed) {
      requests.add(DeleteContentRequest(documentRange: anchor.normalize(_document)));
    }
    if (selectedNode is ParagraphNode) {
      requests.add(InsertNodeAtCaretRequest(node: blockNode));
    } else {
      requests.add(
        InsertNodeAfterNodeRequest(
          existingNodeId: selectedNode.id,
          newNode: blockNode,
        ),
      );
      requests.add(
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: blockNode.id,
              nodePosition: const UpstreamDownstreamNodePosition.downstream(),
            ),
          ),
          SelectionChangeType.insertContent,
          SelectionReason.userInteraction,
        ),
      );
    }

    _editor.execute(requests);
    if (mounted) setState(() {});
    _refocusEditor();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      if (_editorFocusNode.canRequestFocus) {
        _editorFocusNode.requestFocus();
      }
    });
    return true;
  }

  void _insertImageAfterPickerResolved({
    required String ref,
    required bool handwriting,
    required DocumentSelection? selectionBeforePick,
  }) {
    final imageNode = ImageNode(
      id: Editor.createNodeId(),
      imageUrl: ref,
      altText: handwriting ? '手写' : '',
    );
    _insertBlockNodeWithResolvedSelection(
      blockNode: imageNode,
      selectionBeforeAsync: selectionBeforePick,
      needCaretHint: '请先点击正文输入区再插入图片',
    );
  }

  String _extensionFromImageUrl(String url) {
    final q = url.indexOf('?');
    final path = q >= 0 ? url.substring(0, q) : url;
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && dot < path.length - 1) {
      return path.substring(dot + 1).toLowerCase();
    }
    return 'png';
  }

  String _extensionForRawImageBytes(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
    if (bytes.length >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif';
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    return 'png';
  }

  Future<Uint8List?> _readBytesForImageNode(ImageNode node) async {
    final url = node.imageUrl;
    if (url.startsWith('minote://')) {
      final cached = NoteAttachmentStore.peekInlineImageBytes(url);
      if (cached != null) return cached;
      final p = await NoteAttachmentStore.getLocalPath(url);
      if (p == null) return null;
      return readLocalFileBytes(p);
    }
    if (url.startsWith('file://')) {
      if (kIsWeb) return null;
      return readLocalFileBytes(Uri.parse(url).toFilePath());
    }
    return fetchHttpBytes(url);
  }

  Future<void> _toolbarCopyImagePixels() async {
    final sel = _composer.selection;
    if (sel == null) return;
    final nodes = _document.getNodesInside(sel.base, sel.extent);
    if (nodes.length != 1 || nodes.first is! ImageNode) return;
    final node = nodes.first as ImageNode;
    final bytes = await _readBytesForImageNode(node);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该图片')),
      );
      return;
    }
    final ext = _extensionFromImageUrl(node.imageUrl);
    final ok = await writeImageBytesToClipboard(bytes, extension: ext);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制图片到剪贴板失败')),
      );
    }
  }

  Future<void> _pasteFromToolbar() async {
    final img = await readClipboardImageBytes();
    if (img != null && img.isNotEmpty) {
      await NoteAttachmentStore.ensureInitialized();
      final ext = _extensionForRawImageBytes(img);
      final ref = await NoteAttachmentStore.saveBytes(img, ext);
      if (!mounted) return;
      _insertImageAfterPickerResolved(
        ref: ref,
        handwriting: false,
        selectionBeforePick: _composer.selection,
      );
      return;
    }
    _commonOps.paste();
  }

  void _toggleSelectedImageWidthHalfFull() {
    final sel = _composer.selection;
    if (sel == null) return;
    final nodes = _document.getNodesInside(sel.base, sel.extent);
    if (nodes.length != 1 || nodes.first is! ImageNode) return;
    final node = nodes.first as ImageNode;
    final cur = miImageWidthFactorFromMetadata(node.metadata);
    final next = cur < 0.75 ? 1.0 : 0.5;
    _editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: node.copyWithAddedMetadata({kMiImageWidthFactorKey: next}),
      ),
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _insertImageFromPicker({required bool handwriting}) async {
    await NoteAttachmentStore.ensureInitialized();
    final selectionBeforePick = _composer.selection;

    final picked = await _pickGalleryImage();
    if (picked == null) return;
    final bytes = picked.bytes;
    final ext = picked.ext;
    final ref = await NoteAttachmentStore.saveBytes(bytes, ext);
    if (!mounted) return;

    final capHandwriting = handwriting;
    final capRef = ref;
    final capSel = selectionBeforePick;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _insertImageAfterPickerResolved(
        ref: capRef,
        handwriting: capHandwriting,
        selectionBeforePick: capSel,
      );
    });
  }

  String _guessImageExtension(String path, String? mime) {
    if (path.isNotEmpty) {
      final dot = path.lastIndexOf('.');
      if (dot >= 0 && dot < path.length - 1) {
        return path.substring(dot + 1).toLowerCase();
      }
    }
    final m = mime?.toLowerCase() ?? '';
    if (m.contains('png')) return 'png';
    if (m.contains('webp')) return 'webp';
    if (m.contains('gif')) return 'gif';
    return 'jpg';
  }

  Future<void> _insertVoiceAttachment() async {
    final selectionBeforeSheet = _composer.selection;
    final outcome = await showVoiceRecordSheet(context);
    if (outcome == null || !mounted) return;
    final t = DateTime.now();
    final label =
        '语音 ${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final node = FileAttachmentNode(
      id: Editor.createNodeId(),
      minoteRef: outcome.ref,
      displayLabel: label,
      waveformPeaks: outcome.waveformPeaks,
    );
    // 与选图一致：等一帧再插入，减少 Activity/Sheet 恢复瞬间 composer 未同步导致的失败。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ok = _insertBlockNodeWithResolvedSelection(
        blockNode: node,
        selectionBeforeAsync: selectionBeforeSheet,
        needCaretHint: '请先点击正文输入区再插入语音',
      );
      if (!mounted || !ok) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音已插入'), duration: Duration(seconds: 2)),
      );
    });
  }

  void _insertNewTodoBlock() {
    _insertBlockNodeWithResolvedSelection(
      blockNode: TaskNode(
        id: Editor.createNodeId(),
        text: AttributedText(),
        isComplete: false,
      ),
      selectionBeforeAsync: _composer.selection,
      needCaretHint: '请先点击正文输入区再插入待办',
    );
  }

  /// 当前段为正文/列表时转为待办；已在待办则取消待办（恢复为段落）；其它块类型则插入新待办。
  void _insertTodo() {
    final sel = _composer.selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) {
      _insertNewTodoBlock();
      return;
    }
    final id = sel.extent.nodeId;
    final node = _document.getNodeById(id);
    if (node is TaskNode) {
      _editor.execute([ConvertTaskToParagraphRequest(nodeId: id)]);
      setState(() {});
      _refocusEditor();
      return;
    }
    if (node is ParagraphNode) {
      _editor.execute([ConvertParagraphToTaskRequest(nodeId: id)]);
      setState(() {});
      _refocusEditor();
      return;
    }
    if (node is ListItemNode) {
      _editor.execute([
        ReplaceNodeRequest(
          existingNodeId: id,
          newNode: TaskNode(
            id: node.id,
            text: node.text,
            isComplete: false,
            indent: node.indent,
          ),
        ),
      ]);
      setState(() {});
      _refocusEditor();
      return;
    }
    _insertNewTodoBlock();
  }

  void _onBottomToolbarAction(NoteEditorBottomAction action) {
    switch (action) {
      case NoteEditorBottomAction.smartLayout:
        _applySmartLayout();
        return;
      case NoteEditorBottomAction.voice:
        _insertVoiceAttachment();
        return;
      case NoteEditorBottomAction.image:
        _insertImageFromPicker(handwriting: false);
        return;
      case NoteEditorBottomAction.handwriting:
        _insertImageFromPicker(handwriting: true);
        return;
      case NoteEditorBottomAction.todo:
        _insertTodo();
        return;
    }
  }

  bool get _canUndo => _editor.history.isNotEmpty;
  bool get _canRedo => _editor.future.isNotEmpty;

  /// 撤销 / 重做由 [Editor] 触发 [FunctionalEditListener] 统一 [setState]；此处不再重复刷帧。
  void _performUndo() {
    if (!_canUndo) return;
    _editor.undo();
  }

  void _performRedo() {
    if (!_canRedo) return;
    _editor.redo();
  }

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
        // 不可放在 StyleRule 里：SingleColumnStylesheetStyler 合并样式时不会用新列表覆盖已有 inlineWidgetBuilders。
        inlineWidgetBuilders: [
          miInlineImageBuilder,
          ...defaultInlineWidgetBuilderChain,
        ],
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
      inlineWidgetBuilders: [
        miInlineImageBuilder,
        ...defaultInlineWidgetBuilderChain,
      ],
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

  List<ComponentBuilder> _editorComponentBuilders() {
    return [
      const MiBlockquoteComponentBuilder(),
      const ParagraphComponentBuilder(),
      const ListItemComponentBuilder(),
      LocalImageComponentBuilder(_document),
      const HorizontalRuleComponentBuilder(),
      const FileAttachmentComponentBuilder(),
      MiTaskComponentBuilder(_editor),
      const UnknownComponentBuilder(),
    ];
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
    final id = sel.extent.nodeId;
    final node = _document.getNodeById(id);
    final alignName = switch (alignment) {
      TextAlign.center => 'center',
      TextAlign.right => 'right',
      TextAlign.justify => 'justify',
      _ => 'left',
    };
    if (node is ParagraphNode) {
      _editor.execute([
        ChangeParagraphAlignmentRequest(nodeId: id, alignment: alignment),
      ]);
    } else if (node is ImageNode) {
      _editor.execute([
        ReplaceNodeRequest(
          existingNodeId: node.id,
          newNode: node.copyWithAddedMetadata({'textAlign': alignName}),
        ),
      ]);
    } else {
      return;
    }
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
        Widget option(String label, Future<void> Function() action) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                Navigator.pop(sheetContext);
                await Future<void>.delayed(Duration.zero);
                if (!pageContext.mounted) return;
                await action();
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
                  option(
                    '以文字形式分享',
                    () => shareNoteAsPlainText(
                      pageContext,
                      _titleController.text,
                      _document,
                    ),
                  ),
                  option(
                    '以图片形式分享',
                    () => shareNoteAsImage(
                      pageContext,
                      _titleController.text,
                      _formatNow(),
                      _noteCardTypeLabel,
                      _document,
                      theme,
                      _stylesheetForTheme(theme.brightness),
                      [_inlineImageBuildersPhase],
                      _editorComponentBuilders(),
                    ),
                  ),
                  option(
                    '保存图片到本地',
                    () => saveNoteImageToLocal(
                      pageContext,
                      _titleController.text,
                      _formatNow(),
                      _noteCardTypeLabel,
                      _document,
                      theme,
                      _stylesheetForTheme(theme.brightness),
                      [_inlineImageBuildersPhase],
                      _editorComponentBuilders(),
                    ),
                  ),
                  option(
                    '以 Markdown 格式导出',
                    () => shareNoteAsMarkdownFile(
                      pageContext,
                      _titleController.text,
                      _document,
                    ),
                  ),
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
                  tooltip: '撤销',
                  icon: const Icon(Icons.undo_rounded),
                  onPressed: _canUndo ? _performUndo : null,
                ),
                IconButton(
                  tooltip: '重做',
                  icon: const Icon(Icons.redo_rounded),
                  onPressed: _canRedo ? _performRedo : null,
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
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_formatNow()} | ${_characterCount()}字',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: KeyedSubtree(
                key: _editorBodyKey,
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
                          contentTapDelegateFactories: [
                            (ctx) => MiImageBlockTapHandler(
                                  ctx,
                                  androidControls:
                                      defaultTargetPlatform == TargetPlatform.android ||
                                              defaultTargetPlatform == TargetPlatform.fuchsia
                                          ? _androidEditControls
                                          : null,
                                  iosControls: defaultTargetPlatform == TargetPlatform.iOS
                                      ? _iosEditControls
                                      : null,
                                ),
                            superEditorLaunchLinkTapHandlerFactory,
                          ],
                          stylesheet: _stylesheetForTheme(brightness),
                          selectionStyle: _selectionStyles(brightness, scheme),
                          // 系统相册/文件选择器会抢走焦点；默认 true 会 ClearSelection，返回后易出现内容已插入但版面不刷新，需再点正文才显示。
                          // 与官方对「自定义插入面板」的说明一致（见 SuperEditorSelectionPolicies）。
                          selectionPolicies: const SuperEditorSelectionPolicies(
                            clearSelectionWhenEditorLosesFocus: false,
                            clearSelectionWhenImeConnectionCloses: false,
                          ),
                          documentOverlayBuilders: _caretOverlays(brightness),
                          customStylePhases: [_inlineImageBuildersPhase],
                          componentBuilders: _editorComponentBuilders(),
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
              onBottomAction: _onBottomToolbarAction,
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
    required this.onBottomAction,
    required this.onTextFormat,
  });

  static const double _barHeight = 48;

  final bool visible;
  final bool textMenuOpen;
  final VoidCallback onToggleTextMenu;
  final VoidCallback onCloseTextMenu;
  final void Function(NoteEditorBottomAction action) onBottomAction;
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
        _tb(icon: Icons.auto_fix_high_rounded, color: iconColor, onTap: () => onBottomAction(NoteEditorBottomAction.smartLayout)),
        _tb(icon: Icons.mic_none_rounded, color: iconColor, onTap: () => onBottomAction(NoteEditorBottomAction.voice)),
        _tb(icon: Icons.image_outlined, color: iconColor, onTap: () => onBottomAction(NoteEditorBottomAction.image)),
        _tb(icon: Icons.gesture_rounded, color: iconColor, onTap: () => onBottomAction(NoteEditorBottomAction.handwriting)),
        _tb(icon: Icons.check_box_outlined, color: iconColor, onTap: () => onBottomAction(NoteEditorBottomAction.todo)),
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
