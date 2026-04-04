import 'dart:io' show File;

bool fileExistsSync(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}
