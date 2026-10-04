// Problem / Subject / Template models. See docs/problem-schema.md.

enum ProblemType { choice, short }

// ---------------------------------------------------------------------------
// JSON helpers (JSON numbers may arrive as int or double; maps may be untyped)

String _str(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  if (v is int) return v.toString();
  if (v is double) {
    if (v.isFinite && v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toString();
  }
  return v.toString();
}

String? _strOrNull(Object? v) => v == null ? null : _str(v);

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

double? _dbl(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

List<String> _strList(Object? v) {
  if (v is List) {
    return List<String>.unmodifiable(v.map((e) => _str(e)));
  }
  return const <String>[];
}

Map<String, dynamic>? _map(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return null;
}

/// Parses "#RRGGBB" / "RRGGBB" / "#AARRGGBB" (or an int) into ARGB.
int parseColor(Object? v, [int fallback = 0xFF5B6475]) {
  if (v is int) return v;
  if (v is! String) return fallback;
  var s = v.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
  final n = int.tryParse(s, radix: 16);
  if (n == null) return fallback;
  if (s.length == 6) return 0xFF000000 | n;
  if (s.length == 8) return n;
  return fallback;
}

String colorToHex(int argb) {
  final rgb = argb & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

// ---------------------------------------------------------------------------

class ParamSpec {
  final double? min;
  final double? max;
  final double? step;
  final List<double>? values;

  const ParamSpec({this.min, this.max, this.step, this.values});

  factory ParamSpec.fromJson(Map<String, dynamic> j) {
    final rawValues = j['values'];
    List<double>? values;
    if (rawValues is List) {
      values = List<double>.unmodifiable(
          rawValues.map((e) => _dbl(e)).whereType<double>());
    }
    return ParamSpec(
      min: _dbl(j['min']),
      max: _dbl(j['max']),
      step: _dbl(j['step']),
      values: values,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (min != null) m['min'] = min;
    if (max != null) m['max'] = max;
    if (step != null) m['step'] = step;
    final vs = values;
    if (vs != null) m['values'] = List<double>.of(vs);
    return m;
  }
}

class ProblemTemplate {
  final Map<String, ParamSpec> params;
  final List<String> require;
  final String stem;
  final String answer;
  final int? round;
  final List<String>? choiceExprs;
  final String choiceFormat;
  final String? solution;
  final String? hint;

  const ProblemTemplate({
    required this.params,
    this.require = const <String>[],
    required this.stem,
    required this.answer,
    this.round,
    this.choiceExprs,
    this.choiceFormat = '[[v]]',
    this.solution,
    this.hint,
  });

  factory ProblemTemplate.fromJson(Map<String, dynamic> j) {
    final params = <String, ParamSpec>{};
    final rawParams = _map(j['params']);
    if (rawParams != null) {
      for (final entry in rawParams.entries) {
        final k = entry.key;
        final v = entry.value;
        final m = _map(v);
        if (m != null) {
          params[k] = ParamSpec.fromJson(m);
        } else if (v is num) {
          // shorthand: "a": 3  -> fixed value
          params[k] = ParamSpec(values: <double>[v.toDouble()]);
        } else if (v is List) {
          params[k] = ParamSpec.fromJson(<String, dynamic>{'values': v});
        }
      }
    }
    final rawChoices = j['choiceExprs'];
    final fmt = j['choiceFormat'];
    return ProblemTemplate(
      params: Map<String, ParamSpec>.unmodifiable(params),
      require: _strList(j['require']),
      stem: _str(j['stem']),
      answer: _str(j['answer']),
      round: _int(j['round']),
      choiceExprs: rawChoices is List ? _strList(rawChoices) : null,
      choiceFormat: (fmt is String && fmt.isNotEmpty) ? fmt : '[[v]]',
      solution: _strOrNull(j['solution']),
      hint: _strOrNull(j['hint']),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'params': <String, dynamic>{
        for (final e in params.entries) e.key: e.value.toJson(),
      },
      'require': List<String>.of(require),
      'stem': stem,
      'answer': answer,
      'choiceFormat': choiceFormat,
    };
    if (round != null) m['round'] = round;
    final ce = choiceExprs;
    if (ce != null) m['choiceExprs'] = List<String>.of(ce);
    if (solution != null) m['solution'] = solution;
    if (hint != null) m['hint'] = hint;
    return m;
  }
}

class Problem {
  final String id;
  final String subjectId;
  final String subjectName;
  final String unit;
  final String topic;
  final String stem;
  final String answer;
  final String solution;
  final int difficulty;
  final ProblemType type;
  final List<String> boxItems;
  final List<String> choices;
  final String? answerUnit;
  final String? hint;
  final double tolerance;
  final List<String> tags;
  final ProblemTemplate? template;
  final String? variantOf;
  final int? variantSeed;

  /// 지문형: id of the passage this question belongs to.
  final String? passageId;

  /// Authored twin (쌍둥이 변형) of another problem.
  final String? twinOf;

  /// 출처 (기출 문항: "2024학년도 9월 모의평가 15번").
  final String? source;

  /// Created by the user in the app.
  final bool custom;

  /// 교재 머리표 (예: 기출문제, 변형, 심화, 숙제 1 (중)) — 원문처럼 검은/주황 상자에 찍힌다.
  final String? label;
  final bool labelAccent;

  /// TeX 원문을 옮긴 문항: 원문처럼 본문 글꼴(Noto Serif KR)과 글줄 수식(text style)으로 그린다.
  final bool texStyle;

  /// 배점 (null → 난이도로 2·3·4점, 0 → 표시하지 않음).
  final int? points;

  const Problem({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    this.unit = '',
    this.topic = '',
    required this.stem,
    required this.answer,
    this.solution = '',
    this.difficulty = 1,
    this.type = ProblemType.short,
    this.boxItems = const <String>[],
    this.choices = const <String>[],
    this.answerUnit,
    this.hint,
    this.tolerance = 0,
    this.tags = const <String>[],
    this.template,
    this.variantOf,
    this.variantSeed,
    this.passageId,
    this.twinOf,
    this.source,
    this.custom = false,
    this.label,
    this.labelAccent = false,
    this.texStyle = false,
    this.points,
  });

  bool get isTwin => twinOf != null;

  /// The problem whose 오답 record this problem feeds (variant/twin → original).
  String get familyId => variantOf ?? twinOf ?? id;

  bool get isVariant => variantOf != null;
  bool get hasTemplate => template != null;
  bool get isChoice => type == ProblemType.choice;

  /// `subjectId`/`subjectName` keys inside [j] (as written by [toJson]) take
  /// precedence; the named arguments are used when the JSON lacks them
  /// (problems inside a subject file).
  factory Problem.fromJson(
    Map<String, dynamic> j, {
    required String subjectId,
    required String subjectName,
  }) {
    final typeStr = _str(j['type']).trim().toLowerCase();
    final choices = _strList(j['choices']);
    final ProblemType type;
    if (typeStr == 'choice') {
      type = ProblemType.choice;
    } else if (typeStr == 'short') {
      type = ProblemType.short;
    } else {
      type = choices.isNotEmpty ? ProblemType.choice : ProblemType.short;
    }
    final tpl = _map(j['template']);
    final jSubjectId = j['subjectId'];
    final jSubjectName = j['subjectName'];
    final unitRaw = _strOrNull(j['answerUnit']);
    return Problem(
      id: _str(j['id']),
      subjectId: (jSubjectId is String && jSubjectId.isNotEmpty)
          ? jSubjectId
          : subjectId,
      subjectName: (jSubjectName is String && jSubjectName.isNotEmpty)
          ? jSubjectName
          : subjectName,
      unit: _str(j['unit']),
      topic: _str(j['topic']),
      stem: _str(j['stem']),
      answer: _str(j['answer']).trim(),
      solution: _str(j['solution']),
      difficulty: _clampInt(_int(j['difficulty']) ?? 1, 1, 5),
      type: type,
      boxItems: _strList(j['boxItems']),
      choices: choices,
      answerUnit: (unitRaw == null || unitRaw.trim().isEmpty) ? null : unitRaw,
      hint: _strOrNull(j['hint']),
      tolerance: (_dbl(j['tolerance']) ?? 0).abs(),
      tags: _strList(j['tags']),
      template: tpl == null ? null : ProblemTemplate.fromJson(tpl),
      variantOf: _strOrNull(j['variantOf']),
      variantSeed: _int(j['variantSeed']),
      passageId: _strOrNull(j['passageId']),
      twinOf: _strOrNull(j['twinOf']),
      source: _strOrNull(j['source']),
      custom: j['custom'] == true,
      label: (_strOrNull(j['label']) ?? '').trim().isEmpty ? null : _str(j['label']).trim(),
      labelAccent: j['labelAccent'] == true,
      texStyle: j['texStyle'] == true,
      points: _int(j['points']),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'unit': unit,
      'topic': topic,
      'difficulty': difficulty,
      'type': type == ProblemType.choice ? 'choice' : 'short',
      'stem': stem,
      'answer': answer,
      'solution': solution,
      'tolerance': tolerance,
    };
    if (boxItems.isNotEmpty) m['boxItems'] = List<String>.of(boxItems);
    if (choices.isNotEmpty) m['choices'] = List<String>.of(choices);
    if (answerUnit != null) m['answerUnit'] = answerUnit;
    if (hint != null) m['hint'] = hint;
    if (tags.isNotEmpty) m['tags'] = List<String>.of(tags);
    final t = template;
    if (t != null) m['template'] = t.toJson();
    if (variantOf != null) m['variantOf'] = variantOf;
    if (variantSeed != null) m['variantSeed'] = variantSeed;
    if (passageId != null) m['passageId'] = passageId;
    if (twinOf != null) m['twinOf'] = twinOf;
    if (source != null) m['source'] = source;
    if (custom) m['custom'] = true;
    if (label != null) m['label'] = label;
    if (labelAccent) m['labelAccent'] = true;
    if (texStyle) m['texStyle'] = true;
    if (points != null) m['points'] = points;
    return m;
  }

  /// Nullable fields can be cleared with the `clear*` flags.
  Problem copyWith({
    String? id,
    String? subjectId,
    String? subjectName,
    String? unit,
    String? topic,
    String? stem,
    String? answer,
    String? solution,
    int? difficulty,
    ProblemType? type,
    List<String>? boxItems,
    List<String>? choices,
    String? answerUnit,
    String? hint,
    double? tolerance,
    List<String>? tags,
    ProblemTemplate? template,
    String? variantOf,
    int? variantSeed,
    bool? custom,
    bool clearAnswerUnit = false,
    bool clearHint = false,
    bool clearTemplate = false,
    bool clearVariant = false,
  }) {
    return Problem(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      unit: unit ?? this.unit,
      topic: topic ?? this.topic,
      stem: stem ?? this.stem,
      answer: answer ?? this.answer,
      solution: solution ?? this.solution,
      difficulty: difficulty ?? this.difficulty,
      type: type ?? this.type,
      boxItems: boxItems ?? this.boxItems,
      choices: choices ?? this.choices,
      answerUnit: clearAnswerUnit ? null : (answerUnit ?? this.answerUnit),
      hint: clearHint ? null : (hint ?? this.hint),
      tolerance: tolerance ?? this.tolerance,
      tags: tags ?? this.tags,
      template: clearTemplate ? null : (template ?? this.template),
      variantOf: clearVariant ? null : (variantOf ?? this.variantOf),
      variantSeed: clearVariant ? null : (variantSeed ?? this.variantSeed),
      passageId: passageId,
      twinOf: twinOf,
      source: source,
      custom: custom ?? this.custom,
      label: label,
      labelAccent: labelAccent,
      texStyle: texStyle,
      points: points,
    );
  }

  @override
  String toString() => 'Problem($id)';
}

/// 지문 (국어·영어 지문형 문항).
class Passage {
  final String id;
  final String title;
  final String body;
  final String? source;
  const Passage({required this.id, this.title = '', required this.body, this.source});

  factory Passage.fromJson(Map<String, dynamic> j) => Passage(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        source: _strOrNull(j['source']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        if (source != null) 'source': source,
      };
}

/// 교과군 (국어·수학·영어·사회·과학).
class SubjectGroup {
  final String id;
  final String name;
  final int color;
  const SubjectGroup(this.id, this.name, this.color);

  static const all = <SubjectGroup>[
    SubjectGroup('kor', '국어', 0xFFD9534F),
    SubjectGroup('math', '수학', 0xFFE0703B),
    SubjectGroup('eng', '영어', 0xFF2F9E6E),
    SubjectGroup('soc', '사회', 0xFF8C5BD6),
    SubjectGroup('sci', '과학', 0xFF2F6BFF),
  ];

  static SubjectGroup? byId(String id) {
    for (final g in all) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// 학년 값 (schema `grades`).
/// 학년 값 (고등 전용 서비스).
const List<String> kGrades = ['고1', '고2', '고3', 'N수'];

/// A course (과목): 물리학Ⅰ, 수학Ⅰ, 국어(독서)… — one JSON file.
class Subject {
  final String id;
  final String name;

  /// ARGB, parsed from "#RRGGBB".
  final int color;

  /// Problems shown in lists / 무한 풀기 (authored twins are kept in [twins]).
  final List<Problem> problems;
  final List<Problem> twins;
  final List<Passage> passages;

  /// kor | math | eng | soc | sci ('' for 내 문제).
  final String group;

  /// mid | high
  final String level;
  final List<String> grades;
  final String track;
  final List<String> unitOrder;

  const Subject({
    required this.id,
    required this.name,
    required this.color,
    required this.problems,
    this.twins = const <Problem>[],
    this.passages = const <Passage>[],
    this.group = '',
    this.level = 'high',
    this.grades = const <String>[],
    this.track = '',
    this.unitOrder = const <String>[],
  });

  bool get isMiddle => level == 'mid';

  /// Units (대단원): declared order first, then any others in first-appearance order.
  List<String> get units {
    final seen = <String>{};
    final out = <String>[];
    final present = {for (final p in problems) p.unit};
    for (final u in unitOrder) {
      if (present.contains(u) && seen.add(u)) out.add(u);
    }
    for (final p in problems) {
      if (seen.add(p.unit)) out.add(p.unit);
    }
    return out;
  }

  List<Problem> problemsInUnit(String unit) =>
      problems.where((p) => p.unit == unit).toList();

  Passage? passage(String? id) {
    if (id == null) return null;
    for (final p in passages) {
      if (p.id == id) return p;
    }
    return null;
  }

  Subject copyWith({List<Problem>? problems, List<Problem>? twins, List<Passage>? passages}) => Subject(
        id: id,
        name: name,
        color: color,
        problems: problems ?? this.problems,
        twins: twins ?? this.twins,
        passages: passages ?? this.passages,
        group: group,
        level: level,
        grades: grades,
        track: track,
        unitOrder: unitOrder,
      );

  factory Subject.fromJson(Map<String, dynamic> j) {
    final id = _str(j['subjectId'], _str(j['id']));
    final name = _str(j['subject'], _str(j['name'], id));
    final raw = j['problems'];
    final problems = <Problem>[];
    final twins = <Problem>[];
    if (raw is List) {
      for (final e in raw) {
        final m = _map(e);
        if (m == null) continue;
        final p = Problem.fromJson(m, subjectId: id, subjectName: name);
        (p.isTwin ? twins : problems).add(p);
      }
    }
    final passages = <Passage>[];
    final rawP = j['passages'];
    if (rawP is List) {
      for (final e in rawP) {
        final m = _map(e);
        if (m != null) passages.add(Passage.fromJson(m));
      }
    }
    return Subject(
      id: id,
      name: name,
      color: parseColor(j['color']),
      problems: List<Problem>.unmodifiable(problems),
      twins: List<Problem>.unmodifiable(twins),
      passages: List<Passage>.unmodifiable(passages),
      group: _str(j['group']),
      level: _str(j['level'], 'high'),
      grades: _strList(j['grades']),
      track: _str(j['track']),
      unitOrder: _strList(j['units']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subject': name,
        'subjectId': id,
        'color': colorToHex(color),
        if (group.isNotEmpty) 'group': group,
        'level': level,
        if (grades.isNotEmpty) 'grades': grades,
        if (track.isNotEmpty) 'track': track,
        if (unitOrder.isNotEmpty) 'units': unitOrder,
        if (passages.isNotEmpty) 'passages': [for (final p in passages) p.toJson()],
        'problems': [for (final p in [...problems, ...twins]) p.toJson()],
      };
}

/// 문제집 (assets/problems/workbooks.json).
/// 커리큘럼 단계 — 문제집 고르기 화면이 이 순서로 보여 준다.
const List<String> kWorkbookStages = ['개념', '유형', '기출', 'N제', '모의고사'];

String _stageFromLevel(String level) => switch (level) {
      '기본' => '개념',
      '모의고사' => '모의고사',
      _ => 'N제',
    };

class Workbook {
  final String id;
  final String title;
  final String course;
  final String level;
  final String desc;
  final List<String> problemIds;

  /// 시리즈 이름 (예: FLOW TYPE) — such workbooks may mix several courses.
  final String series;

  /// 커리큘럼 단계: 개념 | 유형 | 기출 | N제 | 모의고사 (없으면 level 로 짐작).
  final String stage;

  /// 범위 (예: 수학Ⅰ, 공통수학1, 역학) — 같은 과목 안에서 다시 나눌 때.
  final String scope;

  /// 만든 곳 (예: LAST30 ITEM LAB).
  final String publisher;

  const Workbook({
    required this.id,
    required this.title,
    required this.course,
    this.level = '기본',
    this.desc = '',
    this.problemIds = const <String>[],
    this.series = '',
    this.stage = '개념',
    this.scope = '',
    this.publisher = '',
  });

  int get stageIndex {
    final i = kWorkbookStages.indexOf(stage);
    return i < 0 ? kWorkbookStages.length : i;
  }

  factory Workbook.fromJson(Map<String, dynamic> j) {
    final level = _str(j['level'], '기본');
    final stage = _str(j['stage']);
    return Workbook(
      id: _str(j['id']),
      title: _str(j['title']),
      course: _str(j['course']),
      level: level,
      desc: _str(j['desc']),
      problemIds: _strList(j['problems']),
      series: _str(j['series']),
      stage: kWorkbookStages.contains(stage) ? stage : _stageFromLevel(level),
      scope: _str(j['scope']),
      publisher: _str(j['publisher']),
    );
  }

  static List<Workbook> listFromJson(Object? decoded) {
    final m = _map(decoded);
    final raw = m == null ? decoded : m['workbooks'];
    final out = <Workbook>[];
    if (raw is List) {
      for (final e in raw) {
        final w = _map(e);
        if (w != null) out.add(Workbook.fromJson(w));
      }
    }
    return out;
  }
}
