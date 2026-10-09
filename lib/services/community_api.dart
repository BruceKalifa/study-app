import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'content_sync.dart';

/// Error with a message that can be shown to the student as-is.
class CommunityError implements Exception {
  final String message;
  const CommunityError(this.message);
  @override
  String toString() => message;
}

class Board {
  final String id, name, desc;

  /// 이 게시판이 맞는 학년·과정 (비면 모두). server/community.js 의 BOARDS 와 같아야 한다.
  final List<String> tracks;
  const Board(this.id, this.name, this.desc, [this.tracks = const <String>[]]);

  static const _high = ['고1', '고2', '고3', 'N수'];

  static const defaults = [
    Board('free', '자유', '수험생활 이야기'),
    Board('qna', '질문', '과목·문제 질문'),
    Board('proof', '공부인증', '오늘 공부한 것 인증'),
    Board('info', '입시정보', '입시·모의고사 정보', _high),
    Board('mind', '고민·멘탈', '털어놓고 응원받기'),
    Board('tips', '공부법·꿀팁', '시간표·암기·오답 정리 노하우'),
    Board('study', '스터디 모집', '같이 공부할 사람 찾기'),
    Board('naesin', '내신', '학교 시험·수행평가·내신 전략', ['고1', '고2', '고3']),
    Board('suneung', '수능·모의고사', '학평·모평·수능 후기와 분석', ['고2', '고3', 'N수']),
    Board('math', '수학', '수학 개념·풀이·킬러 문항', _high),
    Board('sci', '과학', '물리·화학·생명·지구과학', _high),
    Board('lang', '국어·영어', '국어·영어 공부법과 질문', _high),
    Board('soc', '사회탐구', '사탐 과목 공부법과 질문', _high),
    Board('sisi', '수시·정시', '수시 최저·정시 지원 전략', ['고3', 'N수']),
    Board('nsu', 'N수·재수', '반수·재수 생활과 계획', ['N수']),
    Board('apt', '인적성·NCS', '인적성·NCS 후기와 유형 공유', ['취준']),
    Board('job', '취업정보', '채용 일정·자소서·면접 정보', ['취준']),
    Board('hyu', '한양대 라운지', '학교 생활·수강·시험 이야기', ['한양대']),
    Board('univmath', '공업수학·미적분학', '공업수학1·2, 미적분학1·2 질문', ['한양대']),
    Board('univexam', '시험·학점', '중간·기말 대비와 학점 관리', ['한양대']),
    Board('transfer', '편입정보', '대학별 일정·기출·합격 후기', ['편입']),
    Board('trmath', '편입수학', '편입수학 개념과 기출 질문', ['편입']),
  ];

  /// 고른 학년·과정에 맞는 게시판 (공통 게시판 + 과정별). 과정을 모르면 전부.
  static List<Board> forGrades(Iterable<String> grades) {
    final gs = grades.toSet();
    if (gs.isEmpty) return defaults;
    return [
      for (final b in defaults)
        if (b.tracks.isEmpty || b.tracks.any(gs.contains)) b,
    ];
  }

  static String nameOf(String id) {
    for (final b in defaults) {
      if (b.id == id) return b.name;
    }
    return id;
  }
}

class Comment {
  final String id, author, grade, body;
  final int createdAt;
  final bool mine;
  const Comment({
    required this.id,
    required this.author,
    required this.grade,
    required this.body,
    required this.createdAt,
    required this.mine,
  });

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: '${j['id']}',
        author: '${j['author'] ?? ''}',
        grade: '${j['grade'] ?? ''}',
        body: '${j['body'] ?? ''}',
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
        mine: j['mine'] == true,
      );
}

class Post {
  final String id, board, title, preview, body, author, grade;
  final String? problemId;
  final int createdAt, likes, commentCount, views;
  final bool liked, mine;
  final List<Comment> comments;

  const Post({
    required this.id,
    required this.board,
    required this.title,
    required this.preview,
    required this.body,
    required this.author,
    required this.grade,
    required this.createdAt,
    required this.likes,
    required this.commentCount,
    required this.views,
    required this.liked,
    required this.mine,
    this.problemId,
    this.comments = const [],
  });

  factory Post.fromJson(Map<String, dynamic> j) {
    final cs = j['comments'];
    final list = cs is List ? [for (final c in cs) Comment.fromJson((c as Map).cast<String, dynamic>())] : <Comment>[];
    return Post(
      id: '${j['id']}',
      board: '${j['board'] ?? 'free'}',
      title: '${j['title'] ?? ''}',
      preview: '${j['preview'] ?? ''}',
      body: '${j['body'] ?? j['preview'] ?? ''}',
      author: '${j['author'] ?? ''}',
      grade: '${j['grade'] ?? ''}',
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      likes: (j['likes'] as num?)?.toInt() ?? 0,
      commentCount: cs is List ? list.length : ((j['comments'] as num?)?.toInt() ?? 0),
      views: (j['views'] as num?)?.toInt() ?? 0,
      liked: j['liked'] == true,
      mine: j['mine'] == true,
      problemId: j['problemId'] as String?,
      comments: list,
    );
  }
}

class RankEntry {
  final int rank;
  final String name, grade;
  final int studyMs, solved;
  final bool me;
  const RankEntry(this.rank, this.name, this.grade, this.studyMs, this.solved, this.me);

