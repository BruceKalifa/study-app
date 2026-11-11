import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../ink/ink_controller.dart';
import '../services/handwriting.dart';
import '../services/live_sync.dart';
import '../widgets/common.dart';
import 'onboarding_screen.dart';
import '../widgets/update_dialog.dart' show UpdateTile;
import 'teacher_shell.dart' show AccountCard;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nick;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _nick = TextEditingController(text: AppScope.read(context).learner.nickname);
    }
  }

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final ink = app.ink;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 60),
      children: [
        const Text('설정', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
        const SizedBox(height: 22),

        // ---------------- account
        const AccountCard(),
        const SizedBox(height: 12),
        const Card(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4), child: UpdateTile())),
        const SizedBox(height: 28),

        // ---------------- profiles (로그인 없이 쓸 때만)
        if (!app.signedIn)
          _Section(title: '학생 프로필', subtitle: '한 태블릿을 여러 학생이 쓰면 프로필을 나눠 기록을 따로 관리해요', children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final p in app.profiles)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => app.switchProfile(p.id),
                      onLongPress:
                          app.profiles.length > 1 && p.id != app.profile.id ? () => _confirmDelete(app, p.id, p.name) : null,
                      child: Container(
                        width: 124,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: p.id == app.profile.id ? AppColors.highlightSoft : AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: p.id == app.profile.id ? AppColors.ink : AppColors.line,
                              width: p.id == app.profile.id ? 1.6 : 1),
                        ),
                        child: Column(children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: Color(p.color),
                            child: Text(p.name.isEmpty ? '?' : String.fromCharCode(p.name.runes.first),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                          ),
                          const SizedBox(height: 8),
                          Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (p.id == app.profile.id)
                            const Text('사용 중',
                                style: TextStyle(fontSize: 12, color: AppColors.inkSoft, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _prompt('새 학생 이름', '', (v) => app.addProfile(v)),
                    child: Container(
                      width: 124,
                      height: 108,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.lineStrong),
                      ),
                      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.person_add_alt_1_rounded, color: AppColors.inkSoft),
                        SizedBox(height: 6),
                        Text('학생 추가', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, children: [
                  TextButton.icon(
                    onPressed: () => _prompt('이름 바꾸기', app.profile.name, app.renameProfile),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text('"${app.profile.name}" 이름 바꾸기'),
                  ),
                  const Text('다른 프로필을 길게 누르면 삭제할 수 있어요',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
          ]),

        // ---------------- study
        _Section(title: '학교와 목표', subtitle: '오늘의 세트는 내 교재의 문제로 만들어져요', children: [
          _Row(
            title: '${app.learner.gradeLabel} · ${app.learner.goal} 목표',
            sub: app.myWorkbooks.isEmpty
                ? '내 교재가 비어 있어요'
                : '내 교재 ${app.myWorkbooks.length}권: ${app.myWorkbooks.map((w) => w.title).join(', ')}',
            trailing: OutlinedButton(
              key: const Key('edit-learner'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const OnboardingScreen(editing: true))),
              child: const Text('바꾸기'),
            ),
          ),
        ]),
        _Section(
          title: '커뮤니티와 공부시간 순위',
          subtitle: '글과 댓글에는 닉네임이, 순위에는 이름 첫 글자만(예: 오XX) 보여요',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    key: const Key('nickname'),
                    controller: _nick,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: '커뮤니티 닉네임',
                      hintText: '비워 두면 ${app.communityName}',
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                    onSubmitted: (v) => app.updateLearner((l) => l.nickname = v.trim()),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      app.updateLearner((l) => l.nickname = _nick.text.trim());
                    },
                    child: const Text('저장'),
                  ),
                ),
              ]),
            ),
            _switch('공부시간 순위에 참여', '켜면 오늘 공부시간이 가린 이름으로 순위에 올라가요', app.learner.rankingOptIn,
                (v) => app.updateLearner((l) => l.rankingOptIn = v)),
          ],
        ),
        _Section(title: '학습', children: [
          _Row(
            title: '하루 목표',
            sub: '오늘의 세트와 홈 진도에 쓰여요',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 240,
                child: Slider(
                  value: s.dailyGoal.toDouble().clamp(5.0, 40.0),
                  min: 5,
                  max: 40,
                  divisions: 7,
                  label: '${s.dailyGoal}문제',
                  onChanged: (v) => app.updateSettings((x) => x.dailyGoal = v.round()),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text('${s.dailyGoal}문제',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, fontFeatures: AppColors.tabular)),
              ),
            ]),
          ),
          _switch('풀이 시간 표시', '문제마다 타이머를 보여줘요', s.showTimer, (v) => app.updateSettings((x) => x.showTimer = v)),
          _switch('손글씨로 답 쓰기', '단답형은 문제 아래 답칸에 쓰면 자동 인식해요. 끄면 답칸을 눌러 키패드로 입력해요', s.handwritingAnswer,
              (v) => app.updateSettings((x) => x.handwritingAnswer = v)),
          _switch('정답이면 자동으로 다음 문제', null, s.autoAdvance, (v) => app.updateSettings((x) => x.autoAdvance = v)),
          _switch('전체화면으로 풀기', '문제와 필기 공간만 남겨요. 풀이 화면에서도 바로 켜고 끌 수 있어요', s.fullscreenSolve,
              (v) => app.updateSettings((x) => x.fullscreenSolve = v)),
          _switch('시험지 글꼴 (명조)', '문제를 시험지처럼 명조체로 보여줘요', s.examFont,
              (v) => app.updateSettings((x) => x.examFont = v)),
          if (app.isTeacher)
            _switch('출처·머리표 보기 (선생님)', '문항 옆의 출처·변형(원: …)·기출 표시를 앱에서도 봐요. 학생에게는 항상 안 보여요', s.showOrigin,
                (v) => app.updateSettings((x) => x.showOrigin = v)),
          ValueListenableBuilder<HandwritingStatus>(
            valueListenable: Handwriting.instance.status,
            builder: (context, st, _) => _Row(
              title: '필기 인식 모델',
              sub: switch (st) {
                HandwritingStatus.ready => '준비됨 · 기기 안에서 인식해요 (인터넷 불필요)',
                HandwritingStatus.downloading => '내려받는 중… (약 20MB, 처음 한 번)',
                HandwritingStatus.unavailable => '사용할 수 없음 · 인터넷 연결 후 다시 시도하세요',
                HandwritingStatus.unknown => '확인 전',
              },
              trailing: st == HandwritingStatus.ready
                  ? const Icon(Icons.check_circle_rounded, color: AppColors.correct)
                  : TextButton(onPressed: Handwriting.instance.prepare, child: const Text('준비하기')),
            ),
          ),
        ]),

        // ---------------- pen
        _Section(title: '펜과 필기', subtitle: 'S펜 옆 버튼을 누른 채로 쓰면 지우개, 떼면 원래 펜으로 돌아와요', children: [
          _switch('손가락으로 쓰기', '끄면 손가락은 화면 이동·확대만 해요 (손바닥 인식 방지)', ink.fingerDraws,
              (v) => app.updateInk((x) => x.fingerDraws = v)),
          _switch('필압 사용', '누르는 힘에 따라 굵기가 달라져요', ink.pressure, (v) => app.updateInk((x) => x.pressure = v)),
          _switch('멈추면 도형으로', '선·원·삼각형·사각형을 그린 뒤 펜을 떼지 않고 잠시 멈추면 반듯하게 바꿔줘요. 그냥 떼면 손글씨 그대로예요',
              ink.holdToStraighten, (v) => app.updateInk((x) => x.holdToStraighten = v)),
          _switch('원·삼각형·사각형도 맞추기', '끄면 멈췄을 때 직선만 맞춰요', ink.shapeSnap,
              (v) => app.updateInk((x) => x.shapeSnap = v)),
          _switch('두 손가락 탭으로 실행 취소', '세 손가락 탭은 다시 실행', ink.twoFingerUndo,
              (v) => app.updateInk((x) => x.twoFingerUndo = v)),
          _Row(
            title: '기본 종이',
            trailing: SegmentedButton<PaperStyle>(
              segments: const [
                ButtonSegment(value: PaperStyle.blank, label: Text('무지')),
                ButtonSegment(value: PaperStyle.lines, label: Text('줄')),
                ButtonSegment(value: PaperStyle.grid, label: Text('모눈')),
                ButtonSegment(value: PaperStyle.dots, label: Text('점')),
              ],
              selected: {ink.paper},
              onSelectionChanged: (v) => app.updateInk((x) => x.paper = v.first),
            ),
          ),
          _Row(
            title: '지우개',
            trailing: SegmentedButton<EraserMode>(
              segments: const [
                ButtonSegment(value: EraserMode.stroke, label: Text('획 단위')),
                ButtonSegment(value: EraserMode.area, label: Text('부분')),
              ],
              selected: {ink.eraserMode},
              onSelectionChanged: (v) => app.updateInk((x) => x.eraserMode = v.first),
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 18), child: _PenCheck()),
        ]),

        // ---------------- live
        _Section(
          title: '선생님과 실시간 공유',
          children: [
            _switch('실시간 공유 켜기', '켜 두면 문제를 풀 때 필기가 선생님 화면에 바로 보여요', s.liveEnabled,
                (v) => app.updateSettings((x) => x.liveEnabled = v)),
            if (app.live != null)
              ValueListenableBuilder<LiveStatus>(
                valueListenable: app.live!.status,
                builder: (context, st, _) {
                  final (label, color) = switch (st) {
                    LiveStatus.online => ('연결됨 · 선생님 화면에 공유 중', AppColors.correct),
                    LiveStatus.connecting => ('연결 중…', AppColors.review),
                    LiveStatus.error => ('연결 실패 · 같은 와이파이인지 확인하세요 (자동 재시도 중)', AppColors.wrong),
                    LiveStatus.off => ('꺼짐', AppColors.inkMuted),
                  };
                  return _Row(
                    title: '연결 상태',
                    trailing: Pill(label, color: color, icon: Icons.podcasts_rounded),
                  );
                },
              ),
          ],
        ),

        // ---------------- content
        _Section(
          title: '교재 업데이트',
          children: [
            _Row(
              title: '새로 나온 교재와 고친 문항 받기',
              sub: app.syncMessage.isEmpty
                  ? '지금 과목 ${app.bank.subjects.length}개, 문항 ${app.bank.all.length}개가 들어 있어요'
                  : app.syncMessage,
              trailing: FilledButton.icon(
                key: const Key('sync-content'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: app.syncing
                    ? null
                    : () async {
                        final r = await app.syncContent();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message)));
                        }
                      },
                icon: app.syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download_rounded),
                label: const Text('업데이트 받기'),
              ),
            ),
          ],
        ),

        // ---------------- data
        _Section(title: '데이터', children: [
          _Row(
            title: '${app.profile.name}님의 기록',
            sub: '풀이 기록 ${app.totalSolved}개, 오답노트 ${app.wrongNote.length}개',
            trailing: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.wrong,
                side: const BorderSide(color: AppColors.wrongSoft),
                minimumSize: const Size(0, 44),
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('기록을 모두 지울까요?'),
                    content: Text('${app.profile.name}님의 풀이 기록, 오답노트, 필기가 모두 삭제돼요. 되돌릴 수 없어요.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.wrong),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('모두 지우기'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await app.resetRecords();
              },
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('이 프로필의 기록 초기화'),
            ),
          ),
        ]),

        _Section(title: '사용 팁', children: const [
          _Tip(Icons.edit_rounded, 'S펜으로 쓰고, 손가락 한 개로 화면 이동, 두 개로 확대/축소해요.'),
          _Tip(Icons.auto_fix_normal_rounded, 'S펜 옆 버튼을 누른 채로 문지르면 지우개, 떼면 바로 펜으로 돌아와요.'),
          _Tip(Icons.touch_app_rounded, '두 손가락으로 톡 치면 실행 취소, 세 손가락이면 다시 실행.'),
          _Tip(Icons.straighten_rounded, '선을 긋고 잠깐 멈추면 반듯한 직선이 돼요. 그래프·벡터 그릴 때 편해요.'),
          _Tip(Icons.gesture_rounded, '올가미로 필기를 둘러싸면 옮기기·복제·색 바꾸기를 할 수 있어요.'),
          _Tip(Icons.auto_awesome_rounded, '틀린 문제는 숫자를 바꾼 변형문제로 다시 풀어 보세요.'),
        ]),
        const SizedBox(height: 4),
        const Center(
          child: Text('Solvit 0.1 · 오픈소스 · 글꼴 Pretendard (SIL OFL)',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        ),
      ],
    );
  }

  Widget _switch(String title, String? sub, bool v, ValueChanged<bool> on) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          subtitle: sub == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.45)),
                ),
          value: v,
          onChanged: on,
        ),
      );

  void _prompt(String title, String initial, Future<void> Function(String) onOk) {
    final c = TextEditingController(text: initial);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 360, child: TextField(controller: c, autofocus: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onOk(c.text);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(AppState app, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"$name" 프로필을 삭제할까요?'),
        content: const Text('이 학생의 기록이 모두 삭제돼요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.wrong),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) await app.deleteProfile(id);
  }
}

/// 설정 묶음: 제목은 종이 위에, 항목들은 흰 판 한 장 안에 구분선으로.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: SectionHeader(title, subtitle: subtitle),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
              children[i],
            ],
          ]),
        ),
      ]),
    );
  }
}

