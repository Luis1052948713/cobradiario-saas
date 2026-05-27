import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<String> saveReportBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final baseDirectory = await _directorioBase();
  final exportDirectory = Directory(
    path.join(baseDirectory.path, 'cobra_diario_reportes'),
  );
  await exportDirectory.create(recursive: true);

  final file = File(path.join(exportDirectory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Directory> _directorioBase() async {
  final publicDownloads = await _directorioDescargasPublico();
  if (publicDownloads != null) return publicDownloads;

  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } catch (_) {
    // Some mobile platforms do not expose a public downloads directory.
  }

  return getApplicationDocumentsDirectory();
}

Future<Directory?> _directorioDescargasPublico() async {
  final candidates = <Directory>[];

  if (Platform.isAndroid) {
    candidates.add(Directory('/storage/emulated/0/Download'));
  }

  if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      candidates.add(Directory(path.join(userProfile, 'Downloads')));
      candidates.add(Directory(path.join(userProfile, 'Descargas')));
    }
  }

  if (Platform.isLinux || Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(Directory(path.join(home, 'Downloads')));
      candidates.add(Directory(path.join(home, 'Descargas')));
    }
  }

  for (final directory in candidates) {
    try {
      if (await directory.exists()) return directory;
    } catch (_) {
      // Continue with the next candidate if the platform denies access.
    }
  }

  return null;
}
