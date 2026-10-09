/// 학년·과정별 학습 목표 목록 — 온보딩의 "목표가 무엇인가요?" 가 고른 과정에 따라 다르게 나온다.
library;

import 'package:flutter/material.dart';

class GoalOption {
  const GoalOption(this.label, this.icon, this.desc, {this.exam = '', this.suneung = false});

  /// 화면·저장에 쓰는 이름 (Learner.goals 에 그대로 들어간다)
  final String label;
  final IconData icon;
  final String desc;

  /// 이 목표를 고르면 D-day 카드에 처음 띄울 시험 이름 ('' = 정하지 않음)
  final String exam;

  /// true 면 D-day 날짜를 수능으로 미리 채운다 (그 밖의 시험은 날짜를 직접 정한다)
  final bool suneung;
}

const _suneung = GoalOption('수능', Icons.flag_rounded, '수능 D-day에 맞춰 실전 감각과 약점 유형을 관리해요',
    exam: '수능', suneung: true);
const _naesin = GoalOption('내신', Icons.school_rounded, '학교 진도에 맞춰 단원별로 다지고 시험 기간을 대비해요', exam: '기말고사');
const _mock = GoalOption('모의고사·학평', Icons.assignment_rounded, '학력평가와 모의평가 형식으로 실전 감각을 길러요', exam: '모의고사');
const _concept = GoalOption('개념 다지기', Icons.foundation_rounded, '빠진 개념을 메우고 기본 문제부터 차근차근 풀어요');
const _weak = GoalOption('약점 유형 보완', Icons.build_circle_rounded, '자주 틀리는 유형을 찾아 변형 문제로 집중해서 풀어요');

/// 과정(학년) 하나에 맞는 목표들 — 위에 있을수록 먼저 권한다.
const Map<String, List<GoalOption>> goalsByGrade = {
  '고1': [
    _naesin,
    GoalOption('선행 학습', Icons.trending_up_rounded, '다음 학기·학년 과정을 미리 개념부터 쌓아요'),
    _concept,
    _mock,
    _suneung,
  ],
  '고2': [
    _naesin,
    _mock,
    _suneung,
    GoalOption('선행 학습', Icons.trending_up_rounded, '다음 학기·학년 과정을 미리 개념부터 쌓아요'),
    _concept,
  ],
  '고3': [
    _suneung,
    GoalOption('내신 마무리', Icons.school_rounded, '학교 시험과 학생부를 챙기면서 수능과 병행해요', exam: '기말고사'),
    GoalOption('6·9월 모의평가', Icons.event_available_rounded, '6월·9월 모의평가를 목표로 실전 감각을 올려요', exam: '9월 모의평가'),
    GoalOption('수시 준비', Icons.edit_document, '수능 최저와 내신을 함께 챙겨요'),
    GoalOption('정시 준비', Icons.rocket_launch_rounded, '수능 한 번에 집중해서 점수를 끌어올려요', exam: '수능', suneung: true),
    _weak,
  ],
  'N수': [
    _suneung,
    GoalOption('6·9월 모의평가', Icons.event_available_rounded, '6월·9월 모의평가를 목표로 실전 감각을 올려요', exam: '9월 모의평가'),
    _weak,
    GoalOption('킬러 문항 도전', Icons.bolt_rounded, '최상위권 변별 문항을 풀어 보며 한계를 넘어요'),
    GoalOption('개념 완성', Icons.foundation_rounded, '1년 동안 개념을 처음부터 다시 완성해요'),
    GoalOption('정시 준비', Icons.rocket_launch_rounded, '수능 한 번에 집중해서 점수를 끌어올려요', exam: '수능', suneung: true),
  ],
  '취준': [
    GoalOption('인적성 실전 대비', Icons.fact_check_rounded, 'GSAT·SKCT 같은 실전 모의고사로 시험 감각을 길러요', exam: '인적성'),
    GoalOption('NCS 대비', Icons.business_center_rounded, '공기업 직업기초능력평가 유형을 익혀요', exam: 'NCS'),
    GoalOption('영역별 약점 보완', Icons.build_circle_rounded, '언어·수리·추리·자료해석 중 약한 영역을 집중해서 풀어요'),
    GoalOption('시간 단축 연습', Icons.timer_rounded, '문항당 풀이 시간을 줄여 시험 시간 안에 끝내요'),
  ],
  '한양대': [
    GoalOption('중간고사 대비', Icons.edit_calendar_rounded, '중간고사 범위를 단원별로 정리하고 기출 유형을 풀어요', exam: '중간고사'),
    GoalOption('기말고사 대비', Icons.edit_calendar_rounded, '기말고사 파이널 자료로 시험 직전까지 정리해요', exam: '기말고사'),
    GoalOption('전공 기초 다지기', Icons.functions_rounded, '공업수학·미적분학 기본 개념과 계산력을 쌓아요'),
    GoalOption('학점 올리기', Icons.trending_up_rounded, '재수강·학점 관리를 위해 약한 단원을 보완해요'),
  ],
  '편입': [
    GoalOption('편입시험 대비', Icons.flag_rounded, '지원 대학 시험일에 맞춰 실전 감각과 약점을 관리해요', exam: '편입시험'),
    GoalOption('대학별 기출 풀이', Icons.history_edu_rounded, '지원 대학 기출 유형을 반복해서 익혀요'),
    GoalOption('편입수학 기초', Icons.functions_rounded, '미적분·선형대수 기본 개념부터 다시 잡아요'),
    _weak,
  ],
};

