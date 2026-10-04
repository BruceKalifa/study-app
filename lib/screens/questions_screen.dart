import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_toolbar.dart';
import '../services/account_api.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import '../widgets/problem_brief.dart';
import '../widgets/problem_card.dart';
import '../widgets/snapshot.dart';
import 'solve_screen.dart';

Color questionStatusColor(String s) => switch (s) {
      'answered' => AppColors.correct,
      'resolved' => AppColors.inkMuted,
      _ => AppColors.review,
    };

/// 질문 (학생) / 질문함 (선생님): 1:1 questions with the linked teacher.
class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({super.key, this.studentId, this.embedded = false});

  /// Teacher: only this student's questions.
  final String? studentId;

  /// Inside another page (no big header).
  final bool embedded;

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  String _status = 'all';
  List<Question>? _list;
  String? _error;
  bool _loading = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    final app = AppScope.read(context);
    final api = app.api;
    if (api == null) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final list = await api.questions(status: _status, studentId: widget.studentId);
      if (app.isTeacher) {
        // 선생님: 답을 기다리는 질문을 먼저
        list.sort((a, b) {
          final o = (a.status == 'open' ? 0 : 1) - (b.status == 'open' ? 0 : 1);
          return o != 0 ? o : b.updatedAt.compareTo(a.updatedAt);
        });
      }
      if (!mounted) return;
      setState(() {
        _list = list;
        _error = null;
      });
      unawaited(app.refreshMe());
    } on ApiError catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _open(Question q) async {
    await QuestionThreadScreen.open(context, q.id);
    _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final teacher = app.isTeacher;
    if (!app.signedIn) return const _NeedAccount();

    final list = _list;
    final header = Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(teacher ? '질문함' : '선생님께 질문',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
          const SizedBox(height: 4),
          Text(
            teacher
                ? '학생들이 보낸 질문이에요 · 답을 기다리는 질문 ${app.openQuestions}개'
                : app.myTeachers.isEmpty
                    ? '선생님과 연결하면 문제와 풀이 사진을 보내 질문할 수 있어요'
                    : '${app.myTeachers.map((t) => t.name).join(', ')}께 질문할 수 있어요',
            style: const TextStyle(fontSize: 15, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
      IconButton(
        key: const Key('q-refresh'),
        tooltip: '새로고침',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh_rounded),
      ),
      if (!teacher) ...[
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('q-new'),
          onPressed: app.myTeachers.isEmpty
              ? null
              : () async {
                  final sent = await AskTeacherScreen.open(context);
                  if (sent == true) _load();
                },
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(0, 50)),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('새 질문'),
        ),
      ],
    ]);

    final filters = Wrap(spacing: 8, children: [
      for (final (id, label) in const [('all', '전체'), ('open', '답변 대기'), ('answered', '답변 완료'), ('resolved', '해결')])
        ChoiceChip(
          key: Key('q-filter-$id'),
          label: Text(label),
          selected: _status == id,
          onSelected: (_) {
            setState(() => _status = id);
            _load();
          },
        ),
    ]);

    final body = <Widget>[
      if (!widget.embedded) ...[header, const SizedBox(height: 18)],
      if (!teacher && app.myTeachers.isEmpty) ...[const LinkTeacherCard(), const SizedBox(height: 18)],
      filters,
      const SizedBox(height: 14),
      if (_error != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_off_rounded, color: AppColors.wrong),
            title: Text(_error!),
            trailing: TextButton(onPressed: _load, child: const Text('다시 시도')),
          ),
        )
      else if (list == null)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
      else if (list.isEmpty)
        EmptyState(
          icon: Icons.forum_outlined,
          title: teacher ? '아직 받은 질문이 없어요' : '아직 보낸 질문이 없어요',
          message: teacher
              ? '학생이 문제를 풀다가 "질문"을 누르면 여기로 와요.'
              : '문제를 풀고 채점한 뒤 "질문"을 누르면 풀이 화면과 함께 보낼 수 있어요.',
        )
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _QuestionTile(question: list[i], teacher: teacher, onTap: () => _open(list[i])),
            ],
          ]),
        ),
    ];

    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(32, 28, 32, 40), children: body),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.question, required this.teacher, required this.onTap});
  final Question question;
  final bool teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = question;
    final p = q.problemId == null ? null : app.problem(q.problemId!);
    final who = teacher ? '${q.student.name}${q.student.grade.isEmpty ? '' : ' · ${q.student.grade}'}' : q.teacher.name;
    return InkWell(
      key: Key('q-${q.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          SizedBox(
            width: 14,
            child: q.unread
                ? Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle))
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(q.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16.5, fontWeight: q.unread ? FontWeight.w800 : FontWeight.w700)),
                ),
                if (q.hasImage) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.image_outlined, size: 17, color: AppColors.inkMuted),
                ],
              ]),
              const SizedBox(height: 3),
              Text(
                [
                  who,
                  if (p != null) '${p.subjectName} · ${p.topic.isEmpty ? p.unit : p.topic}',
                  fmtDate(q.updatedAt),
                  if (q.messageCount > 1) '메시지 ${q.messageCount}',
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
              ),
              if (q.preview.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(MathText.plain(q.preview),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: AppColors.inkSoft)),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Pill(q.statusLabel, color: questionStatusColor(q.status)),
        ]),
      ),
    );
  }
}

