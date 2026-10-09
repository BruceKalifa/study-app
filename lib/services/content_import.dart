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

  /// 서버에서 받은 교재면 그 파일의 지문 — 서버 것이 바뀌면 다시 받는다 (파일로 넣었으면 빈 값).
  final String sha;
  const ImportedBook(this.id, this.title, this.problems, this.at, [this.sha = '']);

  factory ImportedBook.fromJson(Map<String, dynamic> j) => ImportedBook(
        '${j['id']}',
        '${j['title'] ?? j['id']}',
        (j['problems'] as num?)?.toInt() ?? 0,
        (j['at'] as num?)?.toInt() ?? 0,
        '${j['sha'] ?? ''}',
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'problems': problems, 'at': at, if (sha.isNotEmpty) 'sha': sha};
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

  /// Several books in one file: `{format:'pulinote-collection', books:[bundle, …]}`.
  static const collection = 'pulinote-collection';

  /// Bytes of a `.pulinote` file (gzip or plain JSON) → the bundle JSON(s). Throws [FormatException].
  static List<Map<String, dynamic>> decodeAll(List<int> bytes) {
    final j = _json(bytes);
    if (j['format'] == collection) {
      final books = j['books'];
      if (books is! List || books.isEmpty) throw const FormatException('교재가 없어요');
      return [for (final b in books) _check(b)];
    }
    return [_check(j)];
  }

  /// A single-book file → its bundle JSON. Throws [FormatException].
  static Map<String, dynamic> decode(List<int> bytes) => _check(_json(bytes));

  static Map<String, dynamic> _json(List<int> bytes) {
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
    if (j is! Map) throw const FormatException('풀이노트 교재 파일이 아니에요');
    return j.map((k, v) => MapEntry('$k', v));
  }

  static Map<String, dynamic> _check(Object? j) {
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

  /// Validates and stores the book(s) in [bytes]; a book with the same id is replaced.
  Future<List<BookBundle>> add(List<int> bytes, {String sha = ''}) async {
    final all = decodeAll(bytes);
    final parsed = [for (final j in all) parse(j)];
    if (parsed.any((b) => b.problemCount == 0)) throw const FormatException('문항이 없어요');
    var books = await list();
    for (var k = 0; k < all.length; k++) {
      final bundle = parsed[k];
      await storage.write('imports/${bundle.id}.json', jsonEncode(all[k]));
      books = books.where((b) => b.id != bundle.id).toList()
        ..add(ImportedBook(bundle.id, bundle.title, bundle.problemCount, DateTime.now().millisecondsSinceEpoch, sha));
    }
    await _saveIndex(books);
    return parsed;
  }

  Future<void> remove(String id) async {
    await storage.delete('imports/$id.json');
    await _saveIndex((await list()).where((b) => b.id != id).toList());
  }

  /// 기기에 저장해 둔 교재들을 다시 `.pulinote` 파일(gzip)로 묶는다 — 서버에 올릴 때 쓴다.
  /// [ids] 가 한 권이면 그 교재 하나, 여러 권이면 `pulinote-collection`.
  Future<Uint8List?> fileFor(List<String> ids) async {
    final books = <Map<String, dynamic>>[];
    for (final id in ids) {
      final raw = await storage.read('imports/$id.json');
      if (raw == null) continue;
      try {
        books.add((jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (e) {
        debugPrint('imported $id broken: $e');
      }
    }
    if (books.isEmpty) return null;
    final j = books.length == 1 ? books.first : {'format': collection, 'version': 1, 'books': books};
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(j))));
  }

  /// 서버에 올린 뒤, 그 교재들이 지금 서버 파일과 같다고 표시한다 (다시 받지 않게).
  Future<void> markSha(Iterable<String> ids, String sha) async {
    final set = ids.toSet();
    final books = await list();
    if (!books.any((b) => set.contains(b.id) && b.sha != sha)) return;
    await _saveIndex([
      for (final b in books) set.contains(b.id) ? ImportedBook(b.id, b.title, b.problems, b.at, sha) : b,
    ]);
  }

  /// 저장해 둔 교재의 정답을 고친다 (`{문항 id: 정답}`). 고친 문항 수를 돌려준다.
  Future<int> setAnswers(String bookId, Map<String, String> answers) async {
    final raw = await storage.read('imports/$bookId.json');
    if (raw == null) return 0;
    final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
    var n = 0;
    for (final c in (j['courses'] as List? ?? const [])) {
      if (c is! Map) continue;
      for (final key in ['problems', 'twins']) {
        for (final p in (c[key] as List? ?? const [])) {
          if (p is! Map) continue;
          final a = answers['${p['id']}'];
          if (a == null || '${p['answer'] ?? ''}' == a) continue;
          p['answer'] = a;
          n++;
        }
      }
    }
    if (n > 0) await storage.write('imports/$bookId.json', jsonEncode(j));
    return n;
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

/// 다른 앱에서 "풀이노트로 열기" (MainActivity, channel `pulinote/files`).
/// 앱 안에서 파일을 고르는 길은 없앴다 — 교재는 서버 교재 창고에서 받는다.
class BookFiles {
  BookFiles._();
  static const MethodChannel _ch = MethodChannel('pulinote/files');

  /// A file opened with the app from another app (카카오톡, 내 파일…), once.
  static Future<Uint8List?> takeOpened() async {
    try {
      return await _ch.invokeMethod<Uint8List>('takeOpened');
    } catch (_) {
      return null;
    }
  }
}
