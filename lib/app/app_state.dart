import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/problem.dart';
import '../core/problem_bank.dart';
import '../core/variants.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_model.dart';
import '../services/community_api.dart';
import '../services/content_sync.dart';
import '../services/live_sync.dart';
import 'learner.dart';
import 'records.dart';
import 'storage.dart';
import 'theme.dart';

class Tally {
  int solved = 0;
  int correct = 0;
  int timeMs = 0;
  double get accuracy => solved == 0 ? 0 : correct / solved;
}

class AppState extends ChangeNotifier {
  AppState({required this.storage, required ProblemBank baseBank, this.enableLive = true})
      : _baseBank = baseBank,
        _contentBank = baseBank,
        bank = baseBank;

  final Storage storage;
  final ProblemBank _baseBank;

  /// Bundled content + packs downloaded from the content server.
  ProblemBank _contentBank;
  final bool enableLive;
  ProblemBank bank;

  List<Profile> profiles = [];
  late Profile profile;
  AppSettings settings = AppSettings();
  InkSettings ink = InkSettings();
  List<Attempt> attempts = [];
  Map<String, ProblemState> states = {};
  List<Problem> customProblems = [];
  bool ready = false;

  // learner / study management
  Learner learner = Learner();
  DailySet? _daily;
  List<StudySession> sessions = [];
  int? studyStartedAt;
  List<TodoItem> todos = [];
  List<ExamScore> scores = [];
  String syncMessage = '';
  bool syncing = false;

  LiveSync? _live;
  LiveSync? get live => _live;

  final math.Random _rand = math.Random();
  Timer? _saveTimer;
  int _revision = 0;

