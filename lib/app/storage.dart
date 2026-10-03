import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny key/value file storage so the app state can be unit-tested in memory.
abstract class Storage {
  Future<String?> read(String path);
  Future<void> write(String path, String data);
  Future<void> delete(String path);
  Future<void> deleteDir(String dir);
}

class FileStorage implements Storage {
  FileStorage._(this._root);
  final Directory _root;

  static Future<FileStorage> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/pulinote');
    if (!await root.exists()) await root.create(recursive: true);
    return FileStorage._(root);
  }

  File _file(String path) => File('${_root.path}/$path');

  @override
  Future<String?> read(String path) async {
    try {
      final f = _file(path);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String path, String data) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String path) async {
    try {
      final f = _file(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<void> deleteDir(String dir) async {
    try {
      final d = Directory('${_root.path}/$dir');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}

class MemoryStorage implements Storage {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String path) async => data[path];

  @override
  Future<void> write(String path, String d) async => data[path] = d;

  @override
  Future<void> delete(String path) async => data.remove(path);

  @override
  Future<void> deleteDir(String dir) async => data.removeWhere((k, _) => k.startsWith('$dir/'));
}
