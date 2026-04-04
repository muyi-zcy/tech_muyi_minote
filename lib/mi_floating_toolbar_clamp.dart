import 'package:flutter/material.dart';

/// 将 super_editor 浮动菜单在屏幕坐标下限制在 [editorBodyKey] 对应区域内，避免超出编辑区。
class MiFloatingToolbarClamp extends StatefulWidget {
  const MiFloatingToolbarClamp({
    super.key,
    required this.editorBodyKey,
    this.scrollController,
    required this.child,
  });

  final GlobalKey editorBodyKey;
  final ScrollController? scrollController;
  final Widget child;

  @override
  State<MiFloatingToolbarClamp> createState() => _MiFloatingToolbarClampState();
}

class _MiFloatingToolbarClampState extends State<MiFloatingToolbarClamp> {
  final GlobalKey _toolbarKey = GlobalKey();
  Offset _nudge = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScrollOrLayoutChange);
  }

  @override
  void didUpdateWidget(covariant MiFloatingToolbarClamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.scrollController?.removeListener(_onScrollOrLayoutChange);
    widget.scrollController?.addListener(_onScrollOrLayoutChange);
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScrollOrLayoutChange);
    super.dispose();
  }

  void _onScrollOrLayoutChange() {
    if (!mounted) return;
    // 滚动后 Follower 会重定位，先清零再下一帧重算，避免叠加上一次的平移。
    setState(() => _nudge = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _clampIfNeeded());
    return Transform.translate(
      offset: _nudge,
      child: KeyedSubtree(
        key: _toolbarKey,
        child: widget.child,
      ),
    );
  }

  void _clampIfNeeded() {
    if (!mounted) return;
    final bodyCtx = widget.editorBodyKey.currentContext;
    final barCtx = _toolbarKey.currentContext;
    if (bodyCtx == null || barCtx == null) return;

    final bodyRo = bodyCtx.findRenderObject();
    final barRo = barCtx.findRenderObject();
    if (bodyRo is! RenderBox || barRo is! RenderBox) return;
    if (!bodyRo.hasSize || !barRo.hasSize || !bodyRo.attached || !barRo.attached) return;

    final editorRect = bodyRo.localToGlobal(Offset.zero) & bodyRo.size;
    final transformedTopLeft = barRo.localToGlobal(Offset.zero);
    final rawTopLeft = transformedTopLeft - _nudge;
    final rawRect = rawTopLeft & barRo.size;

    const pad = 6.0;
    double dx = 0;
    double dy = 0;

    if (rawRect.width <= editorRect.width - 2 * pad) {
      if (rawRect.left < editorRect.left + pad) {
        dx = editorRect.left + pad - rawRect.left;
      } else if (rawRect.right > editorRect.right - pad) {
        dx = editorRect.right - pad - rawRect.right;
      }
    } else {
      dx = editorRect.left + pad - rawRect.left;
    }

    if (rawRect.height <= editorRect.height - 2 * pad) {
      if (rawRect.top < editorRect.top + pad) {
        dy = editorRect.top + pad - rawRect.top;
      } else if (rawRect.bottom > editorRect.bottom - pad) {
        dy = editorRect.bottom - pad - rawRect.bottom;
      }
    } else {
      dy = editorRect.top + pad - rawRect.top;
    }

    final next = Offset(dx, dy);
    if ((next - _nudge).distance > 0.5) {
      setState(() => _nudge = next);
    }
  }
}
