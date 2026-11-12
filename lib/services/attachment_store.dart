import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class AttachmentStore {
  static String _canonical(String path) =>
      Platform.isWindows ? path.replaceAll('\\', '/').toLowerCase() : path;
  final Directory? directory;
  AttachmentStore({this.directory});
  Future<Directory> root() async {
    final base =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/driver_proofs',
        );
    return base.create(recursive: true);
  }

  Future<Map<String, Object?>> save(
    String scope,
    String key,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)
      throw StateError('Proof must be between 1 byte and 5 MB.');
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    final png =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final webp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    if (!jpeg && !png && !webp)
      throw StateError('Select a JPEG, PNG or WebP proof.');
    final folder = await root();
    // All caller-controlled names are hashed before becoming filesystem paths.
    final name = sha256.convert('$scope/$key'.codeUnits).toString();
    final file = File('${folder.path}/$name.proof');
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
    return {
      'path': file.path,
      'size': bytes.length,
      'hash': sha256.convert(bytes).toString(),
    };
  }

  Future<Uint8List> read(Map<String, dynamic> attachment) async {
    final bytes = await File(attachment['path'] as String).readAsBytes();
    if (bytes.length != attachment['byte_size'] ||
        sha256.convert(bytes).toString() != attachment['sha256']) {
      throw StateError('Saved proof is damaged. Review this action.');
    }
    return bytes;
  }

  Future<void> remove(String path) async {
    final folder = await root();
    final file = File(path);
    if (file.parent.absolute.path != folder.absolute.path)
      throw StateError('Invalid attachment path.');
    if (await file.exists()) await file.delete();
  }

  Future<void> removeOrphans(Set<String> referenced, DateTime before) async {
    final folder = await root();
    final protected = referenced.map(_canonical).toSet();
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is! File || protected.contains(_canonical(entry.path)))
        continue;
      if (!(entry.path.endsWith('.proof') || entry.path.endsWith('.tmp')))
        continue;
      if ((await entry.stat()).modified.isBefore(before))
        await remove(entry.path);
    }
  }
}
