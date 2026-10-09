import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../services/account_api.dart';

/// 첫 화면: 학생 / 선생님 → 로그인 · 회원가입 (또는 로그인 없이 쓰기).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String? _role; // student | teacher
  bool _signup = false;
  bool _busy = false;
  String? _error;
  /// 고른 학년·과정 (복수 선택, 고른 순서대로 — 첫 번째가 대표)
  final List<String> _grades = [];
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    for (final c in [_id, _pw, _pw2, _name, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final app = AppScope.read(context);
    const server = kDefaultServer; // 주소를 물어보지 않는다 (lib/app/theme.dart)
    String? err;
    if (_id.text.trim().isEmpty || _pw.text.isEmpty) {
      err = '아이디와 비밀번호를 입력하세요';
    } else if (_signup && _name.text.trim().isEmpty) {
      err = '이름을 입력하세요';
    } else if (_signup && _pw.text != _pw2.text) {
      err = '비밀번호 확인이 맞지 않아요';
    } else if (_signup && _role == 'teacher' && _code.text.trim().isEmpty) {
      err = '승인 코드를 입력하세요';
    } else if (_signup && _role == 'student' && _grades.isEmpty) {
      err = '학년·과정을 하나 이상 골라 주세요';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signup) {
        await app.signup(
          server: server,
          role: _role!,
          loginId: _id.text,
          password: _pw.text,
          name: _name.text,
          grade: _role == 'student' ? (_grades.firstOrNull ?? '') : '',
          grades: _role == 'student' ? List<String>.of(_grades) : const <String>[],
          teacherCode: _role == 'teacher' ? _code.text : '',
        );
      } else {
        await app.login(server: server, loginId: _id.text, password: _pw.text);
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x1A1B2A4A), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: _role == null ? _rolePicker() : _form(),
      ),
    );

    final hero = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.draw_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 14),
        const Text(kAppName, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
      ]),
      const SizedBox(height: 28),
      const Text('시험지처럼 풀고,\n틀린 문제는 변형으로\n다시 만나요',
          style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white, height: 1.25, letterSpacing: -1.6)),
      const SizedBox(height: 18),
      Text('내가 고른 문제집 · 매일 오답 변형 세트 · 선생님께 1:1 질문',
          style: TextStyle(fontSize: 17, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w600)),
    ]);

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: wide
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(child: hero),
                      const SizedBox(width: 40),
                      Flexible(child: card),
                    ]),
                  )
                : Column(children: [hero, const SizedBox(height: 32), card]),
          ),
        ),
      ),
    );
  }

  Widget _rolePicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Text('어떻게 쓰실 건가요?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
      const SizedBox(height: 18),
      _RoleCard(
        key: const Key('welcome-student'),
        icon: Icons.school_rounded,
        title: '학생',
        desc: '문제집을 골라 풀고, 오답을 관리하고, 선생님께 질문해요',
        color: AppColors.blue,
        onTap: () => setState(() {
          _role = 'student';
          _error = null;
        }),
      ),
      const SizedBox(height: 12),
      _RoleCard(
        key: const Key('welcome-teacher'),
        icon: Icons.co_present_rounded,
        title: '선생님',
        desc: '학생이 무엇을 틀렸는지 보고, 질문에 글이나 필기로 답해요',
        color: AppColors.correct,
        onTap: () => setState(() {
          _role = 'teacher';
          _error = null;
        }),
      ),
      const SizedBox(height: 18),
      TextButton(
        key: const Key('welcome-offline'),
        onPressed: () => AppScope.read(context).useOffline(),
        child: const Text('로그인 없이 써 보기 · 기록은 이 기기에만 저장돼요'),
      ),
    ]);
  }

  Widget _form() {
    final teacher = _role == 'teacher';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        IconButton(
          key: const Key('welcome-back'),
          onPressed: _busy ? null : () => setState(() => _role = null),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        Text(teacher ? '선생님' : '학생', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
      ]),
      const SizedBox(height: 14),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('로그인', key: Key('auth-tab-login'))),
          ButtonSegment(value: true, label: Text('회원가입', key: Key('auth-tab-signup'))),
        ],
        selected: {_signup},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() {
          _signup = s.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 18),
      if (_signup) ...[
        TextField(
          key: const Key('auth-name'),
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: teacher ? '이름 (학생에게 보여요)' : '이름', prefixIcon: const Icon(Icons.badge_outlined)),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        key: const Key('auth-id'),
        controller: _id,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: '아이디',
          helperText: _signup ? '영문 소문자·숫자 4~20자' : null,
          prefixIcon: const Icon(Icons.person_outline_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('auth-pw'),
        controller: _pw,
        obscureText: true,
        textInputAction: _signup ? TextInputAction.next : TextInputAction.done,
        onSubmitted: _signup ? null : (_) => _submit(),
        decoration: InputDecoration(
          labelText: '비밀번호',
          helperText: _signup ? '6자 이상' : null,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
        ),
      ),
      if (_signup) ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('auth-pw2'),
          controller: _pw2,
          obscureText: true,
          decoration: const InputDecoration(labelText: '비밀번호 확인', prefixIcon: Icon(Icons.lock_outline_rounded)),
        ),
        if (teacher) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('auth-teacher-code'),
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '승인 코드',
              helperText: '정식 출시 전에는 승인받은 선생님만 가입할 수 있어요',
              prefixIcon: Icon(Icons.verified_user_outlined),
            ),
          ),
        ],
        if (!teacher) ...[
          const SizedBox(height: 16),
          const Text('학년·과정', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
          const SizedBox(height: 4),
          const Text('여러 개 골라도 돼요 (예: 한양대 + N수 + 편입)',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in kGrades)
              FilterChip(
                key: Key('auth-grade-$g'),
                label: Text(g),
                selected: _grades.contains(g),
                onSelected: (on) => setState(() {
                  if (on) {
                    _grades.add(g);
                  } else {
                    _grades.remove(g);
                  }
                }),
              ),
          ]),
        ],
      ],
      const SizedBox(height: 10),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          key: const Key('auth-error'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.wrongSoft, borderRadius: BorderRadius.circular(12)),
          child: Text(_error!, style: const TextStyle(color: AppColors.wrong, fontWeight: FontWeight.w700)),
        ),
      ],
      const SizedBox(height: 18),
      FilledButton(
        key: const Key('auth-submit'),
        onPressed: _busy ? null : _submit,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: teacher ? AppColors.correct : AppColors.blue,
        ),
        child: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(_signup ? '가입하고 시작하기' : '로그인', style: const TextStyle(fontSize: 17)),
      ),
      if (!_signup) ...[
        const SizedBox(height: 8),
        const Text('비밀번호를 잊었으면 선생님(관리자)께 문의하세요.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
      ],
    ]);
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard(
      {super.key, required this.icon, required this.title, required this.desc, required this.color, required this.onTap});
  final IconData icon;
  final String title, desc;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(desc, style: const TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.35)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ]),
        ),
      ),
    );
  }
}