  // ------------------------------------------------------------------ init
  Future<void> init() async {
    final raw = await storage.read('profiles.json');
    String? currentId;
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        profiles = [for (final p in (j['list'] as List? ?? const [])) Profile.fromJson((p as Map).cast<String, dynamic>())];
        currentId = j['current'] as String?;
      } catch (e) {
        debugPrint('profiles.json broken: $e');
      }
    }
    if (profiles.isEmpty) {
      profiles = [Profile(id: _newId(), name: '학생', color: 0xFF2F6BFF, createdAt: _now)];
    }
    profile = profiles.firstWhere((p) => p.id == currentId, orElse: () => profiles.first);
    final (packs, wbs) = await ContentSync(storage).loadCached();
    if (packs.isNotEmpty || wbs != null) _contentBank = _baseBank.withPacks(packs, workbooks: wbs);
    await _loadProfileData();
    ready = true;
    notifyListeners();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;
  String _newId() => '${_now.toRadixString(36)}${_rand.nextInt(1 << 30).toRadixString(36)}';
  String _pp(String f) => 'profiles/${profile.id}/$f';

  Future<void> _loadProfileData() async {
    _drafts.clear();
    settings = AppSettings();
    ink = InkSettings();
    attempts = [];
    states = {};
    customProblems = [];
    learner = Learner();
    _daily = null;
    sessions = [];
    studyStartedAt = null;
    todos = [];
    scores = [];
    final raw = await storage.read(_pp('state.json'));
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['settings'] is Map) settings = AppSettings.fromJson((j['settings'] as Map).cast<String, dynamic>());
        if (j['ink'] is Map) ink = InkSettings.fromJson((j['ink'] as Map).cast<String, dynamic>());
        attempts = [
          for (final a in (j['attempts'] as List? ?? const [])) Attempt.fromJson((a as Map).cast<String, dynamic>())
        ];
        for (final s in (j['states'] as List? ?? const [])) {
          final st = ProblemState.fromJson((s as Map).cast<String, dynamic>());
          states[st.baseId] = st;
        }
        customProblems = [
          for (final p in (j['custom'] as List? ?? const []))
            Problem.fromJson((p as Map).cast<String, dynamic>(),
                subjectId: ProblemBank.customSubjectId, subjectName: ProblemBank.customSubjectName)
        ];
        Map<String, dynamic> m(Object? o) => (o as Map).cast<String, dynamic>();
        if (j['learner'] is Map) learner = Learner.fromJson(m(j['learner']));
        if (j['daily'] is Map) _daily = DailySet.fromJson(m(j['daily']));
        sessions = [for (final x in (j['sessions'] as List? ?? const [])) StudySession.fromJson(m(x))];
        studyStartedAt = (j['studyStart'] as num?)?.toInt();
        todos = [for (final x in (j['todos'] as List? ?? const [])) TodoItem.fromJson(m(x))];
        scores = [for (final x in (j['scores'] as List? ?? const [])) ExamScore.fromJson(m(x))];
      } catch (e) {
        debugPrint('state.json broken: $e');
      }
    }
    _rebuildBank();
    _configureLive();
    _revision++;
  }

  void _rebuildBank() {
    bank = customProblems.isEmpty ? _contentBank : _contentBank.withExtra(customProblems);
  }

  /// Called when the app comes back to the foreground.
  void onResumed() {
    _live?.reconnect();
    reportStudy();
  }

  void _configureLive() {
    if (!enableLive) return;
    final l = _live ??= LiveSync(studentId: profile.id, name: profile.name);
    l.configure(enabled: settings.liveEnabled, url: settings.serverUrl, name: profile.name, studentId: profile.id);
  }

  void _changed({bool save = true}) {
    _revision++;
    _statsCache = null;
    if (save) _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final data = jsonEncode({
      'v': 1,
      'settings': settings.toJson(),
      'ink': ink.toJson(),
      'attempts': [for (final a in attempts) a.toJson()],
      'states': [for (final s in states.values) s.toJson()],
      'custom': [for (final p in customProblems) p.toJson()],
      'learner': learner.toJson(),
      if (_daily != null) 'daily': _daily!.toJson(),
      'sessions': [for (final x in sessions) x.toJson()],
      'studyStart': studyStartedAt,
      'todos': [for (final x in todos) x.toJson()],
      'scores': [for (final x in scores) x.toJson()],
    });
    await storage.write(_pp('state.json'), data);
  }

  Future<void> _saveProfiles() => storage.write(
        'profiles.json',
        jsonEncode({'current': profile.id, 'list': [for (final p in profiles) p.toJson()]}),
      );

  // ------------------------------------------------------------ profiles
  Future<void> switchProfile(String id) async {
    if (id == profile.id) return;
    await saveNow();
    profile = profiles.firstWhere((p) => p.id == id, orElse: () => profile);
    await _saveProfiles();
    await _loadProfileData();
    notifyListeners();
  }

  Future<void> addProfile(String name) async {
    const colors = [0xFF2F6BFF, 0xFFFF6B4A, 0xFF169C6B, 0xFF8B5CF6, 0xFFE8A317, 0xFF0EA5E9, 0xFFEC4899];
    final p = Profile(
      id: _newId(),
      name: name.trim().isEmpty ? '학생 ${profiles.length + 1}' : name.trim(),
      color: colors[profiles.length % colors.length],
      createdAt: _now,
    );
    profiles = [...profiles, p];
    await switchProfile(p.id);
    await _saveProfiles();
  }

  Future<void> renameProfile(String name) async {
    if (name.trim().isEmpty) return;
    profile.name = name.trim();
    await _saveProfiles();
    _configureLive();
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (profiles.length <= 1) return;
    profiles = profiles.where((p) => p.id != id).toList();
    await storage.deleteDir('profiles/$id');
    if (profile.id == id) {
      profile = profiles.first;
      await _loadProfileData();
    }
    await _saveProfiles();
    notifyListeners();
  }

  // ------------------------------------------------------------ settings
  void updateSettings(void Function(AppSettings s) fn) {
    fn(settings);
    _configureLive();
    _changed();
  }

  void updateInk(void Function(InkSettings s) fn) {
    fn(ink);
    _changed();
  }

  // ------------------------------------------------------------ problems
  Problem? problem(String id) => bank.byId(id);

  /// Records of variants and authored twins count for their original problem.
  String baseIdOf(Problem p) => p.familyId;

  ProblemState stateOf(String baseId) => states[baseId] ?? ProblemState(baseId);

  bool isSolved(String baseId) => (states[baseId]?.attempts ?? 0) > 0;

  bool _attempted(String problemId) => attempts.any((a) => a.problemId == problemId);

  /// Is there any variant (authored twin or template) for this problem's family?
  bool hasVariant(Problem p) {
    final b = problem(p.familyId) ?? p;
    return b.hasTemplate || bank.twinsOf(b.id).isNotEmpty;
  }

  /// A variant of [base]'s family: an authored twin not tried yet, else a template variant,
  /// else any twin, else the original itself.
  Problem makeVariant(Problem base) {
    final b = problem(base.familyId) ?? base;
    final twins = bank.twinsOf(b.id).where((t) => t.id != base.id).toList()..shuffle(_rand);
    final fresh = twins.where((t) => !_attempted(t.id)).toList();
    if (fresh.isNotEmpty) return fresh.first;
    if (!b.hasTemplate) return twins.isNotEmpty ? twins.first : b;
    for (var i = 0; i < 6; i++) {
      try {
        return generateVariant(b, _rand.nextInt(1 << 30));
      } catch (_) {}
    }
    return b;
  }

  List<Problem> variantsFor(Problem base, int n) => [for (var i = 0; i < n; i++) makeVariant(base)];

  List<Problem> problemsWhere({String? subjectId, String? unit, bool onlyUnsolved = false, int? difficulty}) {
    final out = <Problem>[];
    for (final s in bank.subjects) {
      if (subjectId != null && s.id != subjectId) continue;
      for (final p in s.problems) {
        if (unit != null && p.unit != unit) continue;
        if (onlyUnsolved && isSolved(p.id)) continue;
        if (difficulty != null && p.difficulty != difficulty) continue;
        out.add(p);
      }
    }
    return out;
  }

  /// Today's mix: due 오답 reviews (as variants when possible) + new problems.
  List<Problem> todayMix() {
    final goal = math.max(5, settings.dailyGoal);
    final now = _now;
    final out = <Problem>[];
    final due = states.values.where((s) => s.isDue(now)).toList()
      ..sort((a, b) => (a.nextReviewAt ?? 0).compareTo(b.nextReviewAt ?? 0));
    for (final s in due.take((goal / 2).ceil())) {
      final p = problem(s.baseId);
      if (p == null) continue;
      out.add(p.hasTemplate && _rand.nextBool() ? makeVariant(p) : p);
    }
    final fresh = problemsWhere(onlyUnsolved: true)..shuffle(_rand);
    // spread over subjects
    fresh.sort((a, b) => a.difficulty.compareTo(b.difficulty));
    final bySubject = <String, List<Problem>>{};
    for (final p in fresh) {
      bySubject.putIfAbsent(p.subjectId, () => []).add(p);
    }
    final queues = bySubject.values.toList()..shuffle(_rand);
    var i = 0;
    while (out.length < goal && queues.any((q) => q.isNotEmpty)) {
      final q = queues[i % queues.length];
      if (q.isNotEmpty) out.add(q.removeAt(0));
      i++;
    }
    if (out.length < goal) {
      final weakest = bank.all.where((p) => !out.any((o) => baseIdOf(o) == p.id)).toList()
        ..sort((a, b) => _acc(a.id).compareTo(_acc(b.id)));
      for (final p in weakest.take(goal - out.length)) {
        out.add(p.hasTemplate ? makeVariant(p) : p);
      }
    }
    return out;
  }

  double _acc(String baseId) {
    final s = states[baseId];
    if (s == null || s.attempts == 0) return 0.5;
    return s.correct / s.attempts;
  }

  // ------------------------------------------------------------ recording
  Future<Attempt> record(
    Problem p, {
    required String answer,
    required String expected,
    required bool correct,
    required int timeMs,
    required String mode,
    InkDocument? inkDoc,
  }) async {
    final id = _newId();
    final baseId = baseIdOf(p);
    final hasInk = inkDoc != null && !inkDoc.isEmpty;
    final a = Attempt(
      id: id,
      problemId: p.id,
      baseId: baseId,
      subjectId: p.subjectId,
      unit: p.unit,
      topic: p.topic,
      answer: answer,
      expected: expected,
      correct: correct,
      timeMs: timeMs,
      at: _now,
      mode: mode,
      hasInk: hasInk,
    );
    attempts = [...attempts, a];
    final st = states[baseId] ?? ProblemState(baseId);
    st.apply(ok: correct, at: a.at, answer: answer, attemptId: id);
    states[baseId] = st;
    final d = _daily;
    if (d != null && d.day == dayKey(DateTime.now()) && d.problemIds.contains(p.id)) d.done.add(p.id);
    if (hasInk) {
      await storage.write(_pp('ink/$id.json'), jsonEncode(inkDoc!.toJson()));
    }
    _changed();
    reportStudy(now: false);
    final l = _live;
    if (l != null) {
      l.sendAnswer(problemId: p.id, answer: answer, correct: correct, timeMs: timeMs);
      l.sendStats(
        total: totalSolved,
        correct: totalCorrect,
        streak: streak,
        todayCount: todayCount,
        weakTopics: weakTopics.map((e) => e.$1).toList(),
      );
    }
    return a;
  }

  Future<InkDocument?> loadAttemptInk(String attemptId) async {
    final raw = await storage.read(_pp('ink/$attemptId.json'));
    if (raw == null) return null;
    try {
      return InkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String _draftKey(String problemId) => _pp('drafts/${problemId.replaceAll(RegExp(r'[^A-Za-z0-9_\-~]'), '_')}.json');

  // drafts are cached in memory so moving back and forth never reads a stale file
  final Map<String, InkDocument?> _drafts = {};

  Future<InkDocument?> loadDraft(String problemId) async {
    final key = _draftKey(problemId);
    if (_drafts.containsKey(key)) return _drafts[key];
    final raw = await storage.read(key);
    if (raw == null) return null;
    try {
      return InkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(String problemId, InkDocument doc) async {
    final key = _draftKey(problemId);
    if (doc.isEmpty) {
      _drafts[key] = null;
      await storage.delete(key);
    } else {
      _drafts[key] = doc;
      await storage.write(key, jsonEncode(doc.toJson()));
    }
  }

  Future<void> deleteDraft(String problemId) {
    final key = _draftKey(problemId);
    _drafts[key] = null;
    return storage.delete(key);
  }

  /// Replace all records with [list] (oldest first) and rebuild per-problem state.
  /// Used for demos/screenshots and data import.
  void seedAttempts(List<Attempt> list) {
    attempts = List<Attempt>.of(list)..sort((a, b) => a.at.compareTo(b.at));
    states = {};
    for (final a in attempts) {
      final st = states[a.baseId] ?? ProblemState(a.baseId);
      st.apply(ok: a.correct, at: a.at, answer: a.answer, attemptId: a.id);
      states[a.baseId] = st;
    }
    _changed();
  }

  Future<String?> readProfileFile(String name) => storage.read(_pp(name));
  Future<void> writeProfileFile(String name, String data) => storage.write(_pp(name), data);

  // ------------------------------------------------------------ wrong note
  List<ProblemState> get wrongNote {
    final now = _now;
    final l = states.values.where((s) => s.inWrongNote).toList();
    l.sort((a, b) {
      final ad = a.isDue(now) ? 0 : 1, bd = b.isDue(now) ? 0 : 1;
      if (ad != bd) return ad - bd;
      return b.lastAt.compareTo(a.lastAt);
    });
    return l;
  }

  List<ProblemState> get resolvedWrong =>
      states.values.where((s) => !s.inWrongNote && s.resolvedAt != null).toList()
        ..sort((a, b) => (b.resolvedAt ?? 0).compareTo(a.resolvedAt ?? 0));

  int get dueCount {
    final now = _now;
    return states.values.where((s) => s.isDue(now)).length;
  }

  void markResolved(String baseId) {
    final s = states[baseId];
    if (s == null) return;
    s.inWrongNote = false;
    s.resolvedAt = _now;
    s.nextReviewAt = null;
    _changed();
  }

  void addToWrongNote(String baseId) {
    final s = states[baseId] ?? ProblemState(baseId);
    s.inWrongNote = true;
    s.reviewStage = 0;
    s.nextReviewAt = _now;
    states[baseId] = s;
    _changed();
  }

  void toggleBookmark(String baseId) {
    final s = states[baseId] ?? ProblemState(baseId);
    s.bookmarked = !s.bookmarked;
    states[baseId] = s;
    _changed();
  }

  void setNote(String baseId, String note) {
    final s = states[baseId] ?? ProblemState(baseId);
    s.note = note;
    states[baseId] = s;
    _changed();
  }

  List<ProblemState> get bookmarks => states.values.where((s) => s.bookmarked).toList();

  // ------------------------------------------------------------ custom problems
  void saveCustom(Problem p) {
    final i = customProblems.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      customProblems[i] = p;
    } else {
      customProblems = [...customProblems, p];
    }
    _rebuildBank();
    _changed();
  }

  void deleteCustom(String id) {
    customProblems = customProblems.where((p) => p.id != id).toList();
    _rebuildBank();
    _changed();
  }

  String newCustomId() => 'my-${_newId()}';


  // ------------------------------------------------------------ learner: courses & workbooks
  bool get needsOnboarding => !learner.onboarded;

  /// Courses meant for [grade] (내 문제 excluded).
  List<Subject> coursesForGrade(String grade) => [
        for (final s in bank.subjects)
          if (s.id != ProblemBank.customSubjectId && (s.grades.isEmpty || s.grades.contains(grade))) s
      ];

  /// The learner's courses (all courses of the grade when none were picked).
  List<Subject> get myCourses {
    final picked = [
      for (final id in learner.courses)
        if (bank.subject(id) case final s?) s
    ];
    return picked.isNotEmpty ? picked : coursesForGrade(learner.grade);
  }

  Set<String> get myCourseIds => {for (final s in myCourses) s.id};

  List<Workbook> get myWorkbooks {
    final ids = myCourseIds;
    final picked = [
      for (final id in learner.workbooks)
        if (bank.workbook(id) case final w? when ids.contains(w.course)) w
    ];
    return picked.isNotEmpty ? picked : bank.workbooks.where((w) => ids.contains(w.course)).toList();
  }

  /// (solved, total) for a workbook.
  (int, int) workbookProgress(Workbook w) {
    var n = 0;
    for (final id in w.problemIds) {
      if (isSolved(id)) n++;
    }
    return (n, w.problemIds.length);
  }

  void completeOnboarding({
    required String name,
    required String grade,
    required String goal,
    required List<String> courses,
    required List<String> workbooks,
  }) {
    if (name.trim().isNotEmpty && name.trim() != profile.name) {
      profile.name = name.trim();
      _saveProfiles();
    }
    learner
      ..grade = grade
      ..goal = goal
      ..courses = courses
      ..workbooks = workbooks
      ..onboarded = true;
    if (learner.examDate == 0) {
      final d = defaultSuneungDate(DateTime.now());
      learner.examDate = d.millisecondsSinceEpoch;
      learner.examName = goal == '내신' ? '기말고사' : '수능';
    }
    if (learner.trialStartedAt == 0) learner.trialStartedAt = _now;
    _daily = null; // rebuild today's set for the new courses
    _configureLive();
    _changed();
  }

  void updateLearner(void Function(Learner l) fn) {
    fn(learner);
    _changed();
  }

  // ------------------------------------------------------------ D-day
  int get dDay {
    if (learner.examDate == 0) return 0;
    final t = DateTime.fromMillisecondsSinceEpoch(learner.examDate);
    final n = DateTime.now();
    return DateTime(t.year, t.month, t.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  }

  // ------------------------------------------------------------ subscription (결제 연동 전)
  static const int trialDays = 7;
  bool get subscribed => learner.plan.isNotEmpty;
  int get trialDaysLeft {
    if (learner.trialStartedAt == 0) return trialDays;
    final used = (_now - learner.trialStartedAt) ~/ Duration.millisecondsPerDay;
    return math.max(0, trialDays - used);
  }

  void subscribe(String plan) {
    learner
      ..plan = plan
      ..subscribedAt = _now;
    _changed();
  }

  void cancelSubscription() {
    learner.plan = '';
    _changed();
  }

  // ------------------------------------------------------------ 매일 오답 변형 세트
  DailySet get dailySet {
    final key = dayKey(DateTime.now());
    final d = _daily;
    if (d != null && d.day == key) return d;
    final fresh = _buildDaily(key);
    _daily = fresh;
    _scheduleSave();
    return fresh;
  }

  /// Make tomorrow's set now (e.g. after changing courses).
  void rebuildDailySet() {
    _daily = _buildDaily(dayKey(DateTime.now()));
    _changed();
  }

  List<Problem> get dailyProblems => [
        for (final id in dailySet.problemIds)
          if (problem(id) case final p?) p
      ];

  DailySet _buildDaily(String day) {
    final target = math.max(6, settings.dailyGoal);
    final mine = myCourseIds;
    bool inMine(Problem p) => mine.isEmpty || mine.contains(p.subjectId);
    final ids = <String>[];
    final why = <String, String>{};
    final usedFamilies = <String>{};
    void add(Problem p, String reason) {
      if (ids.contains(p.id)) return;
      ids.add(p.id);
      why[p.id] = reason;
      usedFamilies.add(p.familyId);
    }

    // 1) 최근 오답 → 쌍둥이 / 템플릿 변형 / 같은 유형 다른 문항
    final wrongs = states.values.where((s) => s.inWrongNote).toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));
    for (final st in wrongs) {
      if (ids.length >= (target * 0.6).ceil()) break;
      final base = problem(st.baseId);
      if (base == null || !inMine(base)) continue;
      final twins = bank.twinsOf(base.id).where((t) => !_attempted(t.id)).toList()..shuffle(_rand);
      if (twins.isNotEmpty) {
        add(twins.first, 'twin');
      } else if (base.hasTemplate) {
        add(makeVariant(base), 'variant');
      } else {
        final similar = bank.all
            .where((p) =>
                p.subjectId == base.subjectId &&
                p.topic == base.topic &&
                p.id != base.id &&
                !usedFamilies.contains(p.id) &&
                !isSolved(p.id))
            .toList();
        if (similar.isNotEmpty) {
          add(similar[_rand.nextInt(similar.length)], 'similar');
        } else {
          add(base, 'review');
        }
      }
    }
    // 2) 복습할 날이 된 오답
    final now = _now;
    for (final st in wrongs.where((s) => s.isDue(now))) {
      if (ids.length >= (target * 0.75).ceil()) break;
      if (usedFamilies.contains(st.baseId)) continue;
      final base = problem(st.baseId);
      if (base != null && inMine(base)) add(base, 'review');
    }
    // 3) 약점 유형의 새 문항
    for (final (topic, _, _) in weakTopics) {
      if (ids.length >= (target * 0.9).ceil()) break;
      final cands = bank.all
          .where((p) => p.topic == topic && inMine(p) && !isSolved(p.id) && !usedFamilies.contains(p.id))
          .toList();
      if (cands.isNotEmpty) add(cands[_rand.nextInt(cands.length)], 'weak');
    }
    // 4) 내 과목의 새 문항 (과목을 고르게)
    final byCourse = <String, List<Problem>>{};
    for (final p in bank.all) {
      if (!inMine(p) || isSolved(p.id) || usedFamilies.contains(p.id) || p.passageId != null) continue;
      byCourse.putIfAbsent(p.subjectId, () => []).add(p);
    }
    for (final l in byCourse.values) {
      l.shuffle(_rand);
      l.sort((a, b) => a.difficulty.compareTo(b.difficulty));
    }
    final queues = byCourse.values.toList()..shuffle(_rand);
    var i = 0;
    while (ids.length < target && queues.any((q) => q.isNotEmpty)) {
      final q = queues[i % queues.length];
      if (q.isNotEmpty) add(q.removeAt(0), 'new');
      i++;
    }
    return DailySet(day: day, problemIds: ids, reasons: why);
  }

  /// 오늘의 세트에서 이 문제가 들어간 이유.
  String dailyReason(String problemId) => dailySet.reasons[problemId] ?? '';

  // ------------------------------------------------------------ 순공 타이머
  bool get studying => studyStartedAt != null;

  void startStudy() {
    if (studyStartedAt != null) return;
    studyStartedAt = _now;
    _changed();
  }

  void stopStudy() {
    final s = studyStartedAt;
    if (s == null) return;
    final ms = _now - s;
    if (ms >= 30 * 1000) sessions = [...sessions, StudySession(s, ms)];
    studyStartedAt = null;
    _changed();
    reportStudy();
  }

  int studyMsOn(String day) {
    var ms = 0;
    for (final x in sessions) {
      if (dayKey(DateTime.fromMillisecondsSinceEpoch(x.start)) == day) ms += x.ms;
    }
    final s = studyStartedAt;
    if (s != null && dayKey(DateTime.fromMillisecondsSinceEpoch(s)) == day) ms += _now - s;
    return ms;
  }

  int get todayStudyMs => studyMsOn(dayKey(DateTime.now()));

  /// Time spent solving problems on [day] (from attempts).
  int solveMsOn(String day) =>
      daily[day]?.timeMs ?? 0;

  // ------------------------------------------------------------ 할 일
  List<TodoItem> get todayTodos {
    final today = dayKey(DateTime.now());
    // unfinished items from earlier days carry over
    return todos.where((t) => t.day == today || (!t.done && t.day.compareTo(today) < 0)).toList();
  }

  void addTodo(String text) {
    if (text.trim().isEmpty) return;
    todos = [...todos, TodoItem(id: _newId(), text: text.trim(), day: dayKey(DateTime.now()))];
    _changed();
  }

  void toggleTodo(String id) {
    for (final t in todos) {
      if (t.id == id) t.done = !t.done;
    }
    _changed();
  }

  void removeTodo(String id) {
    todos = todos.where((t) => t.id != id).toList();
    _changed();
  }

  // ------------------------------------------------------------ 모의고사 성적
  List<ExamScore> get scoresByDate => [...scores]..sort((a, b) => a.date.compareTo(b.date));

  void saveScore(ExamScore s) {
    scores = [for (final x in scores) if (x.id != s.id) x, s];
    _changed();
  }

  void removeScore(String id) {
    scores = scores.where((x) => x.id != id).toList();
    _changed();
  }

  String newId() => _newId();

  // ------------------------------------------------------------ 커뮤니티 · 순위
  /// null when no server address is set.
  CommunityApi? get community =>
      settings.serverUrl.trim().isEmpty ? null : CommunityApi(settings.serverUrl, profile.id);

  /// Name shown on posts: the nickname, or the masked real name (오XX).
  String get communityName => learner.nickname.trim().isNotEmpty ? learner.nickname.trim() : maskName(profile.name);

  /// 오늘 공부시간 = 순공 타이머 + 앱에서 문제 푼 시간.
  int get todayTotalStudyMs => todayStudyMs + solveMsOn(dayKey(DateTime.now()));

  Timer? _reportTimer;

  /// Send today's study time to the ranking (masked name). Errors are ignored.
  Future<void> reportStudy({bool now = true}) async {
    final api = community;
    if (api == null || !learner.rankingOptIn) return;
    if (!now) {
      _reportTimer?.cancel();
      _reportTimer = Timer(const Duration(seconds: 8), () => reportStudy());
      return;
    }
    try {
      await api.reportStudy(
        name: profile.name,
        grade: learner.grade,
        day: dayKey(DateTime.now()),
        studyMs: todayTotalStudyMs,
        solved: todayCount,
      );
    } catch (e) {
      debugPrint('ranking report: $e');
    }
  }

  // ------------------------------------------------------------ content server
  Future<SyncResult> syncContent() async {
    if (syncing) return const SyncResult(false, 0, 0, '받는 중이에요');
    syncing = true;
    syncMessage = '문항을 받는 중…';
    notifyListeners();
    final sync = ContentSync(storage);
    final r = await sync.sync(settings.serverUrl);
    if (r.ok) {
      final (packs, wbs) = await sync.loadCached();
      _contentBank = _baseBank.withPacks(packs, workbooks: wbs);
      _rebuildBank();
    }
    syncing = false;
    syncMessage = r.message;
    _changed(save: false);
    return r;
  }

  // ------------------------------------------------------------ 무한 풀기
  /// Next problem for an endless session (adaptive difficulty).
  Problem? nextEndless(EndlessFeed f) {
    final mine = myCourseIds;
    final pool = bank.all.where((p) {
      if (f.courseId != null ? p.subjectId != f.courseId : !(mine.isEmpty || mine.contains(p.subjectId))) {
        return false;
      }
      if (f.unit != null && p.unit != f.unit) return false;
      if (f.topic != null && p.topic != f.topic) return false;
      return !f.seenFamilies.contains(p.familyId);
    }).toList();
    final target = f.level.round().clamp(1, 5);
    Problem? pick(List<Problem> l) {
      if (l.isEmpty) return null;
      l.shuffle(_rand);
      l.sort((a, b) => (a.difficulty - target).abs().compareTo((b.difficulty - target).abs()));
      final best = (l.first.difficulty - target).abs();
      final top = l.where((p) => (p.difficulty - target).abs() == best).toList();
      return top[_rand.nextInt(top.length)];
    }

    var p = pick(pool.where((p) => !isSolved(p.id)).toList()) ?? pick(pool);
    if (p == null) {
      // everything seen in this session: keep going with variants
      final again = bank.all.where((x) {
        if (f.courseId != null && x.subjectId != f.courseId) return false;
        if (f.unit != null && x.unit != f.unit) return false;
        if (f.topic != null && x.topic != f.topic) return false;
        return hasVariant(x);
      }).toList();
      if (again.isEmpty) return null;
      p = makeVariant(again[_rand.nextInt(again.length)]);
    }
    f.seenFamilies.add(p.familyId);
    return p;
  }

  // ------------------------------------------------------------ reset
  Future<void> resetRecords() async {
    attempts = [];
    states = {};
    _daily = null;
    await storage.deleteDir(_pp('ink'));
    await storage.deleteDir(_pp('drafts'));
    _changed();
  }

  // ------------------------------------------------------------ stats
  _Stats? _statsCache;
  _Stats get _stats => _statsCache ??= _Stats.compute(attempts, _now);

  int get revision => _revision;
  int get totalSolved => attempts.length;
  int get totalCorrect => _stats.correct;
  double get accuracy => attempts.isEmpty ? 0 : _stats.correct / attempts.length;
  int get streak => _stats.streak;
  int get todayCount => _stats.today.solved;
  int get todayCorrect => _stats.today.correct;
  Map<String, Tally> get daily => _stats.daily;
  Map<String, Tally> get bySubject => _stats.bySubject;
  Map<String, Tally> get byUnit => _stats.byUnit;
  Map<String, Tally> get byTopic => _stats.byTopic;
  Map<int, Tally> get byDifficulty {
    final m = <int, Tally>{};
    for (final a in attempts) {
      final d = problem(a.problemId)?.difficulty ?? 3;
      final t = m.putIfAbsent(d, Tally.new);
      t.solved++;
      if (a.correct) t.correct++;
      t.timeMs += a.timeMs;
    }
    return m;
  }

  int get avgTimeMs => attempts.isEmpty ? 0 : _stats.totalTime ~/ attempts.length;

  /// (topic, accuracy, solved) for topics that need work.
  List<(String, double, int)> get weakTopics {
    final l = <(String, double, int)>[];
    _stats.byTopic.forEach((k, v) {
      if (v.solved >= 2 && v.accuracy < 0.75) l.add((k, v.accuracy, v.solved));
    });
    l.sort((a, b) => a.$2.compareTo(b.$2));
    return l.take(6).toList();
  }

  Tally subjectTally(String subjectId) => _stats.bySubject[subjectId] ?? Tally();

  /// Fraction of a subject's base problems solved at least once.
  double coverage(Subject s) {
    if (s.problems.isEmpty) return 0;
    var n = 0;
    for (final p in s.problems) {
      if (isSolved(p.id)) n++;
    }
    return n / s.problems.length;
  }

  Attempt? get lastAttempt => attempts.isEmpty ? null : attempts.last;

  List<Attempt> attemptsFor(String baseId) => attempts.where((a) => a.baseId == baseId).toList();

  @override
  void dispose() {
    _saveTimer?.cancel();
    _reportTimer?.cancel();
    _live?.dispose();
    super.dispose();
  }
}

class _Stats {
  int correct = 0;
  int totalTime = 0;
  int streak = 0;
  Tally today = Tally();
  final Map<String, Tally> daily = {};
  final Map<String, Tally> bySubject = {};
  final Map<String, Tally> byUnit = {};
  final Map<String, Tally> byTopic = {};

  static _Stats compute(List<Attempt> attempts, int now) {
    final s = _Stats();
    for (final a in attempts) {
      if (a.correct) s.correct++;
      s.totalTime += a.timeMs;
      final dk = dayKey(DateTime.fromMillisecondsSinceEpoch(a.at));
      for (final t in [
        s.daily.putIfAbsent(dk, Tally.new),
        s.bySubject.putIfAbsent(a.subjectId, Tally.new),
        s.byUnit.putIfAbsent('${a.subjectId}|${a.unit}', Tally.new),
        if (a.topic.isNotEmpty) s.byTopic.putIfAbsent(a.topic, Tally.new),
      ]) {
        t.solved++;
        if (a.correct) t.correct++;
        t.timeMs += a.timeMs;
      }
    }
    final todayDate = DateTime.fromMillisecondsSinceEpoch(now);
    s.today = s.daily[dayKey(todayDate)] ?? Tally();
    var d = todayDate;
    if (!s.daily.containsKey(dayKey(d))) d = d.subtract(const Duration(days: 1));
    while (s.daily.containsKey(dayKey(d))) {
      s.streak++;
      d = d.subtract(const Duration(days: 1));
    }
    return s;
  }
}

/// Gives widgets access to [AppState].
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope missing');
    return s!.notifier!;
  }

  static AppState read(BuildContext context) {
    final s = context.getInheritedWidgetOfExactType<AppScope>();
    return s!.notifier!;
  }
}

/// State of one 무한 풀기 session: what to draw from and how hard.
class EndlessFeed {
  EndlessFeed({this.courseId, this.unit, this.topic, this.level = 2.5});
  final String? courseId;
  final String? unit;
  final String? topic;
  double level;
  final Set<String> seenFamilies = {};

  /// Adapt: right answers push difficulty up, wrong ones down.
  void report(bool correct) {
    level = (level + (correct ? 0.5 : -0.7)).clamp(1.0, 5.0);
  }

  String get title => topic ?? unit ?? '무한 풀기';
}