/// Shown when the app is used without an account.
class _NeedAccount extends StatelessWidget {
  const _NeedAccount();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.forum_outlined,
      title: '로그인하면 선생님께 질문할 수 있어요',
      message: '학생 계정으로 로그인하고 선생님의 초대 코드를 입력하면,\n문제와 내 풀이 화면을 보내고 답을 받을 수 있어요.',
      action: FilledButton.icon(
        key: const Key('q-login'),
        onPressed: () => AppScope.read(context).showWelcome(),
        icon: const Icon(Icons.login_rounded),
        label: const Text('로그인 · 회원가입'),
      ),
    );
  }
}

/// 선생님 초대 코드 입력 (학생).
class LinkTeacherCard extends StatefulWidget {
  const LinkTeacherCard({super.key});

  @override
  State<LinkTeacherCard> createState() => _LinkTeacherCardState();
}

class _LinkTeacherCardState extends State<LinkTeacherCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final app = AppScope.read(context);
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final t = await app.joinTeacher(_code.text);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _msg = '${t.name}과(와) 연결됐어요! 이제 선생님이 내 풀이 기록을 보고, 질문에 답할 수 있어요.';
        _code.clear();
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _msg = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.link_rounded, color: AppColors.blue),
            SizedBox(width: 8),
            Text('선생님과 연결하기', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          const Text('선생님께 받은 6자리 초대 코드를 입력하세요. 연결하면 선생님이 내가 푼 문제와 틀린 문제를 볼 수 있어요.',
              style: TextStyle(color: AppColors.inkSoft)),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const Key('link-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: '예: K7Q2MX'),
                onSubmitted: (_) => _join(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              key: const Key('link-join'),
              onPressed: _busy ? null : _join,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              child: const Text('연결'),
            ),
          ]),
          if (_msg != null) ...[
            const SizedBox(height: 10),
            Text(_msg!, style: TextStyle(fontWeight: FontWeight.w700, color: _ok ? AppColors.correct : AppColors.wrong)),
          ],
        ]),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── thread

class QuestionThreadScreen extends StatefulWidget {
  const QuestionThreadScreen({super.key, required this.questionId});
  final String questionId;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuestionThreadScreen(questionId: id)));

  @override
  State<QuestionThreadScreen> createState() => _QuestionThreadScreenState();
}

class _QuestionThreadScreenState extends State<QuestionThreadScreen> {
  Question? _q;
  String? _error;
  bool _sending = false;
  Uint8List? _ink;
  final _text = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  AccountApi get _api => AppScope.read(context).api!;

