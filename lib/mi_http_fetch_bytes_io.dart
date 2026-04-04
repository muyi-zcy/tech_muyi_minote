import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> fetchHttpBytes(String url) async {
  if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } catch (_) {
    return null;
  }
}
