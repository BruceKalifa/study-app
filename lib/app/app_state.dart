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
import '../services/live_sync.dart';
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
        bank = baseBank;

  final Storage storage;
  final ProblemBank _baseBank;
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
    await _loadProfileData();
    ready = true;
    notifyListeners();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;
  String _newId() => '${_now.toRadixString(36)}${_rand.nextInt(1 << 30).toRadixString(36)}';
  String _pp(String f) => 'profiles/${profile.id}/$f';

  Future<void> _loadProfileData() async {
    settings = AppSettings();
    ink = InkSettings();
    attempts = [];
    states = {};
    customProblems = [];
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
      } catch (e) {
        debugPrint('state.json broken: $e');
      }
    }
    _rebuildBank();
    _configureLive();
    _revision++;
  }

  void _rebuildBank() {
    bank = customProblems.isEmpty ? _baseBank : _baseBank.withExtra(customProblems);
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

  String baseIdOf(Problem p) => p.variantOf ?? p.id;

  ProblemState stateOf(String baseId) => states[baseId] ?? ProblemState(baseId);

  bool isSolved(String baseId) => (states[baseId]?.attempts ?? 0) > 0;

  Problem makeVariant(Problem base) {
    final b = base.isVariant ? (problem(base.variantOf!) ?? base) : base;
    if (!b.hasTemplate) return b;
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
    if (hasInk) {
      await storage.write(_pp('ink/$id.json'), jsonEncode(inkDoc.toJson()));
    }
    _changed();
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

  Future<InkDocument?> loadDraft(String problemId) async {
    final raw = await storage.read(_draftKey(problemId));
    if (raw == null) return null;
    try {
      return InkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(String problemId, InkDocument doc) async {
    if (doc.isEmpty) {
      await storage.delete(_draftKey(problemId));
    } else {
      await storage.write(_draftKey(problemId), jsonEncode(doc.toJson()));
    }
  }

  Future<void> deleteDraft(String problemId) => storage.delete(_draftKey(problemId));

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

  // ------------------------------------------------------------ reset
  Future<void> resetRecords() async {
    attempts = [];
    states = {};
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
