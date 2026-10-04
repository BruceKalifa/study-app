import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';

/// 구독: 무제한 문항 · 매일 오답 변형 세트 · 학습관리. 결제는 출시 때 스토어 결제로 연결.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final total = app.bank.all.length;
    final twins = [for (final s in app.bank.subjects) ...s.twins].length;
    final courses = app.bank.subjects.where((s) => s.group.isNotEmpty).length;
    final groups = {for (final s in app.bank.subjects) if (s.group.isNotEmpty) s.group}.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xFF1B2A4A), Color(0xFF3A2A5E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.workspace_premium_rounded, color: AppColors.accent, size: 28),
                  const SizedBox(width: 10),
                  Text(app.subscribed ? '구독 중' : '무료 체험 ${app.trialDaysLeft}일 남음',
                      style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
                const SizedBox(height: 12),
                const Text('고퀄리티 문항을\n한 달 구독으로 무제한',
                    style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1.2)),
                const SizedBox(height: 12),
                Text('국어·수학·영어·사회·과학, 고1부터 N수까지. 매일 오답으로 만든 변형 세트와 학습관리까지 한 번에.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 16, height: 1.5)),
              ]),
            ),
            const SizedBox(width: 24),
            Wrap(direction: Axis.vertical, spacing: 10, children: [
              _Stat('$total', '문항'),
              _Stat('$courses', '과목 · $groups개 교과'),
              _Stat('$twins', '쌍둥이 변형'),
            ]),
          ]),
        ),
        const SizedBox(height: 26),
        const Text('구독하면', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 14, children: const [
          _Benefit(Icons.all_inclusive_rounded, '문항 무제한', '모든 과목의 문제집과 무한 풀기를 제한 없이'),
          _Benefit(Icons.auto_awesome_rounded, '매일 오답 변형 세트', '어제 틀린 문제의 쌍둥이·변형 문항이 매일 도착'),
          _Benefit(Icons.draw_rounded, '시험지 그대로 필기', 'S펜·애플펜슬로 시험지 위에 바로 풀고 자동 채점'),
          _Benefit(Icons.insights_rounded, '학습관리', 'D-day, 순공 시간, 모의고사 등급 추이, 주간 리포트'),
          _Benefit(Icons.update_rounded, '새 문항 계속 추가', '매주 새 문항과 문제집이 업데이트돼요'),
        ]),
        const SizedBox(height: 28),
        const Text('요금제', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('표시된 가격은 예시예요. 결제는 출시 때 구글 플레이 · 앱스토어 정기결제로 연결돼요.',
            style: TextStyle(color: AppColors.inkMuted)),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 16, children: [
          _Plan(
            id: 'monthly',
            title: '월간 구독',
            price: '월 19,900원',
            note: '언제든 해지',
            current: app.learner.plan == 'monthly',
          ),
          _Plan(
            id: 'yearly',
            title: '연간 구독',
            price: '월 14,900원',
            note: '연 178,800원 · 25% 할인',
            best: true,
            current: app.learner.plan == 'yearly',
          ),
        ]),
        if (app.subscribed) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: app.cancelSubscription, child: const Text('구독 해지 (테스트)')),
          ),
        ],
        const SizedBox(height: 28),
        const Text('담겨 있는 과목', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final g in SubjectGroup.all)
          if (app.bank.inGroup(g.id).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 56,
                  child: Text(g.name, style: TextStyle(fontWeight: FontWeight.w800, color: Color(g.color), fontSize: 16)),
                ),
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in app.bank.inGroup(g.id))
                      Chip(label: Text('${s.name} · ${s.problems.length}')),
                  ]),
                ),
              ]),
            ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Flexible(child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w700))),
        ]),
      );
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.title, this.desc);
  final IconData icon;
  final String title, desc;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 300,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5, height: 1.4)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _Plan extends StatelessWidget {
  const _Plan({required this.id, required this.title, required this.price, required this.note, this.best = false, this.current = false});
  final String id, title, price, note;
  final bool best, current;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return Container(
      width: 340,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: best ? AppColors.accent : AppColors.line, width: best ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (best)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
              child: const Text('추천', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
        ]),
        const SizedBox(height: 10),
        Text(price, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1)),
        Text(note, style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: Key('plan-$id'),
            style: FilledButton.styleFrom(
              backgroundColor: current ? AppColors.correct : (best ? AppColors.accent : AppColors.ink),
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: current
                ? null
                : () {
                    app.subscribe(id);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('지금은 테스트 구독이에요. 출시 때 스토어 결제로 연결돼요.')));
                  },
            child: Text(current ? '이용 중' : '구독하기'),
          ),
        ),
      ]),
    );
  }
}