  Future<void> _load() async {
    try {
      final q = await _api.question(widget.questionId);
      if (!mounted) return;
      setState(() {
        _q = q;
        _error = null;
      });
      unawaited(AppScope.read(context).refreshMe());
      _toBottom();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty && _ink == null) return;
    setState(() => _sending = true);
    try {
      final q = await _api.reply(widget.questionId, body: body, imagePng: _ink);
      if (!mounted) return;
      setState(() {
        _q = q;
        _text.clear();
        _ink = null;
      });
      _toBottom();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resolve() async {
    try {
      await _api.resolve(widget.questionId);
      await _load();
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _draw(Problem? p) async {
    final q = _q;
    // 학생이 보낸 마지막 그림 위에 필기 (없으면 문제 위에)
    String? lastImage;
    if (q != null) {
      for (final m in q.messages.reversed) {
        if (m.image != null && !m.mine) {
          lastImage = m.image;
          break;
        }
      }
    }
    final png = await HandwriteScreen.open(context, imagePath: lastImage, problem: p);
    if (png != null && mounted) setState(() => _ink = png);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = _q;
    final p = q?.problemId == null ? null : app.problem(q!.problemId!);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    Widget? problemPane;
    if (p != null) {
      problemPane = Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('질문한 문제', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              if (!app.isTeacher)
                TextButton.icon(
                  onPressed: () => SolveScreen.open(context, title: '질문한 문제', problems: [p], mode: 'review'),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('다시 풀기'),
                ),
            ]),
            const SizedBox(height: 10),
            ProblemBrief(problem: p, showSolution: true, compact: true),
          ]),
        ),
      );
    }

    final thread = Column(children: [
      Expanded(
        child: q == null
            ? Center(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: AppColors.wrong))
                    : const CircularProgressIndicator())
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                children: [
                  if (!wide && problemPane != null) ...[SizedBox(height: 360, child: problemPane), const SizedBox(height: 12)],
                  for (final m in q.messages) _Bubble(message: m, api: _api),
                  if (q.resolved)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: Pill('해결된 질문이에요 · 다시 쓰면 질문이 열려요', color: AppColors.inkMuted, icon: Icons.check_circle_rounded),
                      ),
                    ),
                ],
              ),
      ),
      if (q != null) _composer(p),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(q?.title ?? '질문'),
        actions: [
          if (q != null) ...[
            Center(child: Pill(q.statusLabel, color: questionStatusColor(q.status))),
            const SizedBox(width: 8),
            if (!q.resolved)
              TextButton.icon(
                key: const Key('q-resolve'),
                onPressed: _resolve,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('해결됨'),
              ),
          ],
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: wide && problemPane != null
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 440, child: problemPane),
                const SizedBox(width: 16),
                Expanded(child: thread),
              ])
            : thread,
      ),
    );
  }

  Widget _composer(Problem? p) {
    final teacher = AppScope.read(context).isTeacher;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_ink != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_ink!, height: 90, fit: BoxFit.contain),
              ),
              const SizedBox(width: 10),
              const Text('필기 그림을 함께 보내요', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
              IconButton(onPressed: () => setState(() => _ink = null), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              key: const Key('q-reply-text'),
              controller: _text,
              minLines: 1,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: teacher ? r'답장 쓰기 · 수식은 $v = v_0 + at$ 처럼' : '더 궁금한 점 쓰기',
                border: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const Key('q-reply-ink'),
            onPressed: _sending ? null : () => _draw(p),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.draw_rounded, size: 19),
            label: Text(teacher ? '필기로 답하기' : '필기 첨부'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('q-send'),
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 19),
            label: const Text('보내기'),
          ),
        ]),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.api});
  final QuestionMessage message;
  final AccountApi api;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final color = m.fromTeacher ? AppColors.correct : AppColors.blue;
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.fromTeacher ? Icons.co_present_rounded : Icons.school_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Text(m.name, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(width: 8),
              Text(fmtDate(m.at), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ]),
            if (m.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              MathText(m.body, style: const TextStyle(fontSize: 15.5, height: 1.6, color: AppColors.ink)),
            ],
            if (m.image != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => _ImageViewer(api: api, path: m.image!))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.white,
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: AuthImage(api: api, path: m.image!),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.api, required this.path});
  final AccountApi api;
  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: InteractiveViewer(
          maxScale: 6,
          child: Center(child: AuthImage(api: api, path: path)),
        ),
      );
}

