/// 块图在正文列内的水平占比：1.0 为全宽，0.5 为半宽（相对列宽）。
const String kMiImageWidthFactorKey = 'miImageWidthFactor';

double miImageWidthFactorFromMetadata(Map<String, dynamic> metadata) {
  final v = metadata[kMiImageWidthFactorKey];
  if (v is num) {
    final d = v.toDouble();
    if (d > 0 && d <= 1) return d;
  }
  return 1.0;
}
