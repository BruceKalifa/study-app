import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../ink/ink_controller.dart';
import '../services/handwriting.dart';
import '../services/live_sync.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _url;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _url = TextEditingController(text: AppScope.read(context).settings.serverUrl);
    }
  }

  @override
  void dispose() {
    _url.dispose();
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
        const Text('설정', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
        const SizedBox(height: 20),

        // ---------------- profiles
        _Section(title: '학생 프로필', subtitle: '한 태블릿을 여러 학생이 쓰면 프로필을 나눠 기록을 따로 관리해요', children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final p in app.profiles)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => app.switchProfile(p.id),
                onLongPress: app.profiles.length > 1 && p.id != app.profile.id ? () => _confirmDelete(app, p.id, p.name) : null,
                child: Container(
                  width: 130,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.id == app.profile.id ? Color(p.color).withValues(alpha: 0.10) : AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: p.id == app.profile.id ? Color(p.color) : AppColors.line, width: p.id == app.profile.id ? 2 : 1),
                  ),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(p.color),
                      child: Text(p.name.isEmpty ? '?' : String.fromCharCode(p.name.runes.first),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                    ),
                    const SizedBox(height: 8),
                    Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (p.id == app.profile.id)
                      const Text('사용 중', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  ]),
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _prompt('새 학생 이름', '', (v) => app.addProfile(v)),
              child: Container(
                width: 130,
                height: 112,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
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
          const SizedBox(height: 10),
          Row(children: [
            TextButton.icon(
              onPressed: () => _prompt('이름 바꾸기', app.profile.name, app.renameProfile),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text('"${app.profile.name}" 이름 바꾸기'),
            ),
            const Spacer(),
            const Text('다른 프로필을 길게 누르면 삭제할 수 있어요', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ]),
        ]),

        // ---------------- study
        _Section(title: '학습', children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('하루 목표', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Slider(
              value: s.dailyGoal.toDouble().clamp(5.0, 40.0),
              min: 5,
              max: 40,
              divisions: 7,
              label: '${s.dailyGoal}문제',
              onChanged: (v) => app.updateSettings((x) => x.dailyGoal = v.round()),
            ),
            trailing: Text('${s.dailyGoal}문제', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          _switch('풀이 시간 표시', '문제마다 타이머를 보여줘요', s.showTimer, (v) => app.updateSettings((x) => x.showTimer = v)),
          _switch('손글씨로 답 쓰기', '단답형 답을 손으로 쓰면 자동 인식해요 (끄면 키패드)', s.handwritingAnswer,
              (v) => app.updateSettings((x) => x.handwritingAnswer = v)),
          _switch('정답이면 자동으로 다음 문제', null, s.autoAdvance, (v) => app.updateSettings((x) => x.autoAdvance = v)),
          ValueListenableBuilder<HandwritingStatus>(
            valueListenable: Handwriting.instance.status,
            builder: (context, st, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('필기 인식 모델', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(switch (st) {
                HandwritingStatus.ready => '준비됨 · 기기 안에서 인식해요 (인터넷 불필요)',
                HandwritingStatus.downloading => '내려받는 중… (약 20MB, 처음 한 번)',
                HandwritingStatus.unavailable => '사용할 수 없음 · 인터넷 연결 후 다시 시도하세요',
                HandwritingStatus.unknown => '확인 전',
              }),
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
          _switch('멈추면 직선으로', '선을 긋고 잠시 멈추면 반듯한 직선으로 바꿔줘요', ink.holdToStraighten,
              (v) => app.updateInk((x) => x.holdToStraighten = v)),
          _switch('두 손가락 탭으로 실행 취소', '세 손가락 탭은 다시 실행', ink.twoFingerUndo,
              (v) => app.updateInk((x) => x.twoFingerUndo = v)),
          const SizedBox(height: 8),
          Row(children: [
            const Text('기본 종이', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            SegmentedButton<PaperStyle>(
              segments: const [
                ButtonSegment(value: PaperStyle.blank, label: Text('무지')),
                ButtonSegment(value: PaperStyle.lines, label: Text('줄')),
                ButtonSegment(value: PaperStyle.grid, label: Text('모눈')),
                ButtonSegment(value: PaperStyle.dots, label: Text('점')),
              ],
              selected: {ink.paper},
              onSelectionChanged: (v) => app.updateInk((x) => x.paper = v.first),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Text('지우개', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            SegmentedButton<EraserMode>(
              segments: const [
                ButtonSegment(value: EraserMode.stroke, label: Text('획 단위')),
                ButtonSegment(value: EraserMode.area, label: Text('부분')),
              ],
              selected: {ink.eraserMode},
              onSelectionChanged: (v) => app.updateInk((x) => x.eraserMode = v.first),
            ),
          ]),
          const SizedBox(height: 16),
          const _PenCheck(),
        ]),

        // ---------------- live
        _Section(
          title: '선생님과 실시간 공유',
          subtitle: '선생님 PC에서 풀이노트 서버를 켜고, 화면에 나온 주소를 아래에 입력하세요',
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: '서버 주소',
                    hintText: 'ws://192.168.0.12:8080/ws',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  onSubmitted: (v) => app.updateSettings((x) => x.serverUrl = v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  app.updateSettings((x) {
                    x.serverUrl = _url.text.trim();
                    x.liveEnabled = _url.text.trim().isNotEmpty;
                  });
                },
                child: const Text('연결'),
              ),
            ]),
            const SizedBox(height: 8),
            _switch('실시간 공유 켜기', '켜 두면 문제를 풀 때 필기가 선생님 화면에 바로 보여요', s.liveEnabled,
                (v) => app.updateSettings((x) => x.liveEnabled = v)),
            if (app.live != null)
              ValueListenableBuilder<LiveStatus>(
                valueListenable: app.live!.status,
                builder: (context, st, _) {
                  final (label, color) = switch (st) {
                    LiveStatus.online => ('연결됨 · 선생님 화면에 공유 중', AppColors.correct),
                    LiveStatus.connecting => ('연결 중…', AppColors.review),
                    LiveStatus.error => ('연결 실패 · 주소와 같은 와이파이인지 확인하세요 (자동 재시도 중)', AppColors.wrong),
                    LiveStatus.off => ('꺼짐', AppColors.inkMuted),
                  };
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Pill(label, color: color, icon: Icons.podcasts_rounded),
                  );
                },
              ),
          ],
        ),

        // ---------------- data
        _Section(title: '데이터', children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('문제 ${app.bank.all.length}개 · 변형 가능 ${app.bank.all.where((p) => p.hasTemplate).length}개'),
            subtitle: Text('${app.profile.name}님의 기록 ${app.totalSolved}개 · 오답노트 ${app.wrongNote.length}개'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.wrong),
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
        const Center(
          child: Text('풀이노트 0.1 · 오픈소스 · 글꼴 Pretendard (SIL OFL)',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        ),
      ],
    );
  }

  Widget _switch(String title, String? sub, bool v, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: sub == null ? null : Text(sub),
        value: v,
        onChanged: on,
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

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title, subtitle: subtitle),
            ...children,
          ]),
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500))),
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
          color: e == true ? AppColors.accentSoft : AppColors.paper,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: e == true ? AppColors.accent : AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Icon(e == true ? Icons.auto_fix_normal_rounded : Icons.edit_rounded,
                color: e == true ? AppColors.accent : AppColors.ink, size: 20),
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
