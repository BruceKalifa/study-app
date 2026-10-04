import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/storage.dart';
import '../core/problem.dart';
import '../core/problem_bank.dart';

/// A textbook added from a `.pulinote` file (tools/tex_book.py).
class ImportedBook {
  final String id;
  final String title;
  final int problems;
  final int at;
  const ImportedBook(this.id, this.title, this.problems, this.at);

  factory ImportedBook.fromJson(Map<String, dynamic> j) => ImportedBook(
        '${j['id']}',
        '${j['title'] ?? j['id']}',
        (j['problems'] as num?)?.toInt() ?? 0,
        (j['at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'problems': problems, 'at': at};
}

/// The parsed contents of one bundle.
class BookBundle {
  final String id;
  final String title;
  final List<Subject> courses;
  final List<Workbook> workbooks;
  const BookBundle(this.id, this.title, this.courses, this.workbooks);

  int get problemCount => courses.fold(0, (n, c) => n + c.problems.length + c.twins.length);
}

/// `.pulinote` 교재 파일 (gzip JSON `{format:'pulinote-bundle', id, title, courses:[…], workbooks:[…]}`)
/// kept on the device under `imports/` — 교재 내용은 공개 저장소에 두지 않고 이렇게 따로 넣는다.
class ContentImport {
  ContentImport(this.storage);
  final Storage storage;

  static const _indexPath = 'imports/_index.json';
  static const format = 'pulinote-bundle';

  /// Bytes of a `.pulinote` file (gzip or plain JSON) → the bundle JSON. Throws [FormatException].
  static Map<String, dynamic> decode(List<int> bytes) {
    List<int> raw = bytes;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        raw = gzip.decode(bytes);
      } catch (_) {
        throw const FormatException('파일이 손상됐어요');
      }
    }
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(raw));
    } catch (_) {
      throw const FormatException('풀이노트 교재 파일이 아니에요');
    }
    if (j is! Map || j['format'] != format) throw const FormatException('풀이노트 교재 파일이 아니에요');
    final id = '${j['id'] ?? ''}';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$').hasMatch(id)) throw const FormatException('교재 id 가 잘못됐어요');
    if (j['courses'] is! List) throw const FormatException('문항이 없어요');
    return j.map((k, v) => MapEntry('$k', v));
  }

  static BookBundle parse(Map<String, dynamic> j) {
    final courses = <Subject>[
      for (final c in (j['courses'] as List? ?? const []))
        if (c is Map) Subject.fromJson(c.map((k, v) => MapEntry('$k', v))),
    ];
    final wbs = Workbook.listFromJson(j['workbooks'] ?? const []);
    return BookBundle('${j['id']}', '${j['title'] ?? j['id']}', courses, wbs);
  }

  Future<List<ImportedBook>> list() async {
    try {
      final raw = await storage.read(_indexPath);
      if (raw == null) return [];
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return [for (final b in (j['books'] as List? ?? const [])) ImportedBook.fromJson((b as Map).cast<String, dynamic>())];
    } catch (e) {
      debugPrint('imports index: $e');
      return [];
    }
  }

  Future<void> _saveIndex(List<ImportedBook> books) =>
      storage.write(_indexPath, jsonEncode({'books': [for (final b in books) b.toJson()]}));

  /// Validates and stores [bytes]; a book with the same id is replaced.
  Future<BookBundle> add(List<int> bytes) async {
    final j = decode(bytes);
    final bundle = parse(j);
    if (bundle.problemCount == 0) throw const FormatException('문항이 없어요');
    await storage.write('imports/${bundle.id}.json', jsonEncode(j));
    final books = (await list()).where((b) => b.id != bundle.id).toList()
      ..add(ImportedBook(bundle.id, bundle.title, bundle.problemCount, DateTime.now().millisecondsSinceEpoch));
    await _saveIndex(books);
    return bundle;
  }

  Future<void> remove(String id) async {
    await storage.delete('imports/$id.json');
    await _saveIndex((await list()).where((b) => b.id != id).toList());
  }

  Future<List<BookBundle>> loadAll() async {
    final out = <BookBundle>[];
    for (final b in await list()) {
      final raw = await storage.read('imports/${b.id}.json');
      if (raw == null) continue;
      try {
        out.add(parse((jsonDecode(raw) as Map).cast<String, dynamic>()));
      } catch (e) {
        debugPrint('imported ${b.id} broken: $e');
      }
    }
    return out;
  }

  /// [bank] plus the books: problems join their course (same id replaces), workbooks are added or replaced.
  static ProblemBank merge(ProblemBank bank, List<BookBundle> books) {
    if (books.isEmpty) return bank;
    final order = <String>[for (final s in bank.subjects) s.id];
    final byId = <String, Subject>{for (final s in bank.subjects) s.id: s};
    final wbs = List<Workbook>.of(bank.workbooks);
    for (final book in books) {
      for (final c in book.courses) {
        final e = byId[c.id];
        if (e == null) {
          order.add(c.id);
          byId[c.id] = c;
          continue;
        }
        final ids = {for (final p in [...c.problems, ...c.twins]) p.id};
        byId[c.id] = e.copyWith(
          problems: List<Problem>.unmodifiable([...e.problems.where((p) => !ids.contains(p.id)), ...c.problems]),
          twins: List<Problem>.unmodifiable([...e.twins.where((p) => !ids.contains(p.id)), ...c.twins]),
          passages: List<Passage>.unmodifiable([...e.passages, ...c.passages]),
        );
      }
      for (final w in book.workbooks) {
        final i = wbs.indexWhere((x) => x.id == w.id);
        if (i >= 0) {
          wbs[i] = w;
        } else {
          wbs.add(w);
        }
      }
    }
    return ProblemBank([for (final id in order) byId[id]!], workbooks: wbs);
  }
}

/// Android file picker / "열기" from other apps (MainActivity, channel `pulinote/files`).
class BookFiles {
  BookFiles._();
  static const MethodChannel _ch = MethodChannel('pulinote/files');

  /// Lets the user choose a file; its bytes, or null when cancelled / unsupported.
  static Future<Uint8List?> pick() async {
    try {
      return await _ch.invokeMethod<Uint8List>('pick');
    } catch (e) {
      debugPrint('pick: $e');
      return null;
    }
  }

  /// A file opened with the app from another app (카카오톡, 내 파일…), once.
  static Future<Uint8List?> takeOpened() async {
    try {
      return await _ch.invokeMethod<Uint8List>('takeOpened');
    } catch (_) {
      return null;
    }
  }
}
