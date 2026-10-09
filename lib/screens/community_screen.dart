import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../services/community_api.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'dashboard_screen.dart' show fmtStudy;
import 'solve_screen.dart';

String relTime(int ms) {
  final d = DateTime.now().millisecondsSinceEpoch - ms;
  if (d < 60000) return '방금';
  if (d < 3600000) return '${d ~/ 60000}분 전';
  if (d < 86400000) return '${d ~/ 3600000}시간 전';
  if (d < 7 * 86400000) return '${d ~/ 86400000}일 전';
  return fmtDate(ms, withTime: false);
}

Color boardColor(String id) => switch (id) {
      'qna' || 'math' || 'univmath' || 'trmath' => AppColors.blue,
      'proof' || 'study' || 'naesin' || 'univexam' => AppColors.correct,
      'info' || 'suneung' || 'sisi' || 'transfer' => const Color(0xFF8C5BD6),
      'mind' || 'nsu' => AppColors.accent,
      'sci' || 'lang' || 'soc' || 'tips' => const Color(0xFF0E7C86),
      'apt' || 'job' || 'hyu' => const Color(0xFFC7791F),
      _ => AppColors.inkSoft,
    };

/// 수험생 커뮤니티: 게시판 + 공부시간 순위.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String? _board;
  String _sort = 'new';
  String _q = '';
  List<Post> _posts = [];
  bool _loading = false;
  bool _more = true;
  String? _error;

  /// 가입 때 고른 학년·과정에 맞는 게시판 (공통 + 과정별). 전체 보기는 모든 글.
  List<Board> get _boards => Board.forGrades(AppScope.read(context).learner.grades);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool append = false}) async {
    final api = AppScope.read(context).community;
    if (api == null) {
      setState(() => _error = null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.posts(
        board: _board,
        q: _q,
        sort: _sort,
        before: append && _posts.isNotEmpty && _sort == 'new' ? _posts.last.createdAt : null,
      );
      if (!mounted) return;
      setState(() {
        _posts = append ? [..._posts, ...list] : list;
        _more = list.length >= 30 && _sort == 'new';
      });
    } on CommunityError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _write() async {
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => WritePostScreen(board: _board ?? 'free')));
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final api = app.community;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1050;
      final feed = _feed(app, api);
      if (!wide) {
        return ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 40), children: [
          _header(api),
          const SizedBox(height: 16),
          if (api != null) const RankingPanel(compact: true),
          const SizedBox(height: 16),
          ...feed,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(32, 28, 16, 40), children: [
              _header(api),
              const SizedBox(height: 18),
              ...feed,
            ]),
          ),
        ),
        SizedBox(
          width: 400,
          child: ListView(padding: const EdgeInsets.fromLTRB(8, 28, 28, 40), children: [
            if (api != null) const RankingPanel() else const SizedBox(),
          ]),
        ),
      ]);
    });
  }

  Widget _header(CommunityApi? api) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('커뮤니티', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
            SizedBox(height: 4),
            Text('같은 목표를 가진 수험생들과 묻고, 인증하고, 응원해요',
                style: TextStyle(fontSize: 15.5, color: AppColors.inkSoft)),
          ]),
        ),
        if (api != null)
          FilledButton.icon(
            key: const Key('post-write'),
            onPressed: _write,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(0, 50)),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('글쓰기'),
          ),
      ]),
      if (api != null) ...[
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                ChoiceChip(
                  label: const Text('전체'),
                  selected: _board == null,
                  onSelected: (_) {
                    setState(() => _board = null);
                    _load();
                  },
                ),
                for (final b in _boards) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: Key('board-${b.id}'),
                    label: Text(b.name),
                    selected: _board == b.id,
                    onSelected: (_) {
                      setState(() => _board = b.id);
                      _load();
                    },
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'new', label: Text('최신')),
              ButtonSegment(value: 'hot', label: Text('인기')),
            ],
            selected: {_sort},
            onSelectionChanged: (v) {
              setState(() => _sort = v.first);
              _load();
            },
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: '검색', isDense: true),
              onSubmitted: (v) {
                _q = v.trim();
                _load();
              },
            ),
          ),
        ]),
      ],
    ]);
  }

  List<Widget> _feed(AppState app, CommunityApi? api) {
    if (api == null) {
      return const [
        SizedBox(height: 40),
        EmptyState(
          icon: Icons.forum_outlined,
          title: '커뮤니티 서버에 연결되지 않았어요',
          message: '설정 → 선생님 서버 주소를 입력하면 게시판과 공부시간 순위를 쓸 수 있어요.',
        ),
      ];
    }
    if (_error != null) {
      return [
        const SizedBox(height: 30),
        EmptyState(
          icon: Icons.wifi_off_rounded,
          title: '불러오지 못했어요',
          message: _error,
          action: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('다시 시도')),
        ),
      ];
    }
    if (_posts.isEmpty) {
      return [
        if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (!_loading)
          const Padding(
            padding: EdgeInsets.only(top: 30),
            child: EmptyState(icon: Icons.chat_bubble_outline_rounded, title: '아직 글이 없어요', message: '첫 글을 남겨 보세요!'),
          ),
      ];
    }
    return [
      for (final p in _posts)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _PostTile(
            post: p,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PostScreen(postId: p.id)));
              _load();
            },
          ),
        ),
      if (_more)
        Center(
          child: TextButton(
            onPressed: _loading ? null : () => _load(append: true),
            child: Text(_loading ? '불러오는 중…' : '더 보기'),
          ),
        ),
    ];
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.onTap});
  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = boardColor(post.board);
    return Card(
      key: Key('post-${post.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Pill(Board.nameOf(post.board), color: c, dense: true),
              if (post.problemId != null) ...[
                const SizedBox(width: 6),
                const Pill('문제 질문', color: AppColors.inkSoft, icon: Icons.link_rounded, dense: true),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Text(post.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              ),
            ]),
            if (post.preview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(MathText.plain(post.preview),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft, height: 1.45)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Text('${post.author}${post.grade.isEmpty ? '' : ' · ${post.grade}'} · ${relTime(post.createdAt)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
              if (post.mine) ...[
                const SizedBox(width: 6),
                const Pill('내 글', color: AppColors.blue, dense: true),
              ],
              const Spacer(),
              _Count(post.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, post.likes,
                  color: post.liked ? AppColors.wrong : null),
              _Count(Icons.chat_bubble_outline_rounded, post.commentCount),
              _Count(Icons.visibility_outlined, post.views),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.icon, this.n, {this.color});
  final IconData icon;
  final int n;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(children: [
          Icon(icon, size: 16, color: color ?? AppColors.inkMuted),
          const SizedBox(width: 4),
          Text('$n', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
        ]),
      );
}

// ============================================================ post
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Post? _post;
  String? _error;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  CommunityApi get _api => AppScope.read(context).community!;

  Future<void> _load() async {
    try {
      final p = await _api.post(widget.postId);
      if (mounted) setState(() => _post = p);
    } on CommunityError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _sendComment() async {
    final t = _comment.text.trim();
    if (t.isEmpty || _sending) return;
    final app = AppScope.read(context);
    setState(() => _sending = true);
    try {
      await _api.comment(widget.postId, author: app.communityName, grade: app.learner.grade, body: t);
      _comment.clear();
      await _load();
    } on CommunityError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _like() async {
    try {
      await _api.like(widget.postId);
      await _load();
    } on CommunityError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _menu(String v) async {
    try {
      if (v == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('글을 지울까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('지우기')),
            ],
          ),
        );
        if (ok != true) return;
        await _api.deletePost(widget.postId);
        if (mounted) Navigator.of(context).pop();
      } else if (v == 'report') {
        final reason = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('신고 사유'),
            children: [
              for (final r in ['욕설·비방', '광고·도배', '음란·불쾌', '개인정보 노출', '기타'])
                SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(r)),
            ],
          ),
        );
        if (reason == null) return;
        await _api.report(widget.postId, reason);
        _toast('신고했어요. 여러 명이 신고하면 글이 숨겨져요.');
      }
    } on CommunityError catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = _post;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? '' : Board.nameOf(p.board)),
        actions: [
          if (p != null)
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                if (p.mine) const PopupMenuItem(value: 'delete', child: Text('삭제')),
                if (!p.mine) const PopupMenuItem(value: 'report', child: Text('신고')),
              ],
            ),
        ],
      ),
      body: p == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : Column(children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView(padding: const EdgeInsets.fromLTRB(28, 8, 28, 24), children: [
                      Text(p.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                      const SizedBox(height: 8),
                      Text('${p.author}${p.grade.isEmpty ? '' : ' · ${p.grade}'} · ${relTime(p.createdAt)} · 조회 ${p.views}',
                          style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                      const Divider(height: 32),
                      MathText(p.body, style: const TextStyle(fontSize: 17, height: 1.75)),
                      if (p.problemId != null) ...[
                        const SizedBox(height: 18),
                        Builder(builder: (context) {
                          final prob = app.problem(p.problemId!);
                          return OutlinedButton.icon(
                            onPressed: prob == null
                                ? null
                                : () => SolveScreen.open(context, title: '질문한 문제', problems: [prob]),
                            icon: const Icon(Icons.link_rounded),
                            label: Text(prob == null
                                ? '연결된 문제를 이 기기에서 찾을 수 없어요'
                                : '문제 보기 · ${prob.subjectName} ${prob.topic}'),
                          );
                        }),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: OutlinedButton.icon(
                          key: const Key('post-like'),
                          onPressed: _like,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.liked ? AppColors.wrong : AppColors.inkSoft,
                            side: BorderSide(color: p.liked ? AppColors.wrong : AppColors.line),
                            minimumSize: const Size(120, 48),
                          ),
                          icon: Icon(p.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                          label: Text('응원 ${p.likes}'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('댓글 ${p.comments.length}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      for (final c in p.comments)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${c.author}${c.grade.isEmpty ? '' : ' · ${c.grade}'}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(c.body, style: const TextStyle(color: AppColors.ink, fontSize: 15, height: 1.5)),
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(relTime(c.createdAt), style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                            if (c.mine)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () async {
                                  try {
                                    await _api.deleteComment(p.id, c.id);
                                    await _load();
                                  } on CommunityError catch (e) {
                                    _toast(e.message);
                                  }
                                },
                              ),
                          ]),
                        ),
                    ]),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('comment-input'),
                        controller: _comment,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(hintText: '${app.communityName}(으)로 댓글 달기', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      key: const Key('comment-send'),
                      onPressed: _sending ? null : _sendComment,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}

// ============================================================ write
class WritePostScreen extends StatefulWidget {
  const WritePostScreen({super.key, this.board = 'free', this.problem});
  final String board;

  /// "이 문제 질문하기" from the solve screen.
  final Problem? problem;

  @override
  State<WritePostScreen> createState() => _WritePostScreenState();
}

class _WritePostScreenState extends State<WritePostScreen> {
  late String _board = widget.problem != null ? 'qna' : widget.board;
  late final _title = TextEditingController(
      text: widget.problem == null ? '' : '[${widget.problem!.subjectName}] ${widget.problem!.topic} 질문');
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = AppScope.read(context);
    final api = app.community;
    if (api == null || _sending) return;
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목과 내용을 써 주세요')));
      return;
    }
    setState(() => _sending = true);
    try {
      await api.write(
        author: app.communityName,
        grade: app.learner.grade,
        board: _board,
        title: _title.text.trim(),
        body: _body.text.trim(),
        problemId: widget.problem?.id,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on CommunityError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('글쓰기'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              key: const Key('post-send'),
              onPressed: _sending ? null : _send,
              child: Text(_sending ? '올리는 중…' : '올리기'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(28), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in Board.forGrades(AppScope.read(context).learner.grades))
                ChoiceChip(
                  key: Key('write-board-${b.id}'),
                  label: Text(b.name),
                  selected: _board == b.id,
                  onSelected: (_) => setState(() => _board = b.id),
                ),
            ]),
            const SizedBox(height: 16),
            TextField(
              key: const Key('post-title'),
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(hintText: '제목'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('post-body'),
              controller: _body,
              minLines: 10,
              maxLines: 24,
              maxLength: 5000,
              decoration: const InputDecoration(hintText: '내용 · 수식은 \$x^2\$ 처럼 쓰면 돼요', alignLabelWithHint: true),
            ),
            if (widget.problem != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.paperDeep, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.link_rounded, color: AppColors.inkSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('문제가 함께 첨부돼요 · ${MathText.plain(widget.problem!.stem)}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            Text('${app.communityName}(으)로 올라가요 · 실명·연락처 등 개인정보는 쓰지 마세요',
                style: const TextStyle(color: AppColors.inkMuted)),
          ]),
        ),
      ),
    );
  }
}