/// 고른 과정들에 보여 줄 목표 묶음: (과정 이름, 그 과정의 목표들). 다른 과정에서 이미 나온 목표는 한 번만 보인다.
List<(String, List<GoalOption>)> goalSections(List<String> grades) {
  final seen = <String>{};
  final out = <(String, List<GoalOption>)>[];
  for (final g in grades) {
    final fresh = [
      for (final o in goalsByGrade[g] ?? const <GoalOption>[])
        if (seen.add(o.label)) o,
    ];
    if (fresh.isNotEmpty) out.add((g, fresh));
  }
  return out;
}

/// 고른 과정들에서 고를 수 있는 목표 이름 전부 (위에서부터 순서대로).
List<String> goalLabels(List<String> grades) => [
      for (final s in goalSections(grades)) ...[for (final o in s.$2) o.label]
    ];

GoalOption? goalOption(String label) {
  for (final list in goalsByGrade.values) {
    for (final o in list) {
      if (o.label == label) return o;
    }
  }
  return null;
}

/// 저장된 목표 문자열("수능 · 내신", 옛 값 "둘 다") → 목록.
List<String> parseGoals(String goal) {
  final g = goal.trim();
  if (g.isEmpty) return const [];
  if (g == '둘 다') return const ['수능', '내신'];
  // 구분자는 공백 있는 " · " — 목표 이름 안의 "6·9월", "모의고사·학평" 은 쪼개지 않는다.
  return [
    for (final p in g.split(' · '))
      if (p.trim().isNotEmpty) p.trim()
  ];
}

/// 커뮤니티에서 이름 옆에 보이는 신분 한 칸 ("한양대" → "한양대생", "N수" → "N수생").
String identityOf(String grade) {
  switch (grade) {
    case 'N수':
      return 'N수생';
    case '취준':
      return '취준생';
    case '한양대':
      return '한양대생';
    case '편입':
      return '편입생';
    default:
      return grade;
  }
}

/// 가입할 때 고른 과정으로 만든 신분 글자: "고3", "한양대생 · N수생" (최대 3개).
String identityLabel(Iterable<String> grades) {
  final l = <String>[];
  for (final g in grades) {
    final x = identityOf(g.trim());
    if (x.isNotEmpty && !l.contains(x)) l.add(x);
  }
  return l.take(3).join(' · ');
}
