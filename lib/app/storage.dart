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

  // Writes to the same path are serialized; each uses its own temp file.
  final Map<String, Future<void>> _queue = {};
  int _tmpCounter = 0;

  Future<void> _enqueue(String path, Future<void> Function() job) {
    final prev = _queue[path] ?? Future<void>.value();
    final next = prev.catchError((Object _) {}).then((_) => job());
    _queue[path] = next;
    next.whenComplete(() {
      if (identical(_queue[path], next)) _queue.remove(path);
    }).catchError((Object _) {});
    return next;
  }

  Future<String?> _read(String path) async {
    try {
      final f = _file(path);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> read(String path) async {
    final pending = _queue[path];
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    return _read(path);
  }

  @override
  Future<void> write(String path, String data) => _enqueue(path, () async {
        try {
          final f = _file(path);
          await f.parent.create(recursive: true);
          final tmp = File('${f.path}.${_tmpCounter++}.tmp');
          await tmp.writeAsString(data, flush: true);
          await tmp.rename(f.path);
        } catch (e) {
          // never let a failed save crash the app
        }
      });

  @override
  Future<void> delete(String path) => _enqueue(path, () async {
        try {
          final f = _file(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      });

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
