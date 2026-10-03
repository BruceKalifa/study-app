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

  /// Created by the user in the app.
  final bool custom;

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
    this.custom = false,
  });

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
      custom: j['custom'] == true,
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
    if (custom) m['custom'] = true;
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
      custom: custom ?? this.custom,
    );
  }

  @override
  String toString() => 'Problem($id)';
}

class Subject {
  final String id;
  final String name;

  /// ARGB, parsed from "#RRGGBB".
  final int color;
  final List<Problem> problems;

  const Subject({
    required this.id,
    required this.name,
    required this.color,
    required this.problems,
  });

  /// Units (대단원) in first-appearance order.
  List<String> get units {
    final seen = <String>{};
    final out = <String>[];
    for (final p in problems) {
      if (seen.add(p.unit)) out.add(p.unit);
    }
    return out;
  }

  List<Problem> problemsInUnit(String unit) =>
      problems.where((p) => p.unit == unit).toList();

  factory Subject.fromJson(Map<String, dynamic> j) {
    final id = _str(j['subjectId'], _str(j['id']));
    final name = _str(j['subject'], _str(j['name'], id));
    final raw = j['problems'];
    final problems = <Problem>[];
    if (raw is List) {
      for (final e in raw) {
        final m = _map(e);
        if (m == null) continue;
        problems.add(Problem.fromJson(m, subjectId: id, subjectName: name));
      }
    }
    return Subject(
      id: id,
      name: name,
      color: parseColor(j['color']),
      problems: List<Problem>.unmodifiable(problems),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subject': name,
        'subjectId': id,
        'color': colorToHex(color),
        'problems': [for (final p in problems) p.toJson()],
      };
}
