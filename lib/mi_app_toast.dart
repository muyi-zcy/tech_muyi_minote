import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

/// 统一使用 TDesign Toast，替代底部 [SnackBar]。
void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2000),
}) {
  if (!context.mounted) return;
  TDToast.showText(
    message,
    context: context,
    duration: duration,
    maxLines: 4,
  );
}

void showAppToastSuccess(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2000),
}) {
  if (!context.mounted) return;
  TDToast.showSuccess(
    message,
    context: context,
    duration: duration,
    maxLines: 4,
  );
}

void showAppToastFail(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 3000),
}) {
  if (!context.mounted) return;
  TDToast.showFail(
    message,
    context: context,
    duration: duration,
    maxLines: 4,
  );
}

void showAppToastWarning(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2500),
}) {
  if (!context.mounted) return;
  TDToast.showWarning(
    message,
    context: context,
    duration: duration,
    maxLines: 4,
  );
}