// ============================================================ ranking
/// 공부시간 순위 — names are masked (오XX) before they leave the tablet.
class RankingPanel extends StatefulWidget {
  const RankingPanel({super.key, this.compact = false});
  final bool compact;

  @override
  State<RankingPanel> createState() => _RankingPanelState();
}

class _RankingPanelState extends State<RankingPanel> {
  String _period = 'day';
  bool _myGrade = false;
  Ranking? _r;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final api = app.community;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await app.reportStudy();
      final r = await api.ranking(period: _period, grade: _myGrade ? app.learner.grade : null);
      if (mounted) setState(() => _r = r);
    } on CommunityError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final r = _r;
    final entries = r?.entries ?? const <RankEntry>[];
    final show = widget.compact ? entries.take(5).toList() : entries;
    return Card(
      key: const Key('ranking-panel'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.emoji_events_rounded, color: AppColors.review),
            const SizedBox(width: 8),
            const Text('공부시간 순위', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 20)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'day', label: Text('오늘')),
                ButtonSegment(value: 'week', label: Text('이번 주')),
              ],
              selected: {_period},
              onSelectionChanged: (v) {
                setState(() => _period = v.first);
                _load();
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('${app.learner.grade}만'),
              selected: _myGrade,
              onSelected: (v) {
                setState(() => _myGrade = v);
                _load();
              },
            ),
          ]),
          const SizedBox(height: 12),
          if (!app.learner.rankingOptIn)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('순위 참여가 꺼져 있어요 (설정에서 켤 수 있어요)', style: TextStyle(color: AppColors.inkMuted)),
            ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.wrong))
          else if (r == null)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('아직 기록이 없어요. 오늘 첫 순위의 주인공이 되어 보세요!', style: TextStyle(color: AppColors.inkMuted)),
            )
          else
            for (final e in show) _RankRow(e),
          if (r != null && r.myRank != null && !(show.any((e) => e.me))) ...[
            const Divider(),
            _RankRow(RankEntry(r.myRank!, maskName(app.profile.name), app.learner.grade, r.myStudyMs, 0, true)),
          ],
          const SizedBox(height: 8),
          Text(
            '이름은 첫 글자만 보여요 (예: 오XX) · 전체 ${r?.total ?? 0}명 · 공부시간 = 순공 타이머 + 문제 풀이',
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ]),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow(this.e);
  final RankEntry e;

  @override
  Widget build(BuildContext context) {
    final medal = switch (e.rank) {
      1 => const Color(0xFFE8A317),
      2 => const Color(0xFF9AA3B2),
      3 => const Color(0xFFC07A45),
      _ => null,
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: e.me ? AppColors.blueSoft : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: medal != null
              ? Icon(Icons.workspace_premium_rounded, color: medal, size: 24)
              : Text('${e.rank}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
        ),
        const SizedBox(width: 8),
        Text(e.me ? '${e.name} (나)' : e.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
        const SizedBox(width: 8),
        if (e.grade.isNotEmpty) Pill(e.grade, color: AppColors.inkSoft, dense: true),
        const Spacer(),
        Text(fmtStudy(e.studyMs), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
      ]),
    );
  }
}
