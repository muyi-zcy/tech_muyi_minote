import 'package:flutter/material.dart';

Widget buildLocalImage(
  BuildContext context,
  String imageUrl, {
  double decodeMaxLogical = 720,
}) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  final cacheW = (decodeMaxLogical * dpr).round().clamp(48, 4096);
  return Image.network(
    imageUrl,
    fit: BoxFit.contain,
    cacheWidth: cacheW,
    errorBuilder: (context, error, stackTrace) =>
        const Icon(Icons.broken_image_outlined, size: 24),
  );
}