/// A question picture loaded with the login token (kept in memory for the session).
class AuthImage extends StatefulWidget {
  const AuthImage({super.key, required this.api, required this.path, this.width});
  final AccountApi api;
  final String path;
  final double? width;

  static final Map<String, Uint8List> _cache = {};

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  late Future<Uint8List> _f;

  @override
  void initState() {
    super.initState();
    _f = _load();
  }

  Future<Uint8List> _load() async {
    final hit = AuthImage._cache[widget.path];
    if (hit != null) return hit;
    final b = await widget.api.imageBytes(widget.path);
    if (AuthImage._cache.length > 40) AuthImage._cache.remove(AuthImage._cache.keys.first);
    AuthImage._cache[widget.path] = b;
    return b;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _f,
      builder: (context, snap) {
        final b = snap.data;
        if (b != null) {
          return Image.memory(
            b,
            width: widget.width,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            // keep a box while the picture decodes
            frameBuilder: (context, child, frame, sync) => frame == null && !sync
                ? const SizedBox(width: 160, height: 110, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
                : child,
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.broken_image_outlined, color: AppColors.inkMuted),
              const SizedBox(width: 8),
              const Text('그림을 불러오지 못했어요', style: TextStyle(color: AppColors.inkMuted)),
              TextButton(onPressed: () => setState(() => _f = _load()), child: const Text('다시')),
            ]),
          );
        }
        return const SizedBox(
          width: 160,
          height: 110,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        );
      },
    );
  }
}

// ───────────────────────────────────────────────────────────── ask

/// 학생: 선생님께 질문 보내기 (문제 · 풀이 화면 사진 · 필기 첨부).
class AskTeacherScreen extends StatefulWidget {
  const AskTeacherScreen({super.key, this.problem, this.snapshot});
  final Problem? problem;

  /// The solve page as the student sees it (problem + their handwriting).
  final Uint8List? snapshot;

  static Future<bool?> open(BuildContext context, {Problem? problem, Uint8List? snapshot}) => Navigator.of(context)
      .push(MaterialPageRoute<bool>(builder: (_) => AskTeacherScreen(problem: problem, snapshot: snapshot)));

  @override
  State<AskTeacherScreen> createState() => _AskTeacherScreenState();
}

class _AskTeacherScreenState extends State<AskTeacherScreen> {
  late final TextEditingController _title;
  final _body = TextEditingController();
  Uint8List? _image;
  String? _teacher;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.problem;
    _title = TextEditingController(text: p == null ? '' : '[${p.subjectName}] ${p.topic.isEmpty ? p.unit : p.topic} 질문');
    _image = widget.snapshot;
    final teachers = AppScope.read(context).myTeachers;
    if (teachers.isNotEmpty) _teacher = teachers.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = AppScope.read(context);
    final api = app.api;
    if (api == null || _teacher == null) return;
    if (_body.text.trim().isEmpty && _image == null) {
      setState(() => _error = '무엇이 궁금한지 써 주세요');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await api.ask(
        teacherId: _teacher!,
        title: _title.text,
        body: _body.text.trim(),
        problemId: widget.problem?.id,
        imagePng: _image,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('질문을 보냈어요. 답이 오면 홈과 질문 탭에 표시돼요.')));
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final teachers = app.myTeachers;
    final p = widget.problem;
    return Scaffold(
      appBar: AppBar(title: const Text('선생님께 질문')),
      body: !app.signedIn || teachers.isEmpty
          ? ListView(padding: const EdgeInsets.all(32), children: [
              if (!app.signedIn) const _NeedAccount() else const LinkTeacherCard(),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
              children: [
                if (teachers.length > 1) ...[
                  const Text('누구에게', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final t in teachers)
                      ChoiceChip(label: Text(t.name), selected: _teacher == t.id, onSelected: (_) => setState(() => _teacher = t.id)),
                  ]),
                  const SizedBox(height: 16),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text('받는 사람: ${teachers.first.name}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
                  ),
                TextField(
                  key: const Key('ask-title'),
                  controller: _title,
                  decoration: const InputDecoration(labelText: '제목 (선택)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('ask-body'),
                  controller: _body,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: '무엇이 궁금한가요?',
                    hintText: r'예: 3번 보기에서 왜 운동량이 보존되는지 모르겠어요. 수식은 $p = mv$ 처럼 쓸 수 있어요.',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Text('첨부', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('ask-draw'),
                    onPressed: () async {
                      final png = await HandwriteScreen.open(context, problem: p, image: _image);
                      if (png != null && mounted) setState(() => _image = png);
                    },
                    icon: const Icon(Icons.draw_rounded),
                    label: Text(_image == null ? '필기로 쓰기' : '그림 위에 더 쓰기'),
                  ),
                ]),
                const SizedBox(height: 6),
                if (_image != null)
                  Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        color: Colors.white,
                        constraints: const BoxConstraints(maxHeight: 380),
                        width: double.infinity,
                        child: Image.memory(_image!, fit: BoxFit.contain),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IconButton.filledTonal(
                        tooltip: '그림 빼기',
                        onPressed: () => setState(() => _image = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ])
                else
                  const Text('첨부한 그림이 없어요', style: TextStyle(color: AppColors.inkMuted)),
                if (p != null) ...[
                  const SizedBox(height: 20),
                  const Text('문제', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: ProblemBrief(problem: p, showAnswer: false, compact: true),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.wrong, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('ask-send'),
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size.fromHeight(56)),
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                  label: const Text('질문 보내기'),
                ),
              ],
            ),
    );
  }
}