/// 설정 한 줄: 제목 (+ 설명) 과 오른쪽 조작. 높이는 60 이상.
class _Row extends StatelessWidget {
  const _Row({required this.title, this.sub, this.trailing});
  final String title;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(sub!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.45)),
                ),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ]),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.inkSoft),
        const SizedBox(width: 14),
        Expanded(child: Text(text, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500, height: 1.45))),
      ]),
    );
  }
}

/// Touch the box with the S Pen (with and without the side button) to see what the app receives.
class _PenCheck extends StatefulWidget {
  const _PenCheck();

  @override
  State<_PenCheck> createState() => _PenCheckState();
}

class _PenCheckState extends State<_PenCheck> {
  String _info = 'S펜으로 여기를 눌러 보세요 · 옆 버튼을 누른 채로도 눌러 보세요';
  bool? _eraser;

  void _show(PointerEvent e) {
    final stylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    final eraser = e.kind == PointerDeviceKind.invertedStylus ||
        (stylus && (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) != 0);
    final kind = switch (e.kind) {
      PointerDeviceKind.stylus => 'S펜',
      PointerDeviceKind.invertedStylus => 'S펜(지우개 끝)',
      PointerDeviceKind.touch => '손가락',
      PointerDeviceKind.mouse => '마우스',
      _ => '${e.kind.name}',
    };
    final p = e.pressureMax > e.pressureMin ? (e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin) : e.pressure;
    setState(() {
      _eraser = stylus ? eraser : null;
      _info = '$kind · 버튼 값 ${e.buttons} · 필압 ${(p * 100).round()}% · 접촉 크기 ${e.radiusMajor.toStringAsFixed(1)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = _eraser;
    return Listener(
      onPointerDown: _show,
      onPointerMove: _show,
      child: Container(
        height: 96,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: e == true ? AppColors.highlightSoft : AppColors.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: e == true ? AppColors.ink : AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Icon(e == true ? Icons.auto_fix_normal_rounded : Icons.edit_rounded,
                color: AppColors.ink, size: 20),
            const SizedBox(width: 8),
            Text(
              e == null ? 'S펜 점검' : (e ? '지우개로 인식됨 ✓' : '펜으로 인식됨'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ]),
          const SizedBox(height: 6),
          Text(_info, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
        ]),
      ),
    );
  }
}
