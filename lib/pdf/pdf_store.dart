import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../app/storage.dart';

/// 교재 파일에 들어 있던 원본 PDF 들 — 기기에 `pdfs/<이름>.b64` 로 따로 두고, 그릴 때 꺼낸다.
///
/// 교재 파일(.pulinote)의 `pdfs` 는 `{이름: base64}` 이다. 같은 이름의 PDF 는 같은 내용이어야 한다
/// (변환기가 이름에 내용의 해시를 붙인다).
class PdfStore {
  PdfStore(this.storage);
  final Storage storage;

  /// 앱이 켜질 때 정한다 (테스트는 MemoryStorage 로).
  static PdfStore? instance;

  static final RegExp _name = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,120}$');

  final Map<String, Uint8List> _mem = {};

  String _path(String id) => 'pdfs/$id.b64';

  /// 교재 JSON 의 `pdfs` 를 기기에 둔다. 넣은 이름들을 돌려준다.
  Future<List<String>> putAll(Object? pdfs) async {
    if (pdfs is! Map) return const [];
    final out = <String>[];
    for (final e in pdfs.entries) {
      final id = '${e.key}';
      final v = e.value;
      if (!_name.hasMatch(id) || v is! String || v.isEmpty) continue;
      final b64 = v.startsWith('data:') ? v.substring(v.indexOf(',') + 1) : v;
      final existing = await storage.read(_path(id));
      if (existing != b64) await storage.write(_path(id), b64);
      _mem.remove(id);
      out.add(id);
    }
    return out;
  }

  Future<bool> has(String id) async => _mem.containsKey(id) || await storage.read(_path(id)) != null;

  /// PDF 바이트 (없으면 null).
  Future<Uint8List?> bytes(String id) async {
    final hit = _mem[id];
    if (hit != null) return hit;
    final raw = await storage.read(_path(id));
    if (raw == null) return null;
    try {
      final b = base64Decode(raw);
      if (_mem.length >= 6) _mem.remove(_mem.keys.first);
      _mem[id] = b;
      return b;
    } catch (e) {
      debugPrint('pdf $id broken: $e');
      return null;
    }
  }
}
