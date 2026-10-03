import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetBundle;

import 'problem.dart';
import 'variants.dart';

/// Immutable collection of subjects/problems loaded from assets.
class ProblemBank {
  final List<Subject> subjects;

  ProblemBank(List<Subject> subjects)
      : subjects = List<Subject>.unmodifiable(subjects);

  static const String customSubjectId = 'custom';
  static const String customSubjectName = '내 문제';
  static const int customSubjectColor = 0xFF5B6475;

  static final RegExp _variantId = RegExp(r'^(.+)~v(-?\d+)$');

  late final Map<String, Problem> _index = _buildIndex();
  final Map<String, Problem> _variantCache = <String, Problem>{};

  Map<String, Problem> _buildIndex() {
    final m = <String, Problem>{};
    for (final s in subjects) {
      for (final p in s.problems) {
        m.putIfAbsent(p.id, () => p);
      }
    }
    return m;
  }

  /// Reads `assets/problems/_index.json` (`{"files": [...]}`) and then each
  /// listed file. Files that fail to load/parse are skipped. Subjects with the
  /// same id coming from several files are merged.
  static Future<ProblemBank> load(AssetBundle bundle) async {
    var files = <String>[];
    try {
      final raw = await bundle.loadString('assets/problems/_index.json');
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['files'] : decoded;
      files = list is List
          ? list.map((e) => e.toString()).toList()
          : <String>[];
    } catch (e) {
      debugPrint('ProblemBank: _index.json 읽기 실패: $e');
      return ProblemBank(const <Subject>[]);
    }

    final order = <String>[];
    final byId = <String, Subject>{};
    for (final f in files) {
      final path = f.startsWith('assets/') ? f : 'assets/problems/$f';
      try {
        final raw = await bundle.loadString(path);
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException('최상위가 객체가 아닙니다');
        }
        final subject = Subject.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)));
        final existing = byId[subject.id];
        if (existing == null) {
          order.add(subject.id);
          byId[subject.id] = subject;
        } else {
          byId[subject.id] = Subject(
            id: existing.id,
            name: existing.name,
            color: existing.color,
            problems: List<Problem>.unmodifiable(
                <Problem>[...existing.problems, ...subject.problems]),
          );
        }
      } catch (e) {
        debugPrint('ProblemBank: $path 건너뜀: $e');
      }
    }
    return ProblemBank(<Subject>[for (final id in order) byId[id]!]);
  }

  /// Looks up a problem by id. Variant ids ("baseId~v123") are resolved by
  /// regenerating the variant from the base problem's template.
  Problem? byId(String id) {
    final direct = _index[id];
    if (direct != null) return direct;
    final cached = _variantCache[id];
    if (cached != null) return cached;
    final m = _variantId.firstMatch(id);
    if (m == null) return null;
    final base = _index[m.group(1)!];
    final seed = int.tryParse(m.group(2)!);
    if (base == null || seed == null || !base.hasTemplate) return null;
    try {
      final v = generateVariant(base, seed);
      _variantCache[id] = v;
      return v;
    } on VariantError catch (e) {
      debugPrint('ProblemBank: 변형 $id 생성 실패: $e');
      return null;
    }
  }

  Subject? subject(String id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<Problem> get all => <Problem>[
        for (final s in subjects) ...s.problems,
      ];

  /// Returns a new bank where [extra] problems are appended to their subject
  /// (matched by `subjectId`). Problems whose subject does not exist get a new
  /// subject: id = their subjectId (or 'custom' when empty), named
  /// '내 문제' for 'custom' (otherwise their subjectName), color 0xFF5B6475.
  ProblemBank withExtra(List<Problem> extra) {
    if (extra.isEmpty) return this;
    final order = <String>[for (final s in subjects) s.id];
    final meta = <String, Subject>{for (final s in subjects) s.id: s};
    final lists = <String, List<Problem>>{
      for (final s in subjects) s.id: List<Problem>.of(s.problems),
    };
    for (final p in extra) {
      final sid = p.subjectId.isEmpty ? customSubjectId : p.subjectId;
      var list = lists[sid];
      if (list == null) {
        list = <Problem>[];
        lists[sid] = list;
        order.add(sid);
        final name = (sid == customSubjectId || p.subjectName.isEmpty)
            ? customSubjectName
            : p.subjectName;
        meta[sid] = Subject(
          id: sid,
          name: name,
          color: customSubjectColor,
          problems: const <Problem>[],
        );
      }
      list.add(p);
    }
    return ProblemBank(<Subject>[
      for (final id in order)
        Subject(
          id: id,
          name: meta[id]!.name,
          color: meta[id]!.color,
          problems: List<Problem>.unmodifiable(lists[id]!),
        ),
    ]);
  }
}