  factory RankEntry.fromJson(Map<String, dynamic> j) => RankEntry(
        (j['rank'] as num?)?.toInt() ?? 0,
        '${j['name'] ?? ''}',
        '${j['grade'] ?? ''}',
        (j['studyMs'] as num?)?.toInt() ?? 0,
        (j['solved'] as num?)?.toInt() ?? 0,
        j['me'] == true,
      );
}

class Ranking {
  final String period, day;
  final int total;
  final List<RankEntry> entries;
  final int? myRank;
  final int myStudyMs;
  const Ranking(this.period, this.day, this.total, this.entries, this.myRank, this.myStudyMs);
}

/// First character + "XX" (오예진 → 오XX). Names are masked before they leave the tablet.
String maskName(String name) {
  final t = name.trim();
  if (t.isEmpty) return '익명';
  final first = String.fromCharCode(t.runes.first);
  return '${first}XX';
}

/// Client for docs/community-api.md (same server as the content API).
class CommunityApi {
  CommunityApi(this.serverUrl, this.userId);
  final String serverUrl;
  final String userId;

  String get _base {
    final b = ContentSync.httpBase(serverUrl);
    if (b == null) throw const CommunityError('설정에서 서버 주소를 먼저 입력하세요');
    return b;
  }

  Future<dynamic> _req(String method, String path, {Map<String, Object?>? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.openUrl(method, uri).timeout(const Duration(seconds: 8));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join();
      dynamic data;
      try {
        data = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {}
      if (res.statusCode >= 400) {
        final msg = data is Map && data['error'] != null ? '${data['error']}' : '요청 실패 (${res.statusCode})';
        throw CommunityError(res.statusCode == 429 ? '너무 빨라요. 잠시 후 다시 해 주세요.' : msg);
      }
      return data;
    } on SocketException {
      throw const CommunityError('서버에 연결할 수 없어요 · 주소와 와이파이를 확인하세요');
    } on TimeoutException {
      throw const CommunityError('서버 응답이 없어요');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Post>> posts({String? board, String? q, String sort = 'new', int? before}) async {
    final d = await _req('GET', '/api/community/posts', query: {
      if (board != null) 'board': board,
      if (q != null && q.isNotEmpty) 'q': q,
      'sort': sort,
      if (before != null) 'before': '$before',
      'me': userId,
    });
    final list = (d is Map ? d['posts'] : null) as List? ?? const [];
    return [for (final p in list) Post.fromJson((p as Map).cast<String, dynamic>())];
  }

  Future<Post> post(String id) async {
    final d = await _req('GET', '/api/community/posts/${Uri.encodeComponent(id)}', query: {'me': userId});
    return Post.fromJson(((d as Map)['post'] as Map).cast<String, dynamic>());
  }

  Future<Post> write({
    required String author,
    required String grade,
    required String board,
    required String title,
    required String body,
    String? problemId,
  }) async {
    final d = await _req('POST', '/api/community/posts', body: {
      'userId': userId,
      'author': author,
      'grade': grade,
      'board': board,
      'title': title,
      'body': body,
      if (problemId != null) 'problemId': problemId,
    });
    return Post.fromJson(((d as Map)['post'] as Map).cast<String, dynamic>());
  }

  Future<void> comment(String postId, {required String author, required String grade, required String body}) =>
      _req('POST', '/api/community/posts/${Uri.encodeComponent(postId)}/comments',
          body: {'userId': userId, 'author': author, 'grade': grade, 'body': body});

  Future<(int, bool)> like(String postId) async {
    final d = await _req('POST', '/api/community/posts/${Uri.encodeComponent(postId)}/like', body: {'userId': userId});
    return (((d as Map)['likes'] as num?)?.toInt() ?? 0, d['liked'] == true);
  }

  Future<void> deletePost(String postId) =>
      _req('DELETE', '/api/community/posts/${Uri.encodeComponent(postId)}', query: {'userId': userId});

  Future<void> deleteComment(String postId, String commentId) => _req(
      'DELETE', '/api/community/posts/${Uri.encodeComponent(postId)}/comments/${Uri.encodeComponent(commentId)}',
      query: {'userId': userId});

  Future<void> report(String postId, String reason) => _req(
      'POST', '/api/community/posts/${Uri.encodeComponent(postId)}/report',
      body: {'userId': userId, 'reason': reason});

  Future<void> reportStudy({
    required String name,
    required String grade,
    required String day,
    required int studyMs,
    required int solved,
  }) =>
      _req('POST', '/api/ranking/report', body: {
        'userId': userId,
        'name': maskName(name),
        'grade': grade,
        'day': day,
        'studyMs': studyMs,
        'solved': solved,
      });

  Future<Ranking> ranking({String period = 'day', String? grade, String? day}) async {
    final d = await _req('GET', '/api/ranking', query: {
      'period': period,
      if (grade != null) 'grade': grade,
      if (day != null) 'day': day,
      'me': userId,
    }) as Map;
    final me = d['me'] as Map?;
    return Ranking(
      '${d['period'] ?? period}',
      '${d['day'] ?? ''}',
      (d['total'] as num?)?.toInt() ?? 0,
      [for (final e in (d['entries'] as List? ?? const [])) RankEntry.fromJson((e as Map).cast<String, dynamic>())],
      (me?['rank'] as num?)?.toInt(),
      (me?['studyMs'] as num?)?.toInt() ?? 0,
    );
  }
}
