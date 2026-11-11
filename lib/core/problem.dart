// Problem / Subject / Template models. See docs/problem-schema.md.

import 'pdf_ref.dart';

export 'pdf_ref.dart';

/// choice 객관식 · short 단답형 · essay 서술형 (답칸 없이 풀이를 쓰고 스스로 채점)
enum ProblemType { choice, short, essay }

/// 서술형 채점 기준 한 줄 ("치환을 바르게 세웠다", 2점).
class RubricItem {
  const RubricItem(this.text, this.points);
  final String text;
  final int points;

  /// {"text": "...", "points": 2} 또는 "치환을 세웠다 (2점)" / "치환을 세웠다 | 2"
  static RubricItem? fromJson(Object? j) {
    if (j is Map) {
      final t = '${j['text'] ?? ''}'.trim();
      final pts = j['points'];
      if (t.isEmpty) return null;
      return RubricItem(t, pts is num ? pts.toInt().clamp(0, 100) : 1);
    }
    if (j is String && j.trim().isNotEmpty) {
      final m = RegExp(r'^(.*?)[\s|:·\-]*\(?\s*(\d+)\s*점?\s*\)?\s*$').firstMatch(j.trim());
      if (m != null && m[1]!.trim().isNotEmpty) return RubricItem(m[1]!.trim(), int.parse(m[2]!));
      return RubricItem(j.trim(), 1);
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'text': text, 'points': points};
}


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

  /// 교재 목차 (예: 수업, DAY 1) — 교재를 목차별로 묶어 풀 때 쓴다. 없으면 단원으로 묶는다.
  final String section;
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

  /// 머리표 상자 색 (ARGB, 교재마다 다름 — 원문 \definecolor). null → 검정 (labelAccent 면 주황).
  final int? labelColor;

  /// TeX 원문을 옮긴 문항: 원문처럼 본문 글꼴(Noto Serif KR)과 글줄 수식(text style)으로 그린다.
  final bool texStyle;

  /// 배점 (null → 난이도로 2·3·4점, 0 → 표시하지 않음).
  final int? points;

  /// 원본 PDF 의 문항 영역 — 있으면 본문 대신 PDF 를 그대로 그린다 ([stem] 은 검색·목록용 글).
  final PdfRegion? pdf;

  /// 원본 PDF 의 해설 영역 — 있으면 해설 글 대신 그대로 보여 준다.
  final PdfRegion? solutionPdf;

  const Problem({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    this.unit = '',
    this.topic = '',
    this.section = '',
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
    this.labelColor,
    this.texStyle = false,
    this.points,
    this.pdf,
    this.solutionPdf,
    this.rubric = const <RubricItem>[],
  });

  /// 서술형 채점 기준 (없으면 다 맞음 / 일부 / 틀림 세 단계로 스스로 매긴다).
  final List<RubricItem> rubric;

  bool get isTwin => twinOf != null;
  bool get isEssay => type == ProblemType.essay;

  /// 답칸에 손글씨로 답을 쓰고 자동 채점하는 문항.
  bool get isShort => type == ProblemType.short;

  /// 서술형 만점 (채점 기준의 합 · 없으면 배점 · 그것도 없으면 10).
  int get essayMax {
    final r = rubric.fold<int>(0, (a, b) => a + b.points);
    if (r > 0) return r;
    return (points ?? 0) > 0 ? points! : 10;
  }

  /// The problem whose 오답 record this problem feeds (variant/twin → original).
  String get familyId => variantOf ?? twinOf ?? id;

  bool get isVariant => variantOf != null;
  bool get hasTemplate => template != null;
  bool get isChoice => type == ProblemType.choice;

  bool get hasSolution => solution.trim().isNotEmpty || solutionPdf != null;