// ───────────────────────────────────────────────────────────── handwriting

/// Write with the pen over a picture (the student's page) or over the problem, and get a PNG back.
class HandwriteScreen extends StatefulWidget {
  const HandwriteScreen({super.key, this.imagePath, this.image, this.problem});

  /// A question image on the server (needs the login token).
  final String? imagePath;

  /// A picture already on the tablet.
  final Uint8List? image;
  final Problem? problem;

  static Future<Uint8List?> open(BuildContext context, {String? imagePath, Uint8List? image, Problem? problem}) =>
      Navigator.of(context).push(MaterialPageRoute<Uint8List>(
          builder: (_) => HandwriteScreen(imagePath: imagePath, image: image, problem: problem)));

  @override
  State<HandwriteScreen> createState() => _HandwriteScreenState();
}

class _HandwriteScreenState extends State<HandwriteScreen> {
  late final InkController _ink;
  final GlobalKey _shot = GlobalKey();
  final GlobalKey<InkCanvasState> _canvas = GlobalKey<InkCanvasState>();
  final ExamSheetKeys _keys = ExamSheetKeys();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ink = InkController(settings: AppScope.read(context).ink);
  }

  @override
  void dispose() {
    final c = _ink;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  Future<void> _attach() async {
    setState(() => _busy = true);
    final png = await capturePng(_shot);
    if (!mounted) return;
    setState(() => _busy = false);
    if (png == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('그림을 만들지 못했어요')));
      return;
    }
    Navigator.of(context).pop(png);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final api = app.api;
    Widget? underlay;
    if (widget.image != null) {
      underlay = Padding(
        padding: const EdgeInsets.only(top: 90),
        child: Image.memory(widget.image!, width: 1000, fit: BoxFit.fitWidth),
      );
    } else if (widget.imagePath != null && api != null) {
      underlay = Padding(
        padding: const EdgeInsets.only(top: 90),
        child: AuthImage(api: api, path: widget.imagePath!, width: 1000),
      );
    } else if (widget.problem != null) {
      final p = widget.problem!;
      underlay = ProblemSheet(
        problem: p,
        number: 1,
        color: Color(app.bank.subject(p.subjectId)?.color ?? 0xFF5B6475),
        keys: _keys,
        serif: app.settings.examFont,
        passage: app.bank.passageOf(p),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('필기로 쓰기'),
        actions: [
          FilledButton.icon(
            key: const Key('ink-attach'),
            onPressed: _busy ? null : _attach,
            icon: const Icon(Icons.check_rounded),
            label: const Text('첨부하기'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _shot,
                child: InkCanvas(key: _canvas, controller: _ink, underlay: underlay),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: 12,
              child: InkToolbar(
                controller: _ink,
                onSettingsChanged: () => app.updateInk((_) {}),
                onResetView: () => _canvas.currentState?.resetView(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
