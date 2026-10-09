/// Learner profile and study-management records (학년·목표·과목·문제집, 구독, 매일 세트,
/// 순공 시간, 할 일, 모의고사 성적). Stored per profile in state.json under "learner".
library;

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
String _s(Object? v, [String d = '']) => v is String ? v : d;
List<String> _ls(Object? v) => v is List ? [for (final e in v) '$e'] : <String>[];

/// 수능 is held on a Thursday in mid-November; default D-day target (editable).
DateTime defaultSuneungDate(DateTime now) {
  DateTime thirdThursday(int year) {
    var d = DateTime(year, 11, 1);
    while (d.weekday != DateTime.thursday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(const Duration(days: 14));
  }

  final known = {2026: DateTime(2026, 11, 19), 2027: DateTime(2027, 11, 18)};
  var d = known[now.year] ?? thirdThursday(now.year);
  if (!d.isAfter(DateTime(now.year, now.month, now.day))) d = known[now.year + 1] ?? thirdThursday(now.year + 1);
  return d;
}

class Learner {
  bool onboarded;

  /// 대표 학년 (커뮤니티·순위에 보이는 값) — [grades] 의 첫 번째.
  String grade;

  /// 고른 학년·과정 전부 (복수 선택: 한양대 + N수 + 편입 …). 과목·교재 목록이 이걸로 걸러진다.
  List<String> grades;

  /// 수능 | 내신 | 둘 다
  String goal;

  /// Selected course ids (empty = every course for the grade).
  List<String> courses;
  List<String> workbooks;

  String examName;
  int examDate; // ms since epoch (local midnight)

  // subscription (결제 연동 전: 체험 상태만 관리)
  int trialStartedAt;
  String plan; // '' | monthly | yearly
  int subscribedAt;

  /// 커뮤니티 닉네임 ('' → 가린 이름 "오XX")
  String nickname;

  /// 공부시간 순위에 참여 (이름은 첫 글자만 공개)
  bool rankingOptIn;

  Learner({
    this.onboarded = false,
    this.grade = '고2',
    List<String>? grades,
    this.goal = '수능',
    List<String>? courses,
    List<String>? workbooks,
    this.examName = '수능',
    this.examDate = 0,
    this.trialStartedAt = 0,
    this.plan = '',
    this.subscribedAt = 0,
    this.nickname = '',
    this.rankingOptIn = true,
  })  : grades = (grades == null || grades.isEmpty) ? <String>[grade] : List<String>.of(grades),
        courses = courses ?? <String>[],
        workbooks = workbooks ?? <String>[];


  /// 학년·과정을 한꺼번에 바꾼다 (첫 번째가 대표). 빈 목록은 무시한다.
  void setGrades(List<String> gs) {
    final l = <String>[];
    for (final g in gs) {
      if (g.isNotEmpty && !l.contains(g)) l.add(g);
    }
    if (l.isEmpty) return;
    grades = l;
    grade = l.first;
  }

  /// 화면에 보여 줄 이름: "한양대 · N수 · 편입"
  String get gradeLabel => grades.isEmpty ? grade : grades.join(' · ');

  Map<String, dynamic> toJson() => {
        'onboarded': onboarded,
        'grade': grade,
        'grades': grades,
        'goal': goal,
        'courses': courses,
        'workbooks': workbooks,
        'examName': examName,
        'examDate': examDate,
        'trial': trialStartedAt,
        'plan': plan,
        'subAt': subscribedAt,
        'nick': nickname,
        'rank': rankingOptIn,
      };

  static Learner fromJson(Map<String, dynamic> j) {
    final gs = _ls(j['grades']);
    return Learner(
        onboarded: j['onboarded'] == true,
        grade: gs.isNotEmpty ? gs.first : _s(j['grade'], '고2'),
        grades: gs,
        goal: _s(j['goal'], '수능'),
        courses: _ls(j['courses']),
        workbooks: _ls(j['workbooks']),
        examName: _s(j['examName'], '수능'),
        examDate: _i(j['examDate']),
        trialStartedAt: _i(j['trial']),
        plan: _s(j['plan']),
        subscribedAt: _i(j['subAt']),
        nickname: _s(j['nick']),
        rankingOptIn: j['rank'] != false,
    );
  }
}

/// 매일 오답 변형 세트 — generated once per day.
class DailySet {
  final String day;
  final List<String> problemIds;
  final Set<String> done;

  /// Why each problem is in the set: twin | variant | review | similar | weak | new
  final Map<String, String> reasons;

  DailySet({required this.day, required this.problemIds, Set<String>? done, Map<String, String>? reasons})
      : done = done ?? <String>{},
        reasons = reasons ?? <String, String>{};

  bool get complete => problemIds.isNotEmpty && problemIds.every(done.contains);
  int get doneCount => problemIds.where(done.contains).length;

  int count(String reason) => reasons.values.where((r) => r == reason).length;

  Map<String, dynamic> toJson() => {'day': day, 'ids': problemIds, 'done': done.toList(), 'why': reasons};

  static DailySet fromJson(Map<String, dynamic> j) => DailySet(
        day: _s(j['day']),
        problemIds: _ls(j['ids']),
        done: _ls(j['done']).toSet(),
        reasons: (j['why'] is Map) ? (j['why'] as Map).map((k, v) => MapEntry('$k', '$v')) : <String, String>{},
      );
}

/// One 순공 timer session.
class StudySession {
  final int start;
  final int ms;
  const StudySession(this.start, this.ms);
  Map<String, dynamic> toJson() => {'s': start, 'ms': ms};
  static StudySession fromJson(Map<String, dynamic> j) => StudySession(_i(j['s']), _i(j['ms']));
}

class TodoItem {
  final String id;
  String text;
  bool done;
  final String day;
  TodoItem({required this.id, required this.text, this.done = false, required this.day});
  Map<String, dynamic> toJson() => {'id': id, 't': text, 'd': done, 'day': day};
  static TodoItem fromJson(Map<String, dynamic> j) =>
      TodoItem(id: _s(j['id']), text: _s(j['t']), done: j['d'] == true, day: _s(j['day']));
}

/// 모의고사 성적 한 회.
class ExamScore {
  final String id;
  String name;
  int date;

  /// 과목 이름 → 등급 (1~9)
  Map<String, int> grades;

  /// 과목 이름 → 원점수 (선택)
  Map<String, int> raw;

  ExamScore({required this.id, required this.name, required this.date, Map<String, int>? grades, Map<String, int>? raw})
      : grades = grades ?? <String, int>{},
        raw = raw ?? <String, int>{};

  double? get average {
    if (grades.isEmpty) return null;
    return grades.values.fold<int>(0, (a, b) => a + b) / grades.length;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'date': date, 'g': grades, 'r': raw};

  static Map<String, int> _mi(Object? v) =>
      v is Map ? v.map((k, val) => MapEntry('$k', val is num ? val.toInt() : 0)) : <String, int>{};

  static ExamScore fromJson(Map<String, dynamic> j) =>
      ExamScore(id: _s(j['id']), name: _s(j['name']), date: _i(j['date']), grades: _mi(j['g']), raw: _mi(j['r']));
}

/// Subjects shown when entering 모의고사 성적.
const List<String> kScoreSubjects = ['국어', '수학', '영어', '한국사', '탐구1', '탐구2'];