  /// 선지 수 — 원본 PDF 문항은 PDF 에서 찾은 선지 자리 수 (못 찾았으면 5).
  int get choiceCount {
    if (choices.isNotEmpty) return choices.length;
    final r = pdf;
    if (r != null && isChoice) return r.choices.isNotEmpty ? r.choices.length : 5;
    return 0;
  }

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
    } else if (typeStr == 'essay' || typeStr == '서술형' || typeStr == '서술') {
      type = ProblemType.essay;
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
      section: _str(j['section']),
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
      labelColor: j['labelColor'] == null ? null : parseColor(j['labelColor'], 0xFF000000),
      texStyle: j['texStyle'] == true,
      points: _int(j['points']),
      pdf: PdfRegion.fromJson(j['pdf']),
      solutionPdf: PdfRegion.fromJson(j['solutionPdf']),
      rubric: [
        if (j['rubric'] is List)
          for (final r in j['rubric'] as List)
            if (RubricItem.fromJson(r) case final item?) item
      ],
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'unit': unit,
      'topic': topic,
      if (section.isNotEmpty) 'section': section,
      'difficulty': difficulty,
      'type': switch (type) { ProblemType.choice => 'choice', ProblemType.essay => 'essay', _ => 'short' },
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
    if (labelColor != null) m['labelColor'] = colorToHex(labelColor!);
    if (texStyle) m['texStyle'] = true;
    if (points != null) m['points'] = points;
    if (pdf != null) m['pdf'] = pdf!.toJson();
    if (solutionPdf != null) m['solutionPdf'] = solutionPdf!.toJson();
    if (rubric.isNotEmpty) m['rubric'] = [for (final r in rubric) r.toJson()];
    return m;
  }

  /// Nullable fields can be cleared with the `clear*` flags.
  Problem copyWith({
    String? id,
    String? subjectId,
    String? subjectName,
    String? unit,
    String? topic,
    String? section,
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
      section: section ?? this.section,
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
      labelColor: labelColor,
      texStyle: texStyle,
      points: points,
      pdf: pdf,
      solutionPdf: solutionPdf,
      rubric: rubric,
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

/// 개념 종류 (교재의 읽는 쪽).
const List<String> kConceptKinds = ['개념', '실전개념', '공식 정리'];

/// 개념 페이지 — 문제 없이 읽는 쪽 (개념 정리, 실전개념, 공식 정리). 교재 목차(section) 안에 문제와 섞여 나온다.
/// 본문은 문제와 같은 표기법($수식$, 표, 그림, 상자 …). 문제와는 [links] (또는 [topic]) 가 문제의 유형(topic)과 맞으면 이어진다.
class Concept {
  final String id;
  final String title;

  /// 개념 | 실전개념 | 공식 정리
  final String kind;
  final String unit;
  final String topic;

  /// 교재 목차 이름 (문항의 section 과 같게 쓰면 그 목차 안에 나온다).
  final String section;
  final String body;
  final String? source;

  /// 이 개념이 설명하는 문제 유형들. 문제의 유형(`·` 로 나눈 토막)과 같으면 "관련 개념" 으로 이어진다. 비면 [topic] 을 쓴다.
  final List<String> links;

  /// PDF 에서 만든 쪽 이미지 (`data:image/webp;base64,…` 또는 주소). 있으면 본문 대신 이 그림들을 위아래로 펼쳐 PDF 그대로 보여 준다.
  final List<String> images;

  /// 3D 모션 그래픽 수업 (docs/lesson3d.md) — `Solvit3D.lesson(…)` 이 든 HTML 한 장. 있으면 앱이 3D 수업으로 연다.
  final String lesson3d;

  /// 원본 PDF 의 쪽들 — 있으면 개념책 화면에서 PDF 그대로 넘겨 읽는다.
  final PdfPages? pdf;
  const Concept({
    required this.id,
    this.title = '',
    this.kind = '개념',
    this.unit = '',
    this.topic = '',
    this.section = '',
    required this.body,
    this.source,
    this.links = const <String>[],
    this.images = const <String>[],
    this.lesson3d = '',
    this.pdf,
  });

  factory Concept.fromJson(Map<String, dynamic> j) {
    final kind = _str(j['kind'], '개념');
    return Concept(
      id: _str(j['id']),
      title: _str(j['title']),
      kind: kind.isEmpty ? '개념' : kind,
      unit: _str(j['unit']),
      topic: _str(j['topic']),
      section: _str(j['section']),
      body: _str(j['body']),
      source: _strOrNull(j['source']),
      links: _strList(j['links']),
      images: _strList(j['images']),
      lesson3d: _str(j['lesson3d']),
      pdf: PdfPages.fromJson(j['pdf']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (kind != '개념') 'kind': kind,
        if (unit.isNotEmpty) 'unit': unit,
        if (topic.isNotEmpty) 'topic': topic,
        if (section.isNotEmpty) 'section': section,
        'body': body,
        if (source != null) 'source': source,
        if (links.isNotEmpty) 'links': links,
        if (images.isNotEmpty) 'images': images,
        if (lesson3d.isNotEmpty) 'lesson3d': lesson3d,
        if (pdf != null) 'pdf': pdf!.toJson(),
      };

  /// 이 개념이 설명하는 문제인가 — 문제 유형을 `·` 로 나눈 토막이 연결 이름과 같으면.
  bool explains(Problem p) {
    final keys = <String>[
      for (final l in (links.isNotEmpty ? links : <String>[topic])) if (l.trim().isNotEmpty) l.trim(),
    ];
    if (keys.isEmpty) return false;
    final t = p.topic.trim();
    final parts = [for (final x in t.split('·')) x.trim()];
    for (final k in keys) {
      if (t == k || parts.contains(k)) return true;
    }
    return false;
  }
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
    SubjectGroup('apt', '인적성', 0xFF0E7C86),
    SubjectGroup('univ', '대학', 0xFF6D4AFF),
  ];

  static SubjectGroup? byId(String id) {
    for (final g in all) {
      if (g.id == id) return g;
    }
    return null;
  }
}

/// 대학생이 고르는 학교. 학교 이름이 곧 학년 값이다 (예: '인하대'). 목록에 없는 학교는 [kUnivGeneric] ('대학생').
/// server/http-util.js · server/public/admin/schema.js · tools/text_book.py 의 UNIVERSITIES 와 같아야 한다.
const List<String> kUniversities = [
  '한양대', '서울대', '연세대', '고려대', '서강대', '성균관대', '중앙대', '경희대', '한국외대', '서울시립대',
  '건국대', '동국대', '홍익대', '국민대', '숭실대', '세종대', '단국대', '광운대', '명지대', '상명대',
  '가톨릭대', '이화여대', '숙명여대', '서울과기대', '한국항공대', '인하대', '인천대', '아주대', '가천대', '한국공학대',
  '한국기술교육대', 'KAIST', 'POSTECH', 'UNIST', 'GIST', 'DGIST', '부산대', '경북대', '전남대', '충남대',
  '충북대', '전북대', '강원대', '경상국립대', '부경대', '울산대',
];

/// 모든 대학생에게 보이는 교재·과목의 대상 값, 또 목록에 없는 학교 학생의 학년 값.
const String kUnivGeneric = '대학생';

bool isUniversity(String g) => g == kUnivGeneric || kUniversities.contains(g);

/// 학년 값 (schema `grades`). 고등·N수는 예전 가입자용(새 가입은 받지 않는다) · 인적성(취준) · 대학(학교별) · 편입.
const List<String> kGrades = ['고1', '고2', '고3', 'N수', '취준', kUnivGeneric, ...kUniversities, '편입'];

/// 새로 가입할 때 고르는 과정. '대학생' 을 고르면 학교를 고른다.
const List<String> kSignupTracks = [kUnivGeneric, '취준', '편입'];

/// 비교용으로 넓힌 학년 값: 학교를 고른 학생은 '대학생' (모든 대학 공통) 교재도 본다.
Set<String> expandGrades(Iterable<String> grades) {
  final out = <String>{...grades};
  if (out.any(isUniversity)) out.add(kUnivGeneric);
  return out;
}

/// 과목 대상과 학생 학년이 겹치는지. 과목 쪽 학교 값도 '대학생' 으로 넓혀서 본다
/// (예전에 '한양대' 로만 올린 공업수학·미분적분학 과목도 모든 대학생에게 보인다 — 학교별로 나누는 것은 교재의 `schools`).
bool gradesOverlap(Iterable<String> courseGrades, Iterable<String> learnerGrades) {
  final c = courseGrades.toList();
  if (c.isEmpty) return true;
  final l = expandGrades(learnerGrades);
  return expandGrades(c).any(l.contains);
}

/// 과목 이름 정리: 고등학교 수학 과목(`math`)은 "수학" 이 아니라 "고등수학" 으로 보인다
/// (편입수학·대학수학·공업수학 등과 헷갈리지 않게). 이미 올라가 있는 교재 파일에도 똑같이 적용된다.
String canonicalSubjectName(String id, String name) {
  final n = name.trim();
  if (id == 'math' && n == '수학') return '고등수학';
  // 대학 미적분 과목은 "미분적분학1·2" (예전에 올린 교재 파일의 "미적분학1·2" 도 똑같이 보인다)
  if (id == 'calc1' && n == '미적분학1') return '미분적분학1';
  if (id == 'calc2' && n == '미적분학2') return '미분적분학2';
  return name;
}

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

  /// 개념 페이지 (문제 없이 읽는 쪽).
  final List<Concept> concepts;

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
    this.concepts = const <Concept>[],
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

  Subject copyWith(
          {List<Problem>? problems, List<Problem>? twins, List<Passage>? passages, List<Concept>? concepts}) =>
      Subject(
        id: id,
        name: name,
        color: color,
        problems: problems ?? this.problems,
        twins: twins ?? this.twins,
        passages: passages ?? this.passages,
        concepts: concepts ?? this.concepts,
        group: group,
        level: level,
        grades: grades,
        track: track,
        unitOrder: unitOrder,
      );

  factory Subject.fromJson(Map<String, dynamic> j) {
    final id = _str(j['subjectId'], _str(j['id']));
    final name = canonicalSubjectName(id, _str(j['subject'], _str(j['name'], id)));
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
    final concepts = <Concept>[];
    final rawC = j['concepts'];
    if (rawC is List) {
      for (final e in rawC) {
        final m = _map(e);
        if (m == null) continue;
        final c = Concept.fromJson(m);
        if (c.id.isNotEmpty) concepts.add(c);
      }
    }
    return Subject(
      id: id,
      name: name,
      color: parseColor(j['color']),
      problems: List<Problem>.unmodifiable(problems),
      twins: List<Problem>.unmodifiable(twins),
      passages: List<Passage>.unmodifiable(passages),
      concepts: List<Concept>.unmodifiable(concepts),
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
        if (concepts.isNotEmpty) 'concepts': [for (final c in concepts) c.toJson()],
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

  /// 이 교재에 든 개념 페이지 id (읽는 순서). 문제와 같은 목차 안에 섞여 나온다.
  final List<String> conceptIds;

  /// 시리즈 이름 (예: FLOW TYPE) — such workbooks may mix several courses.
  final String series;

  /// 커리큘럼 단계: 개념 | 유형 | 기출 | N제 | 모의고사 (없으면 level 로 짐작).
  final String stage;

  /// 범위 (예: 수학Ⅰ, 공통수학1, 역학) — 같은 과목 안에서 다시 나눌 때.
  final String scope;

  /// 만든 곳 (예: LAST30 ITEM LAB).
  final String publisher;

  /// 이 교재를 볼 학교 (예: ['인하대']). 비면 모든 학생에게 보인다.
  final List<String> schools;

  const Workbook({
    required this.id,
    required this.title,
    required this.course,
    this.level = '기본',
    this.desc = '',
    this.problemIds = const <String>[],
    this.conceptIds = const <String>[],
    this.series = '',
    this.stage = '개념',
    this.scope = '',
    this.publisher = '',
    this.schools = const <String>[],
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
      conceptIds: _strList(j['concepts']),
      series: _str(j['series']),
      stage: kWorkbookStages.contains(stage) ? stage : _stageFromLevel(level),
      scope: _str(j['scope']),
      publisher: _str(j['publisher']),
      schools: _strList(j['schools']),
    );
  }

  Workbook withSchools(List<String> s) => Workbook(
        id: id,
        title: title,
        course: course,
        level: level,
        desc: desc,
        problemIds: problemIds,
        conceptIds: conceptIds,
        series: series,
        stage: stage,
        scope: scope,
        publisher: publisher,
        schools: s,
      );

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
