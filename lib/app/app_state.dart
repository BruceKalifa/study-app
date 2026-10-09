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
import '../services/account_api.dart';
import '../services/community_api.dart';
import '../services/content_import.dart';
import '../services/content_sync.dart';
import '../services/live_sync.dart';
import 'goals.dart';
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
  AppState({required this.storage, required ProblemBank baseBank, this.enableLive = true, this.autoSyncBooks = true})
      : _baseBank = baseBank,
        _contentBank = baseBank,
        bank = baseBank;

  final Storage storage;

  /// 로그인한 뒤·앱을 켤 때 교재를 저절로 주고받는다 (테스트에서는 끈다).
  final bool autoSyncBooks;
  final ProblemBank _baseBank;

  /// Bundled content + packs downloaded from the content server + imported 교재 files.
  ProblemBank _contentBank;
  List<Subject> _packs = const [];
  List<Workbook>? _packWorkbooks;
  List<BookBundle> _books = const [];

  /// 교재 파일로 넣은 교재 (설정 → 교재 파일).
  List<ImportedBook> importedBooks = [];
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

  // accounts (학생 / 선생님)
  /// The user chose "로그인 없이 쓰기" on the welcome screen.
  bool offlineMode = false;

  /// Server address last used on the welcome screen.
  String lastServer = '';

  /// Latest /api/me (counts for badges, linked teachers, invite code).
  MeInfo? me;

  /// Attempts already sent to the server (attempts only grow; reset → 0).
  int _syncedUpTo = 0;
  bool _recordsSyncing = false;
  Timer? _recordsTimer;
  Timer? _meTimer;
  String lastRecordsSync = '';

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
        offlineMode = j['offline'] == true;
        lastServer = (j['server'] as String?) ?? '';
      } catch (e) {
        debugPrint('profiles.json broken: $e');
      }
    }
    final fresh = profiles.isEmpty;
    if (fresh) {
      profiles = [Profile(id: _newId(), name: '학생', color: 0xFF2F6BFF, createdAt: _now)];
    }
    profile = profiles.firstWhere((p) => p.id == currentId, orElse: () => profiles.first);
    // the first profile must be on disk right away, or a restart would start a new one (and lose the records)
    if (fresh) await _saveProfiles();
    final (packs, wbs) = await ContentSync(storage).loadCached();
    _packs = packs;
    _packWorkbooks = wbs;
    final imports = ContentImport(storage);
    importedBooks = await imports.list();
    _books = await imports.loadAll();
    _composeContent();
    await _loadProfileData();
    ready = true;
    notifyListeners();
    // 교재는 서버가 본이다 — 켤 때마다 조용히 받아 온다 (못 받으면 지난번에 받아 둔 것으로 쓴다)
    syncContentSoon();
    _afterSignIn(restore: false);
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
    _syncedUpTo = 0;
    me = null;
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
        _syncedUpTo = (j['synced'] as num?)?.toInt() ?? 0;
      } catch (e) {
        debugPrint('state.json broken: $e');
      }
    }
    _rebuildBank();
    _configureLive();
    _revision++;
  }

  void _composeContent() {
    _contentBank = ContentImport.merge(_baseBank.withPacks(_packs, workbooks: _packWorkbooks), _books);
  }

  /// Adds a `.pulinote` 교재 file (one book or a collection); a student also gets the 문제집 on the shelf.
  /// Throws [FormatException].
  Future<List<BookBundle>> importBooks(List<int> bytes, {String sha = ''}) async {
    final imports = ContentImport(storage);
    final added = await imports.add(bytes, sha: sha);
    importedBooks = await imports.list();
    _books = await imports.loadAll();
    _composeContent();
    _rebuildBank();
    if (!isTeacher) {
      for (final w in added.expand((b) => b.workbooks)) {
        if (!hasWorkbook(w.id)) addWorkbook(w.id);
      }
    }
    _changed();
    return added;
  }

  Future<BookBundle> importBook(List<int> bytes) async => (await importBooks(bytes)).first;

  // ── 교재 받기 (server/books.js) ──
  //
  // 앱은 교재를 올리지 않는다. 교재는 서버의 교재 창고(웹 /books/)에 올리고,
  // 앱은 거기 있는 것을 받기만 한다. 선생님 태블릿도 똑같이 받기만 한다.
  bool bookSyncing = false;

  /// 마지막 교재 받기 결과 (설정 화면에 보여 준다).
  String bookSyncMessage = '';

  Future<String> _bookChain = Future.value('');

  /// 서버에 있는 교재 중 이 기기에 없거나 바뀐 것을 받는다.
  /// 로그인한 뒤·앱을 켤 때 저절로 돈다. 실패해도 앱은 그냥 쓰던 대로 쓴다.
  /// 여러 번 불러도 하나씩 차례로 돌고, 부른 쪽은 자기 차례의 결과를 받는다.
  Future<String> syncBooks() {
    if (account == null) return Future.value('');
    final next = _bookChain.then((_) => _runBookSync());
    _bookChain = next.catchError((Object _) => '');
    return next;
  }

  Future<String> _runBookSync() async {
    final a = account;
    if (a == null) return '';
    bookSyncing = true;
    bookSyncMessage = '교재를 받는 중…';
    _changed(save: false);
    var msg = '';
    try {
      final api = AccountApi.of(a);
      var got = 0;
      for (final r in await api.books()) {
        final have = {for (final b in importedBooks) b.id: b.sha};
        // 다 있고 서버 파일도 그대로면 건너뛴다 (교재를 다시 올리면 지문이 바뀌어 다시 받는다)
        final same = r.bookIds.isNotEmpty &&
            r.bookIds.every((id) => have.containsKey(id) && (r.sha.isEmpty || have[id] == r.sha));
        if (same) continue;
        got += (await importBooks(await api.bookBytes(r.id), sha: r.sha)).length;
      }
      if (got > 0) msg = '교재 $got권을 받았어요';
    } on ApiError catch (e) {
      msg = e.message;
      debugPrint('book sync: ${e.message}');
    } catch (e) {
      msg = '교재를 받지 못했어요';
      debugPrint('book sync: $e');
    }
    bookSyncing = false;
    bookSyncMessage = msg;
    _changed(save: false);
    return msg;
  }

  /// 로그인 직후·앱 시작 때 (결과를 기다리지 않는다).
  void syncBooksSoon() {
    if (!autoSyncBooks || account == null) return;
    unawaited(syncBooks());
  }

  /// 이 문제집이 들어 있는 교재 파일의 id (교재 파일로 넣은 것이 아니면 null).
  String? bookIdOfWorkbook(String workbookId) {
    for (final b in _books) {
      if (b.workbooks.any((w) => w.id == workbookId)) return b.id;
    }
    return null;
  }

  /// 답안표 고치기 — 기기에 저장한 교재의 정답을 바꾸고, 선생님이면 서버에도 다시 올린다.
  Future<int> updateAnswers(String bookId, Map<String, String> answers) async {
    final imports = ContentImport(storage);
    final n = await imports.setAnswers(bookId, answers);
    if (n == 0) return 0;
    _books = await imports.loadAll();
    _composeContent();
    _rebuildBank();
    _changed();
    // 선생님이 고친 정답은 그 교재만 서버에 다시 올린다 (학생 기기에서 지문이 달라져 다시 받아진다)
    if (isTeacher) unawaited(_pushAnswers(bookId));
    return n;
  }

  /// 답안표에서 고친 정답을 그 교재 하나만 서버에 다시 올린다.
  /// 서버 창고에 없던 교재는 올리지 않는다 — 교재를 올리는 곳은 웹 교재 창고다.
  Future<void> _pushAnswers(String bookId) async {
    final a = account;
    if (a == null || !isTeacher) return;
    try {
      final api = AccountApi.of(a);
      final on = (await api.books()).where((r) => r.mine && r.bookIds.contains(bookId));
      if (on.isEmpty) return;
      final imports = ContentImport(storage);
      final file = await imports.fileFor([bookId]);
      if (file == null) return;
      final up = await api.uploadBook(file);
      await imports.markSha([bookId], up.sha);
      importedBooks = await imports.list();
      bookSyncMessage = '고친 정답을 서버에 올렸어요';
      _changed(save: false);
    } catch (e) {
      debugPrint('answer push: $e');
    }
  }

  Future<void> removeImportedBook(String id) async {
    final imports = ContentImport(storage);
    final gone = _books.where((b) => b.id == id).expand((b) => b.workbooks).map((w) => w.id).toSet();
    await imports.remove(id);
    importedBooks = await imports.list();
    _books = await imports.loadAll();
    _composeContent();
    _rebuildBank();
    for (final w in gone) {
      if (hasWorkbook(w)) removeWorkbook(w);
    }
    _changed();
  }

  void _rebuildBank() {
    bank = customProblems.isEmpty ? _contentBank : _contentBank.withExtra(customProblems);
  }

  /// Called when the app comes back to the foreground.
  void onResumed() {
    _live?.reconnect();
    reportStudy();
    if (account != null) {
      refreshMe();
      syncRecords();
      syncBooksSoon(); // 선생님이 새 교재를 올렸을 수 있다
    }
  }

  void _configureLive() {
    if (!enableLive) return;
    final l = _live ??= LiveSync(studentId: profile.id, name: profile.name);
    l.configure(enabled: settings.liveEnabled, url: serverAddress, name: profile.name, studentId: profile.id);
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
      'synced': _syncedUpTo,
    });
    await storage.write(_pp('state.json'), data);
  }

  Future<void> _saveProfiles() => storage.write(
        'profiles.json',
        jsonEncode({
          'current': profile.id,
          'list': [for (final p in profiles) p.toJson()],
          'offline': offlineMode,
          'server': lastServer,
        }),
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
    _scheduleRecordsSync();
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
    _scheduleRecordsSync();
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
  List<Subject> coursesForGrade(String grade) => coursesForGrades([grade]);

  /// 여러 학년·과정을 함께 고른 경우: 하나라도 겹치는 과목이 보인다.
  List<Subject> coursesForGrades(List<String> grades) => [
        for (final s in bank.subjects)
          if (s.id != ProblemBank.customSubjectId && (s.grades.isEmpty || s.grades.any(grades.contains))) s
      ];

  /// 내 교재: the workbooks the student put on the shelf (in the order they were added).
  /// Problems come only from these books (plus 오답 변형 of problems the student got wrong).
  List<Workbook> get myWorkbooks => [
        for (final id in learner.workbooks)
          if (bank.workbook(id) case final w?) w
      ];

  bool hasWorkbook(String id) => learner.workbooks.contains(id);

  /// Courses of 내 교재 (a series book may span several courses).
  List<Subject> get myCourses {
    final ids = <String>{for (final w in myWorkbooks) ...bank.coursesOf(w)};
    return [
      for (final s in bank.subjects)
        if (ids.contains(s.id)) s
    ];
  }

  Set<String> get myCourseIds => {for (final s in myCourses) s.id};

  /// Every problem in 내 교재, book by book in book order (no duplicates).
  List<Problem> get myProblems {
    final seen = <String>{};
    return [
      for (final w in myWorkbooks)
        for (final p in bank.problemsOf(w))
          if (seen.add(p.id)) p
    ];
  }

  Set<String> get _myProblemIds => {for (final p in myProblems) p.id};

  /// Put a book on the shelf (내 교재에 담기).
  void addWorkbook(String id) {
    if (learner.workbooks.contains(id) || bank.workbook(id) == null) return;
    learner.workbooks = [...learner.workbooks, id];
    _refreshDailyIfUntouched();
    _changed();
    _scheduleRecordsSync();
  }

  void removeWorkbook(String id) {
    if (!learner.workbooks.contains(id)) return;
    learner.workbooks = learner.workbooks.where((w) => w != id).toList();
    _refreshDailyIfUntouched();
    _changed();
    _scheduleRecordsSync();
  }

  /// A new shelf changes today's set unless the student already started it.
  void _refreshDailyIfUntouched() {
    final d = _daily;
    if (d == null || d.done.isEmpty) _daily = null;
  }

  /// Books in the catalog for a course (a series counts for every course it covers).
  List<Workbook> workbooksForCourse(String courseId) =>
      bank.workbooks.where((w) => bank.coursesOf(w).contains(courseId)).toList();

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
    List<String>? grades,
    String goal = '',
    List<String>? goals,
    required List<String> courses,
    required List<String> workbooks,
  }) {
    if (name.trim().isNotEmpty && name.trim() != profile.name) {
      profile.name = name.trim();
      _saveProfiles();
    }
    learner.setGrades(grades != null && grades.isNotEmpty ? grades : [grade]);
    learner.setGoals(goals != null && goals.isNotEmpty ? goals : parseGoals(goal));
    if (learner.goal.isEmpty) learner.goal = '수능';
    learner
      ..courses = courses
      ..workbooks = [for (final w in workbooks) if (bank.workbook(w) != null) w]
      ..onboarded = true;
    if (learner.examDate == 0) {
      // 고른 목표 중 처음으로 시험이 있는 것을 D-day 카드에 올린다. 날짜는 수능만 미리 채운다 (나머지는 직접 정함).
      GoalOption? first;
      for (final g in learner.goals) {
        final o = goalOption(g);
        if (o != null && o.exam.isNotEmpty) {
          first = o;
          break;
        }
      }
      if (first != null) {
        learner.examName = first.exam;
        if (first.suneung) learner.examDate = defaultSuneungDate(DateTime.now()).millisecondsSinceEpoch;
      } else {
        learner.examName = '시험';
      }
    }
    _daily = null; // rebuild today's set for the new books
    _configureLive();
    _changed();
    _scheduleRecordsSync();
  }

  void updateLearner(void Function(Learner l) fn) {
    fn(learner);
    _changed();
    _scheduleRecordsSync();
  }

  // ------------------------------------------------------------ D-day
  int get dDay {
    if (learner.examDate == 0) return 0;
    final t = DateTime.fromMillisecondsSinceEpoch(learner.examDate);
    final n = DateTime.now();
    return DateTime(t.year, t.month, t.day).difference(DateTime(n.year, n.month, n.day)).inDays;
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
    final books = myWorkbooks;
    final mineIds = _myProblemIds;
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
      if (base == null) continue;
      final twins = bank.twinsOf(base.id).where((t) => !_attempted(t.id)).toList()..shuffle(_rand);
      if (twins.isNotEmpty) {
        add(twins.first, 'twin');
      } else if (base.hasTemplate) {
        add(makeVariant(base), 'variant');
      } else {
        final similar = bank.all
            .where((p) =>
                mineIds.contains(p.id) &&
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
      if (base != null) add(base, 'review');
    }
    // 3) 약점 유형 — 내 교재에서 아직 안 푼 같은 유형
    for (final (topic, _, _) in weakTopics) {
      if (ids.length >= (target * 0.9).ceil()) break;
      final cands = [
        for (final p in myProblems)
          if (p.topic == topic && !isSolved(p.id) && !usedFamilies.contains(p.id)) p
      ];
      if (cands.isNotEmpty) add(cands[_rand.nextInt(cands.length)], 'weak');
    }
    // 4) 오늘의 진도 — 내 교재마다 안 푼 문제를 책 순서대로 (책을 번갈아)
    final queues = [
      for (final w in books)
        [
          for (final p in bank.problemsOf(w))
            if (!isSolved(p.id) && !usedFamilies.contains(p.id) && p.passageId == null) p
        ]
    ].where((q) => q.isNotEmpty).toList();
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
  CommunityApi? get community {
    final a = account;
    if (a != null && a.server.trim().isNotEmpty) {
      return CommunityApi(a.server, a.communityKey.isNotEmpty ? a.communityKey : profile.id);
    }
    return settings.serverUrl.trim().isEmpty ? null : CommunityApi(settings.serverUrl, profile.id);
  }

  /// Name shown on posts: the nickname, or the masked real name (오XX).
  String get communityName => learner.nickname.trim().isNotEmpty ? learner.nickname.trim() : maskName(profile.name);

  /// 글·댓글 옆에 보이는 신분 — 가입할 때 고른 과정 ("고3", "한양대생 · N수생"). 선생님은 "선생님".
  String get communityIdentity => isTeacher ? '선생님' : identityLabel(learner.grades);

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
  /// 앱을 켤 때·로그인한 뒤 조용히 받아 온다 (결과를 기다리지 않는다).
  void syncContentSoon() {
    if (!autoSyncBooks || syncing) return;
    unawaited(syncContent());
  }

  Future<SyncResult> syncContent() async {
    if (syncing) return const SyncResult(false, 0, 0, '받는 중이에요');
    syncing = true;
    syncMessage = '문항을 받는 중…';
    notifyListeners();
    final sync = ContentSync(storage);
    final r = await sync.sync(serverAddress);
    if (r.ok) {
      final (packs, wbs) = await sync.loadCached();
      _packs = packs;
      _packWorkbooks = wbs;
      _composeContent();
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
    final source = f.workbookId != null
        ? (bank.workbook(f.workbookId!) == null ? const <Problem>[] : bank.problemsOf(bank.workbook(f.workbookId!)!))
        : myProblems;
    final pool = source.where((p) {
      if (f.courseId != null && p.subjectId != f.courseId) return false;
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
      final again = source.where((x) {
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

  // ------------------------------------------------------------ 계정 (학생 / 선생님)
  Account? get account => profile.account;

  /// 앱이 쓰는 서버 주소. 보통 [kDefaultServer] 이고, 설정에 직접 넣은 주소가 있으면 그것(개발·테스트용).
  String get serverAddress {
    final set = settings.serverUrl.trim();
    if (set.isNotEmpty) return set;
    final last = lastServer.trim();
    return last.isNotEmpty ? last : kDefaultServer;
  }
  bool get signedIn => account != null;
  bool get isTeacher => account?.isTeacher == true;

  /// First screen: sign in, sign up, or use the app without an account.
  bool get needsWelcome => account == null && !offlineMode;

  AccountApi? get api {
    final a = account;
    return a == null ? null : AccountApi.of(a);
  }

  Future<void> login({required String server, required String loginId, required String password}) async {
    final (token, info) = await AccountApi(server).login(loginId.trim(), password);
    await _signIn(server: server, token: token, info: info);
  }

  Future<void> signup({
    required String server,
    required String role,
    required String loginId,
    required String password,
    required String name,
    String grade = '',
    List<String> grades = const <String>[],
    String teacherCode = '',
  }) async {
    final (token, info) = await AccountApi(server).signup(
        role: role,
        loginId: loginId.trim(),
        password: password,
        name: name.trim(),
        grade: grade,
        grades: grades,
        teacherCode: teacherCode);
    await _signIn(server: server, token: token, info: info, fresh: true, grade: grade, grades: grades);
  }

  Future<void> _signIn({
    required String server,
    required String token,
    required MeInfo info,
    bool fresh = false,
    String grade = '',
    List<String> grades = const <String>[],
  }) async {
    final acc = Account(
      server: server.trim(),
      token: token,
      userId: info.userId,
      loginId: info.loginId,
      role: info.role,
      name: info.name,
      grade: info.grade,
      grades: info.grades,
      communityKey: info.communityKey,
    );
    if (ready) await saveNow();
    final pid = Profile.idForAccount(info.userId);
    var p = profiles.where((x) => x.id == pid).firstOrNull;
    if (p == null) {
      const colors = [0xFF2F6BFF, 0xFFFF6B4A, 0xFF169C6B, 0xFF8B5CF6, 0xFFE8A317, 0xFF0EA5E9, 0xFFEC4899];
      p = Profile(id: pid, name: info.name, color: colors[profiles.length % colors.length], createdAt: _now);
      profiles = [...profiles, p];
    }
    p
      ..account = acc
      ..name = info.name;
    profile = p;
    lastServer = acc.server;
    offlineMode = false;
    await _loadProfileData();
    // the account's server is also where problems, community and live view live
    if (settings.serverUrl.trim().isEmpty) settings.serverUrl = acc.server;
    if (fresh && !acc.isTeacher) {
      final gs = grades.isNotEmpty ? grades : (grade.isNotEmpty ? [grade] : const <String>[]);
      if (gs.isNotEmpty) learner.setGrades(gs);
    }
    me = info;
    await _saveProfiles();
    await saveNow();
    notifyListeners();
    await _afterSignIn(restore: !fresh);
  }

  /// Restore records on a new tablet, then keep syncing.
  Future<void> _afterSignIn({required bool restore}) async {
    final a = account;
    _meTimer?.cancel();
    if (a == null) return;
    _meTimer = Timer.periodic(const Duration(seconds: 90), (_) => refreshMe());
    // 서버 교재 창고에 있는 교재를 받아 온다 — 주소를 묻지 않고 저절로
    syncBooksSoon();
    syncContentSoon();
    if (a.isTeacher) return;
    if (restore && attempts.isEmpty) {
      try {
        final r = await AccountApi.of(a).records();
        if (r.attempts.isNotEmpty) {
          seedAttempts(r.attempts);
          final wn = r.wrongNote;
          if (wn != null) {
            final keep = wn.toSet();
            for (final s in states.values) {
              if (s.inWrongNote && !keep.contains(s.baseId)) {
                s.inWrongNote = false;
                s.resolvedAt ??= s.lastAt;
              }
            }
          }
        }
        _syncedUpTo = attempts.length;
        final l = r.learner;
        if (l != null && l.isNotEmpty) learner = Learner.fromJson(l);
        _daily = null;
        _changed();
      } catch (e) {
        debugPrint('restore: $e');
      }
    }
    await syncRecords();
  }

  Future<void> logout() async {
    final a = account;
    if (a == null) return;
    await syncRecords();
    try {
      await AccountApi.of(a).logout();
    } catch (_) {}
    await saveNow();
    _meTimer?.cancel();
    _recordsTimer?.cancel();
    profile.account = null;
    me = null;
    offlineMode = false;
    await _saveProfiles();
    notifyListeners();
  }

  /// "로그인 없이 쓰기": keep records on this tablet only.
  Future<void> useOffline() async {
    offlineMode = true;
    if (profile.isAccountProfile || profile.account != null) {
      final local = profiles.where((p) => !p.isAccountProfile && p.account == null).firstOrNull;
      if (local != null) {
        profile = local;
      } else {
        final p = Profile(id: _newId(), name: '학생', color: 0xFF2F6BFF, createdAt: _now);
        profiles = [...profiles, p];
        profile = p;
      }
      await _loadProfileData();
    }
    await _saveProfiles();
    notifyListeners();
  }

  /// Back to the welcome screen from the offline mode (to sign in).
  Future<void> showWelcome() async {
    offlineMode = false;
    await _saveProfiles();
    notifyListeners();
  }

  /// Account details changed on the server (name, grade, teachers, counts).
  Future<void> refreshMe() async {
    final a = account;
    if (a == null) return;
    try {
      final info = await AccountApi.of(a).me();
      me = info;
      if (info.name != a.name) {
        a.name = info.name;
        profile.name = info.name;
        await _saveProfiles();
      }
      notifyListeners();
    } on ApiError catch (e) {
      if (e.unauthorized) {
        // 비밀번호를 바꾸는 등으로 로그인이 끊김 → 다시 로그인
        profile.account = null;
        me = null;
        await _saveProfiles();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<PersonRef> joinTeacher(String code) async {
    final t = await api!.joinTeacher(code);
    await refreshMe();
    return t;
  }

  Future<void> leaveTeacher(String teacherId) async {
    await api!.leaveTeacher(teacherId);
    await refreshMe();
  }

  List<PersonRef> get myTeachers => me?.teachers ?? const [];
  int get unreadAnswers => me?.unreadQuestions ?? 0;
  int get openQuestions => me?.openQuestions ?? 0;

  void _scheduleRecordsSync() {
    if (account == null || isTeacher) return;
    _recordsTimer?.cancel();
    _recordsTimer = Timer(const Duration(seconds: 4), syncRecords);
  }

  /// Send new attempts, 학습 설정 and the 오답노트 to the server (teacher view, other tablets).
  Future<bool> syncRecords() async {
    final a = account;
    if (a == null || a.isTeacher || _recordsSyncing) return false;
    _recordsSyncing = true;
    _recordsTimer?.cancel();
    try {
      final api = AccountApi.of(a);
      if (_syncedUpTo > attempts.length) _syncedUpTo = 0;
      final wrong = [for (final s in states.values) if (s.inWrongNote) s.baseId];
      var sent = false;
      while (_syncedUpTo < attempts.length || !sent) {
        final end = math.min(attempts.length, _syncedUpTo + 1000);
        await api.sync(
          attempts: attempts.sublist(_syncedUpTo, end),
          learner: sent ? null : learner.toJson(),
          wrongNote: sent ? null : wrong,
        );
        _syncedUpTo = end;
        sent = true;
      }
      lastRecordsSync = '방금 저장됨';
      _scheduleSave();
      return true;
    } on ApiError catch (e) {
      lastRecordsSync = e.message;
      if (e.unauthorized) await refreshMe();
      return false;
    } catch (e) {
      lastRecordsSync = '$e';
      return false;
    } finally {
      _recordsSyncing = false;
    }
  }

  int get unsyncedCount => math.max(0, attempts.length - _syncedUpTo);

  // ------------------------------------------------------------ reset
  Future<void> resetRecords() async {
    attempts = [];
    states = {};
    _daily = null;
    _syncedUpTo = 0;
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
    _recordsTimer?.cancel();
    _meTimer?.cancel();
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
  EndlessFeed({this.courseId, this.unit, this.topic, this.workbookId, this.level = 2.5});

  /// Problems come from 내 교재 (or only this book).
  final String? workbookId;
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
