/// Learning records: attempts and per-problem state (오답노트 / 복습 일정).

class Attempt {
  final String id;
  final String problemId; // may be a variant id "base~v123"
  final String baseId;
  final String subjectId;
  final String unit;
  final String topic;
  final String answer;
  final String expected;
  final bool correct;
  final int timeMs;
  final int at;
  final String mode; // practice | review | variant | today
  final bool hasInk;

  const Attempt({
    required this.id,
    required this.problemId,
    required this.baseId,
    required this.subjectId,
    required this.unit,
    required this.topic,
    required this.answer,
    required this.expected,
    required this.correct,
    required this.timeMs,
    required this.at,
    required this.mode,
    required this.hasInk,
  });

  bool get isVariant => problemId != baseId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pid': problemId,
        'base': baseId,
        'sub': subjectId,
        'unit': unit,
        'topic': topic,
        'ans': answer,
        'exp': expected,
        'ok': correct,
        'ms': timeMs,
        'at': at,
        'mode': mode,
        'ink': hasInk,
      };

  static Attempt fromJson(Map<String, dynamic> j) => Attempt(
        id: j['id'] as String,
        problemId: j['pid'] as String,
        baseId: (j['base'] as String?) ?? j['pid'] as String,
        subjectId: (j['sub'] as String?) ?? '',
        unit: (j['unit'] as String?) ?? '',
        topic: (j['topic'] as String?) ?? '',
        answer: (j['ans'] as String?) ?? '',
        expected: (j['exp'] as String?) ?? '',
        correct: j['ok'] == true,
        timeMs: (j['ms'] as num?)?.toInt() ?? 0,
        at: (j['at'] as num?)?.toInt() ?? 0,
        mode: (j['mode'] as String?) ?? 'practice',
        hasInk: j['ink'] == true,
      );
}

/// Review intervals in days for 오답 복습 (stage 0 → 1 day, …).
const List<int> kReviewIntervals = [1, 3, 7, 14];

class ProblemState {
  final String baseId;
  int attempts;
  int correct;
  int wrong;
  bool? lastCorrect;
  int lastAt;
  bool inWrongNote;
  int reviewStage;
  int? nextReviewAt;
  int? resolvedAt;
  bool bookmarked;
  String note;
  String? lastWrongAnswer;
  String? lastWrongAttemptId;

  ProblemState(
    this.baseId, {
    this.attempts = 0,
    this.correct = 0,
    this.wrong = 0,
    this.lastCorrect,
    this.lastAt = 0,
    this.inWrongNote = false,
    this.reviewStage = 0,
    this.nextReviewAt,
    this.resolvedAt,
    this.bookmarked = false,
    this.note = '',
    this.lastWrongAnswer,
    this.lastWrongAttemptId,
  });

  bool isDue(int now) => inWrongNote && (nextReviewAt ?? 0) <= now;

  /// Apply one graded attempt (base or variant).
  void apply({required bool ok, required int at, required String answer, required String attemptId}) {
    attempts++;
    lastAt = at;
    lastCorrect = ok;
    if (ok) {
      correct++;
      if (inWrongNote) {
        reviewStage++;
        if (reviewStage >= kReviewIntervals.length - 1) {
          inWrongNote = false;
          resolvedAt = at;
          nextReviewAt = null;
        } else {
          nextReviewAt = at + kReviewIntervals[reviewStage] * Duration.millisecondsPerDay;
        }
      }
    } else {
      wrong++;
      inWrongNote = true;
      reviewStage = 0;
      resolvedAt = null;
      // allow an immediate retry today, then schedule tomorrow
      nextReviewAt = at + kReviewIntervals[0] * Duration.millisecondsPerDay;
      lastWrongAnswer = answer;
      lastWrongAttemptId = attemptId;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': baseId,
        'n': attempts,
        'c': correct,
        'w': wrong,
        'last': lastCorrect,
        'lastAt': lastAt,
        'wn': inWrongNote,
        'stage': reviewStage,
        'next': nextReviewAt,
        'resolved': resolvedAt,
        'bm': bookmarked,
        'note': note,
        'lwa': lastWrongAnswer,
        'lwid': lastWrongAttemptId,
      };

  static ProblemState fromJson(Map<String, dynamic> j) => ProblemState(
        j['id'] as String,
        attempts: (j['n'] as num?)?.toInt() ?? 0,
        correct: (j['c'] as num?)?.toInt() ?? 0,
        wrong: (j['w'] as num?)?.toInt() ?? 0,
        lastCorrect: j['last'] as bool?,
        lastAt: (j['lastAt'] as num?)?.toInt() ?? 0,
        inWrongNote: j['wn'] == true,
        reviewStage: (j['stage'] as num?)?.toInt() ?? 0,
        nextReviewAt: (j['next'] as num?)?.toInt(),
        resolvedAt: (j['resolved'] as num?)?.toInt(),
        bookmarked: j['bm'] == true,
        note: (j['note'] as String?) ?? '',
        lastWrongAnswer: j['lwa'] as String?,
        lastWrongAttemptId: j['lwid'] as String?,
      );
}

class Profile {
  final String id;
  String name;
  int color;
  final int createdAt;

  Profile({required this.id, required this.name, required this.color, required this.createdAt});

  String get initial => name.isEmpty ? '?' : name.characters1;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color, 'createdAt': createdAt};

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '학생',
        color: (j['color'] as num?)?.toInt() ?? 0xFF2F6BFF,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

extension _FirstChar on String {
  String get characters1 => runes.isEmpty ? '' : String.fromCharCode(runes.first);
}

class AppSettings {
  int dailyGoal;
  String serverUrl;
  bool liveEnabled;
  bool showTimer;
  bool handwritingAnswer;
  bool autoAdvance;
  bool shuffleChoicesInVariants;

  AppSettings({
    this.dailyGoal = 10,
    this.serverUrl = '',
    this.liveEnabled = false,
    this.showTimer = true,
    this.handwritingAnswer = true,
    this.autoAdvance = false,
    this.shuffleChoicesInVariants = true,
  });

  Map<String, dynamic> toJson() => {
        'dailyGoal': dailyGoal,
        'serverUrl': serverUrl,
        'liveEnabled': liveEnabled,
        'showTimer': showTimer,
        'handwritingAnswer': handwritingAnswer,
        'autoAdvance': autoAdvance,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        dailyGoal: (j['dailyGoal'] as num?)?.toInt() ?? 10,
        serverUrl: (j['serverUrl'] as String?) ?? '',
        liveEnabled: j['liveEnabled'] == true,
        showTimer: j['showTimer'] != false,
        handwritingAnswer: j['handwritingAnswer'] != false,
        autoAdvance: j['autoAdvance'] == true,
      );
}
