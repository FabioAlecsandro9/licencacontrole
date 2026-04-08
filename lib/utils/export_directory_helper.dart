import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ExportDirectoryHelper {
  static Future<Directory> _getDownloadsBaseDir() async {
    if (Platform.isAndroid) {
      final download = Directory('/storage/emulated/0/Download');
      final downloads = Directory('/storage/emulated/0/Downloads');

      if (await download.exists()) return download;
      if (await downloads.exists()) return downloads;
      return download;
    }

    return getApplicationDocumentsDirectory();
  }

  static Future<Directory> getLicencasDir() async {
    final baseDir = await _getDownloadsBaseDir();
    final appDir = Directory(path.join(baseDir.path, 'ZipiTicket'));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }

    final dir = Directory(path.join(appDir.path, 'Licencas'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
