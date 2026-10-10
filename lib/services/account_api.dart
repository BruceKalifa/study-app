import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../app/records.dart';
import 'content_sync.dart';

/// Error with a message that can be shown as-is (Korean, from the server or the network layer).
/// 가입 추천코드 확인 결과.
class SignupCodeInfo {
  final String label; // 한양대생 · 고등학생 · N수생 …
  final List<String> grades; // 이 코드로 고를 수 있는 학년·과정
  const SignupCodeInfo({required this.label, required this.grades});
}

class ApiError implements Exception {
  final String message;
  final int status;
  const ApiError(this.message, [this.status = 0]);
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

int _i(Object? v) => v is num ? v.toInt() : 0;
int? _oi(Object? v) => v is num ? v.toInt() : null;
String _s(Object? v) => v == null ? '' : '$v';
Map<String, dynamic> _m(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _lm(Object? v) => v is List ? [for (final e in v) _m(e)] : const [];

/// The signed-in account stored with a profile (token included).
class Account {
  final String server;
  final String token;
  final String userId;
  final String loginId;
  final String role; // student | teacher
  String name;
  String grade;

  /// 고른 학년·과정 전부 (복수). [grade] 는 그중 대표.
  List<String> grades;
  final String communityKey;

  Account({
    required this.server,
    required this.token,
    required this.userId,
    required this.loginId,
    required this.role,
    required this.name,
    this.grade = '',
    this.grades = const <String>[],
    this.communityKey = '',
  });

  bool get isTeacher => role == 'teacher';
  String get roleLabel => isTeacher ? '선생님' : '학생';

  Map<String, dynamic> toJson() => {
        'server': server,
        'token': token,
        'userId': userId,
        'loginId': loginId,
        'role': role,
        'name': name,
        'grade': grade,
        'grades': grades,
        'ck': communityKey,
      };

  static Account? fromJson(Object? o) {
    final j = _m(o);
    if (_s(j['token']).isEmpty || _s(j['userId']).isEmpty) return null;
    return Account(
      server: _s(j['server']),
      token: _s(j['token']),
      userId: _s(j['userId']),
      loginId: _s(j['loginId']),
      role: _s(j['role']) == 'teacher' ? 'teacher' : 'student',
      name: _s(j['name']),
      grade: _s(j['grade']),
      grades: [if (j['grades'] is List) for (final x in j['grades'] as List) '$x'],
      communityKey: _s(j['ck']),
    );
  }
}

class PersonRef {
  final String id, name, grade;
  const PersonRef(this.id, this.name, [this.grade = '']);
  factory PersonRef.fromJson(Object? o) {
    final j = _m(o);
    return PersonRef(_s(j['id']), _s(j['name']), _s(j['grade']));
  }
}

/// GET /api/me
class MeInfo {
  final String userId, loginId, role, name, grade, communityKey;
  final List<String> grades;
  final String? inviteCode;
  final int studentCount;
  final List<PersonRef> teachers;
  final int unreadQuestions, openQuestions;

  const MeInfo({
    required this.userId,
    required this.loginId,
    required this.role,
    required this.name,
    required this.grade,
    this.grades = const <String>[],
    required this.communityKey,
    this.inviteCode,
    this.studentCount = 0,
    this.teachers = const [],
    this.unreadQuestions = 0,
    this.openQuestions = 0,
  });

  factory MeInfo.fromJson(Map<String, dynamic> j) {
    final u = _m(j['user']);
    final c = _m(j['counts']);
    return MeInfo(
      userId: _s(u['id']),
      loginId: _s(u['loginId']),
      role: _s(u['role']) == 'teacher' ? 'teacher' : 'student',
      name: _s(u['name']),
      grade: _s(u['grade']),
      grades: [if (u['grades'] is List) for (final x in u['grades'] as List) '$x'],
      communityKey: _s(j['communityKey']),
      inviteCode: j['inviteCode'] as String?,
      studentCount: _i(j['studentCount']),
      teachers: [for (final t in _lm(j['teachers'])) PersonRef.fromJson(t)],
      unreadQuestions: _i(c['unreadQuestions']),
      openQuestions: _i(c['openQuestions']),
    );
  }
}

class Tally3 {
  final int solved, correct, timeMs;
  const Tally3(this.solved, this.correct, this.timeMs);
  factory Tally3.fromJson(Object? o) {
    final j = _m(o);
    return Tally3(_i(j['solved']), _i(j['correct']), _i(j['timeMs']));
  }
  double get accuracy => solved == 0 ? 0 : correct / solved;
}

class StudentSummary {
  final String id, name, grade;
  final int? joinedAt, syncedAt, lastActiveAt;
  final int solved, correct, wrongOpen;
  final Tally3 today, week;

  const StudentSummary({
    required this.id,
    required this.name,
    required this.grade,
    this.joinedAt,
    this.syncedAt,
    this.lastActiveAt,
    required this.solved,
    required this.correct,
    required this.wrongOpen,
    required this.today,
    required this.week,
  });

  double get accuracy => solved == 0 ? 0 : correct / solved;

  factory StudentSummary.fromJson(Object? o) {
    final j = _m(o);
    return StudentSummary(
      id: _s(j['id']),
      name: _s(j['name']),
      grade: _s(j['grade']),
      joinedAt: _oi(j['joinedAt']),
      syncedAt: _oi(j['syncedAt']),
      lastActiveAt: _oi(j['lastActiveAt']),
      solved: _i(j['solved']),
      correct: _i(j['correct']),
      wrongOpen: _i(j['wrongOpen']),
      today: Tally3.fromJson(j['today']),
      week: Tally3.fromJson(j['week']),
    );
  }
}

class WrongItem {
  final String baseId, problemId, subjectId, unit, topic, answer, expected;
  final int wrongAt, lastAt, tries, correct, wrongs;
  final bool lastCorrect, open;

  const WrongItem({
    required this.baseId,
    required this.problemId,
    required this.subjectId,
    required this.unit,
    required this.topic,
    required this.answer,
    required this.expected,
    required this.wrongAt,
    required this.lastAt,
    required this.tries,
    required this.correct,
    required this.wrongs,
    required this.lastCorrect,
    required this.open,
  });

  factory WrongItem.fromJson(Object? o) {
    final j = _m(o);
    return WrongItem(
      baseId: _s(j['baseId']),
      problemId: _s(j['problemId']),
      subjectId: _s(j['subjectId']),
      unit: _s(j['unit']),
      topic: _s(j['topic']),
      answer: _s(j['answer']),
      expected: _s(j['expected']),
      wrongAt: _i(j['wrongAt']),
      lastAt: _i(j['lastAt']),
      tries: _i(j['tries']),
      correct: _i(j['correct']),
      wrongs: _i(j['wrongs']),
      lastCorrect: j['lastCorrect'] == true,
      open: j['open'] == true,
    );
  }
}

class DayTally {
  final String day;
  final Tally3 t;
  const DayTally(this.day, this.t);
}

class StudentDetail {
  final StudentSummary student;
  final String grade, goal, examName;
  final int examDate;
  final List<String> workbooks;
  final List<WrongItem> wrong;
  final Map<String, Tally3> bySubject;
  final List<DayTally> byDay;
  final List<Attempt> recent;

  const StudentDetail({
    required this.student,
    required this.grade,
    required this.goal,
    required this.examName,
    required this.examDate,
    required this.workbooks,
    required this.wrong,
    required this.bySubject,
    required this.byDay,
    required this.recent,
  });

  factory StudentDetail.fromJson(Map<String, dynamic> j) {
    final l = _m(j['learner']);
    return StudentDetail(
      student: StudentSummary.fromJson(j['student']),
      grade: _s(l['grade']),
      goal: _s(l['goal']),
      examName: _s(l['examName']),
      examDate: _i(l['examDate']),
      workbooks: l['workbooks'] is List ? [for (final w in l['workbooks'] as List) '$w'] : const [],
      wrong: [for (final w in _lm(j['wrong'])) WrongItem.fromJson(w)],
      bySubject: {for (final t in _lm(j['bySubject'])) _s(t['subjectId']): Tally3.fromJson(t)},
      byDay: [for (final t in _lm(j['byDay'])) DayTally(_s(t['day']), Tally3.fromJson(t))],
      recent: [
        for (final a in _lm(j['recent']))
          if (_s(a['id']).isNotEmpty && _s(a['pid']).isNotEmpty) Attempt.fromJson(a)
      ],
    );
  }
}

class QuestionMessage {
  final String id, from, name, body;
  final String? image;
  final int at;
  final bool mine;
  const QuestionMessage(
      {required this.id, required this.from, required this.name, required this.body, this.image, required this.at, required this.mine});
  bool get fromTeacher => from == 'teacher';

  factory QuestionMessage.fromJson(Object? o) {
    final j = _m(o);
    return QuestionMessage(
      id: _s(j['id']),
      from: _s(j['from']),
      name: _s(j['name']),
      body: _s(j['body']),
      image: j['image'] as String?,
      at: _i(j['at']),
      mine: j['mine'] == true,
    );
  }
}

class Question {
  final String id, title, preview, status, lastFrom;
  final PersonRef student, teacher;
  final String? problemId;
  final bool hasImage, unread;
  final int createdAt, updatedAt, messageCount;
  final List<QuestionMessage> messages;

  const Question({
    required this.id,
    required this.title,
    required this.preview,
    required this.status,
    required this.lastFrom,
    required this.student,
    required this.teacher,
    this.problemId,
    required this.hasImage,
    required this.unread,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
    this.messages = const [],
  });

  bool get resolved => status == 'resolved';
  bool get answered => status == 'answered';
  String get statusLabel => switch (status) { 'answered' => '답변 완료', 'resolved' => '해결', _ => '답변 대기' };

  factory Question.fromJson(Object? o) {
    final j = _m(o);
    return Question(
      id: _s(j['id']),
      title: _s(j['title']),
      preview: _s(j['preview']),
      status: _s(j['status']),
      lastFrom: _s(j['lastFrom']),
      student: PersonRef.fromJson(j['student']),
      teacher: PersonRef.fromJson(j['teacher']),
      problemId: j['problemId'] as String?,
      hasImage: j['hasImage'] == true,
      unread: j['unread'] == true,
      createdAt: _i(j['createdAt']),
      updatedAt: _i(j['updatedAt']),
      messageCount: _i(j['messageCount']),
      messages: [for (final m in _lm(j['messages'])) QuestionMessage.fromJson(m)],
    );
  }
}

/// A textbook the teacher put on the server (`/api/books`).
class ServerBook {
  final String id;
  final String title;
  final List<String> titles;
  final List<String> bookIds;
  final int problems;
  final int bytes;
  final int at;

  /// 서버에 있는 파일의 지문 — 바뀌면 다시 받는다.
  final String sha;
  final String teacherName;
  final bool mine;
  final bool open;

  const ServerBook({
    required this.id,
    required this.title,
    this.titles = const [],
    this.bookIds = const [],
    this.problems = 0,
    this.bytes = 0,
    this.at = 0,
    this.sha = '',
    this.teacherName = '',
    this.mine = false,
    this.open = true,
  });

  /// "1.2MB" — rough size for the download button.
  String get sizeLabel => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB'
      : '${(bytes / 1024).ceil()}KB';

  factory ServerBook.fromJson(Object? o) {
    final j = _m(o);
    return ServerBook(
      id: _s(j['id']),
      title: _s(j['title']),
      titles: [for (final t in (j['titles'] as List? ?? const [])) _s(t)],
      bookIds: [for (final t in (j['bookIds'] as List? ?? const [])) _s(t)],
      problems: _i(j['problems']),
      bytes: _i(j['bytes']),
      at: _i(j['at']),
      sha: _s(j['sha']),
      teacherName: _s(_m(j['teacher'])['name']),
      mine: j['mine'] == true,
      open: j['open'] != false,
    );
  }
}

/// Server records of a student (for restoring on a new tablet).
class ServerRecords {
  final List<Attempt> attempts;
  final Map<String, dynamic>? learner;
  final List<String>? wrongNote;
  const ServerRecords(this.attempts, this.learner, this.wrongNote);
}

/// Client for docs/accounts-api.md.
class AccountApi {
  AccountApi(this.server, [this.token = '']);
  final String server;
  final String token;

  factory AccountApi.of(Account a) => AccountApi(a.server, a.token);

  String get base {
    final b = ContentSync.httpBase(server);
    if (b == null) throw const ApiError('서버 주소를 입력하세요');
    return b;
  }

  /// Full URL for a path the server returned (e.g. a question image).
  String url(String path) => path.startsWith('http') ? path : '$base$path';
  Map<String, String> get authHeaders => token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};

  Future<Map<String, dynamic>> _req(String method, String path,
      {Map<String, Object?>? body,
      Uint8List? rawBody,
      Map<String, String>? query,
      Duration timeout = const Duration(seconds: 20)}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.openUrl(method, uri).timeout(const Duration(seconds: 8));
      if (token.isNotEmpty) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (rawBody != null) {
        req.headers.contentType = ContentType('application', 'octet-stream');
        req.headers.contentLength = rawBody.length;
        req.add(rawBody);
      } else if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      Object? data;
      try {
        data = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {}
      if (res.statusCode >= 400) {
        final msg = data is Map && data['error'] != null ? '${data['error']}' : '요청 실패 (${res.statusCode})';
        throw ApiError(msg, res.statusCode);
      }
      return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    } on SocketException {
      throw const ApiError('서버에 연결할 수 없어요 · 주소와 인터넷 연결을 확인하세요');
    } on HandshakeException {
      throw const ApiError('서버와 보안 연결을 할 수 없어요');
    } on TimeoutException {
      throw const ApiError('서버 응답이 없어요');
    } on FormatException {
      throw const ApiError('서버 주소가 올바르지 않아요');
    } finally {
      client.close(force: true);
    }
  }

  // ── 계정 ──
  Future<(String, MeInfo)> signup({
    required String role,
    required String loginId,
    required String password,
    required String name,
    String grade = '',
    List<String> grades = const <String>[],
    String teacherCode = '',
    String studentCode = '',
  }) async {
    final d = await _req('POST', '/api/auth/signup', body: {
      'role': role,
      'loginId': loginId,
      'password': password,
      'name': name,
      'grade': grades.isNotEmpty ? grades.first : grade,
      if (grades.isNotEmpty) 'grades': grades,
      if (teacherCode.trim().isNotEmpty) 'teacherCode': teacherCode.trim(),
      if (studentCode.trim().isNotEmpty) 'studentCode': studentCode.trim(),
    });
    return (_s(d['token']), MeInfo.fromJson(d));
  }

  /// 추천코드 확인 — 맞으면 그 코드가 받는 부류(예: 한양대생)와 고를 수 있는 학년·과정.
  Future<SignupCodeInfo> checkSignupCode(String code) async {
    final d = await _req('POST', '/api/auth/signup-code', body: {'code': code.trim()});
    return SignupCodeInfo(label: _s(d['label']), grades: [for (final g in (d['grades'] as List? ?? const [])) _s(g)]);
  }

  Future<(String, MeInfo)> login(String loginId, String password) async {
    final d = await _req('POST', '/api/auth/login', body: {'loginId': loginId, 'password': password});
    return (_s(d['token']), MeInfo.fromJson(d));
  }

  Future<void> logout() => _req('POST', '/api/auth/logout', body: const {});
  Future<MeInfo> me() async => MeInfo.fromJson(await _req('GET', '/api/me'));
  Future<MeInfo> updateMe({String? name, String? grade, List<String>? grades}) async => MeInfo.fromJson(await _req('POST', '/api/me',
      body: {if (name != null) 'name': name, if (grade != null) 'grade': grade, if (grades != null) 'grades': grades}));
  Future<void> changePassword(String current, String next) =>
      _req('POST', '/api/me/password', body: {'current': current, 'next': next});

  // ── 학생 ──
  Future<PersonRef> joinTeacher(String code) async =>
      PersonRef.fromJson((await _req('POST', '/api/student/teachers', body: {'code': code}))['teacher']);
  Future<void> leaveTeacher(String teacherId) =>
      _req('DELETE', '/api/student/teachers/${Uri.encodeComponent(teacherId)}');

  Future<int> sync({List<Attempt>? attempts, Map<String, dynamic>? learner, List<String>? wrongNote}) async {
    final d = await _req('POST', '/api/student/sync',
        body: {
          if (attempts != null) 'attempts': [for (final a in attempts) a.toJson()],
          if (learner != null) 'learner': learner,
          if (wrongNote != null) 'wrongNote': wrongNote,
        },
        timeout: const Duration(seconds: 60));
    return _i(d['total']);
  }

  Future<ServerRecords> records() async {
    final d = await _req('GET', '/api/student/records', timeout: const Duration(seconds: 60));
    return ServerRecords(
      [
        for (final a in _lm(d['attempts']))
          if (_s(a['id']).isNotEmpty && _s(a['pid']).isNotEmpty) Attempt.fromJson(a)
      ],
      d['learner'] is Map ? _m(d['learner']) : null,
      d['wrongNote'] is List ? [for (final x in d['wrongNote'] as List) '$x'] : null,
    );
  }

  // ── 선생님 ──
  Future<(String, List<StudentSummary>)> students() async {
    final d = await _req('GET', '/api/teacher/students');
    return (_s(d['inviteCode']), [for (final s in _lm(d['students'])) StudentSummary.fromJson(s)]);
  }

  Future<StudentDetail> student(String id) async =>
      StudentDetail.fromJson(await _req('GET', '/api/teacher/students/${Uri.encodeComponent(id)}'));
  Future<void> removeStudent(String id) => _req('DELETE', '/api/teacher/students/${Uri.encodeComponent(id)}');
  Future<String> newInviteCode() async => _s((await _req('POST', '/api/teacher/invite', body: const {}))['inviteCode']);

  // ── 질문 ──
  static String? _dataUrl(Uint8List? png) => png == null ? null : 'data:image/png;base64,${base64Encode(png)}';

  Future<Question> ask({
    required String teacherId,
    required String body,
    String? title,
    String? problemId,
    Uint8List? imagePng,
  }) async {
    final d = await _req('POST', '/api/questions',
        body: {
          'teacherId': teacherId,
          'body': body,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          if (problemId != null) 'problemId': problemId,
          if (imagePng != null) 'image': _dataUrl(imagePng),
        },
        timeout: const Duration(seconds: 60));
    return Question.fromJson(d['question']);
  }

  Future<List<Question>> questions({String status = 'all', String? studentId}) async {
    final d = await _req('GET', '/api/questions', query: {'status': status, if (studentId != null) 'student': studentId});
    return [for (final q in _lm(d['questions'])) Question.fromJson(q)];
  }

  Future<Question> question(String id) async =>
      Question.fromJson((await _req('GET', '/api/questions/${Uri.encodeComponent(id)}'))['question']);

  Future<Question> reply(String id, {String body = '', Uint8List? imagePng}) async {
    final d = await _req('POST', '/api/questions/${Uri.encodeComponent(id)}/messages',
        body: {'body': body, if (imagePng != null) 'image': _dataUrl(imagePng)}, timeout: const Duration(seconds: 60));
    return Question.fromJson(d['question']);
  }

  Future<void> resolve(String id) => _req('POST', '/api/questions/${Uri.encodeComponent(id)}/resolve', body: const {});

  // ── 교재 창고 (선생님이 올린 .pulinote) ──

  /// 내가 받을 수 있는 교재들 (학생: 연결된 선생님이 올린 것, 선생님: 내가 올린 것).
  Future<List<ServerBook>> books() async =>
      [for (final b in _lm((await _req('GET', '/api/books'))['books'])) ServerBook.fromJson(b)];

  /// 교재 파일 그대로 (`ContentImport.decodeAll` 로 읽는다).
  Future<Uint8List> bookBytes(String id) =>
      _bytes('/api/books/${Uri.encodeComponent(id)}/file', '교재를 받지 못했어요');

  /// (선생님) 교재 올리기 — 같은 교재를 다시 올리면 서버에서 바꿔 끼운다.
  Future<ServerBook> uploadBook(Uint8List file, {String title = '', bool open = true}) async {
    final d = await _req('POST', '/api/books',
        rawBody: file,
        query: {if (title.trim().isNotEmpty) 'title': title.trim(), 'open': open ? '1' : '0'},
        timeout: const Duration(minutes: 3));
    return ServerBook.fromJson(d['book']);
  }

  /// (선생님) 제목·공개 여부 바꾸기.
  Future<ServerBook> updateBook(String id, {String? title, bool? open}) async {
    final d = await _req('POST', '/api/books/${Uri.encodeComponent(id)}',
        body: {if (title != null) 'title': title, if (open != null) 'open': open});
    return ServerBook.fromJson(d['book']);
  }

  /// (선생님) 서버에서 교재 빼기.
  Future<void> deleteBook(String id) => _req('DELETE', '/api/books/${Uri.encodeComponent(id)}');

  /// A question picture (needs the login token).
  Future<Uint8List> imageBytes(String path) => _bytes(path, '그림을 불러오지 못했어요');

  /// GET → bytes, with the login token.
  Future<Uint8List> _bytes(String path, String failed) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(url(path))).timeout(const Duration(seconds: 8));
      if (token.isNotEmpty) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final res = await req.close().timeout(const Duration(minutes: 3));
      final bb = BytesBuilder(copy: false);
      await for (final chunk in res) {
        bb.add(chunk);
      }
      if (res.statusCode >= 400) {
        final j = () {
          try {
            return jsonDecode(utf8.decode(bb.toBytes()));
          } catch (_) {
            return null;
          }
        }();
        final msg = j is Map && j['error'] != null ? '${j['error']}' : '$failed (${res.statusCode})';
        throw ApiError(msg, res.statusCode);
      }
      return bb.takeBytes();
    } on SocketException {
      throw const ApiError('서버에 연결할 수 없어요');
    } on TimeoutException {
      throw const ApiError('서버 응답이 없어요');
    } finally {
      client.close(force: true);
    }
  }
}
