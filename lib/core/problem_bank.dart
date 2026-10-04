import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetBundle;

import 'problem.dart';
import 'variants.dart';

/// Immutable collection of courses/problems (bundled assets + downloaded packs).
class ProblemBank {
  final List<Subject> subjects;
  final List<Workbook> workbooks;

  ProblemBank(List<Subject> subjects, {List<Workbook> workbooks = const <Workbook>[]})
      : subjects = List<Subject>.unmodifiable(subjects),
        workbooks = List<Workbook>.unmodifiable(workbooks);

  static const String customSubjectId = 'custom';
  static const String customSubjectName = '내 문제';
  static const int customSubjectColor = 0xFF5B6475;

  static final RegExp _variantId = RegExp(r'^(.+)~v(-?\d+)$');

  late final Map<String, Problem> _index = _buildIndex();
  late final Map<String, List<Problem>> _twins = _buildTwins();
  final Map<String, Problem> _variantCache = <String, Problem>{};

  Map<String, Problem> _buildIndex() {
    final m = <String, Problem>{};
    for (final s in subjects) {
      for (final p in s.problems) {
        m.putIfAbsent(p.id, () => p);
      }
      for (final p in s.twins) {
        m.putIfAbsent(p.id, () => p);
      }
    }
    return m;
  }

  Map<String, List<Problem>> _buildTwins() {
    final m = <String, List<Problem>>{};
    for (final s in subjects) {
      for (final t in s.twins) {
        m.putIfAbsent(t.twinOf!, () => <Problem>[]).add(t);
      }
    }
    return m;
  }

  /// Reads `assets/problems/_index.json` (`{"files": [...]}`), each listed course
  /// file and `workbooks.json`. Files that fail to load/parse are skipped.
  static Future<ProblemBank> load(AssetBundle bundle) async {
    var files = <String>[];
    try {
      final raw = await bundle.loadString('assets/problems/_index.json');
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['files'] : decoded;
      files = list is List ? list.map((e) => e.toString()).toList() : <String>[];
    } catch (e) {
      debugPrint('ProblemBank: _index.json 읽기 실패: $e');
      return ProblemBank(const <Subject>[]);
    }
    final subjects = <Subject>[];
    for (final f in files) {
      final path = f.startsWith('assets/') ? f : 'assets/problems/$f';
      try {
        subjects.add(parseCourse(await bundle.loadString(path)));
      } catch (e) {
        debugPrint('ProblemBank: $path 건너뜀: $e');
      }
    }
    var workbooks = <Workbook>[];
    try {
      workbooks = Workbook.listFromJson(jsonDecode(await bundle.loadString('assets/problems/workbooks.json')));
    } catch (e) {
      debugPrint('ProblemBank: workbooks.json 없음: $e');
    }
    return ProblemBank(_merge(subjects), workbooks: workbooks);
  }

  static Subject parseCourse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('최상위가 객체가 아닙니다');
    return Subject.fromJson(decoded.map((k, v) => MapEntry(k.toString(), v)));
  }

  /// Same-id subjects are merged (later problems appended).
  static List<Subject> _merge(List<Subject> list) {
    final order = <String>[];
    final byId = <String, Subject>{};
    for (final s in list) {
      final e = byId[s.id];
      if (e == null) {
        order.add(s.id);
        byId[s.id] = s;
      } else {
        byId[s.id] = e.copyWith(
          problems: List<Problem>.unmodifiable([...e.problems, ...s.problems]),
          twins: List<Problem>.unmodifiable([...e.twins, ...s.twins]),
          passages: List<Passage>.unmodifiable([...e.passages, ...s.passages]),
        );
      }
    }
    return [for (final id in order) byId[id]!];
  }

  /// Courses downloaded from the content server replace bundled ones with the same id.
  ProblemBank withPacks(List<Subject> packs, {List<Workbook>? workbooks}) {
    if (packs.isEmpty && workbooks == null) return this;
    final byId = {for (final p in packs) p.id: p};
    final out = <Subject>[
      for (final s in subjects) byId.remove(s.id) ?? s,
      ...byId.values,
    ];
    return ProblemBank(out, workbooks: workbooks ?? this.workbooks);
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

  /// Authored twins (쌍둥이 변형) of a problem.
  List<Problem> twinsOf(String id) => _twins[id] ?? const <Problem>[];

  Passage? passageOf(Problem p) => p.passageId == null ? null : subject(p.subjectId)?.passage(p.passageId);

  Workbook? workbook(String id) {
    for (final w in workbooks) {
      if (w.id == id) return w;
    }
    return null;
  }

  List<Problem> problemsOf(Workbook w) => [
        for (final id in w.problemIds)
          if (byId(id) case final p?) p,
      ];

  List<Subject> inGroup(String group) => subjects.where((s) => s.group == group).toList();

  /// Problems in lists (twins excluded).
  List<Problem> get all => <Problem>[
        for (final s in subjects) ...s.problems,
      ];

  /// Returns a new bank where [extra] problems are appended to their subject
  /// (matched by `subjectId`). Problems whose subject does not exist get a new
  /// subject '내 문제'.
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
        final name = (sid == customSubjectId || p.subjectName.isEmpty) ? customSubjectName : p.subjectName;
        meta[sid] = Subject(id: sid, name: name, color: customSubjectColor, problems: const <Problem>[]);
      }
      list.add(p);
    }
    return ProblemBank(<Subject>[
      for (final id in order) meta[id]!.copyWith(problems: List<Problem>.unmodifiable(lists[id]!)),
    ], workbooks: workbooks);
  }
}
