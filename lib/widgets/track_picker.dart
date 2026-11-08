import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/problem.dart';

/// 가입·온보딩의 "과정" 고르기. 대학생 · 취준 · 편입 (예전 가입자는 고른 고등 과정도 그대로 보인다).
/// '대학생' 을 고르면 아래에 학교 고르는 칸이 나오고, 고른 학교 이름이 학년 값이 된다 (목록에 없으면 '대학생').
class TrackPicker extends StatelessWidget {
  const TrackPicker({
    super.key,
    required this.grades,
    required this.onChanged,
    this.allowed,
    this.big = false,
    this.keyPrefix = 'grade',
  });

  /// 지금 고른 학년 값 (학교 이름 포함). 이 목록을 직접 고친 뒤 [onChanged] 를 부른다.
  final List<String> grades;
  final VoidCallback onChanged;

  /// 추천코드가 허용하는 학년 값 (null 이면 새 가입 과정 전부).
  final List<String>? allowed;
  final bool big;
  final String keyPrefix;

  List<String> get _schools {
    final a = allowed;
    if (a == null) return kUniversities;
    return [for (final u in kUniversities) if (a.contains(u)) u];
  }

  bool get _genericOk => allowed == null || allowed!.contains(kUnivGeneric);

  /// 테스트용: 고등 과정 칩도 보이게 (고등 교재로 된 옛 시험 자료를 쓰는 테스트).
  @visibleForTesting
  static bool showLegacyTracks = false;

  /// 칩으로 보일 과정: 학교들은 '대학생' 칩 하나로 묶는다.
  List<String> get _tracks {
    final base = allowed ?? (showLegacyTracks ? kGrades : kSignupTracks);
    final out = <String>[];
    void add(String g) {
      final t = isUniversity(g) ? kUnivGeneric : g;
      if (!out.contains(t)) out.add(t);
    }

    for (final g in base) {
      add(g);
    }
    // 예전에 고른 과정(고1·N수 …)은 계속 보여서 뺄 수 있게
    for (final g in grades) {
      add(g);
    }
    return out;
  }

  bool _selected(String t) => t == kUnivGeneric ? grades.any(isUniversity) : grades.contains(t);

  void _toggle(String t) {
    if (t == kUnivGeneric) {
      if (grades.any(isUniversity)) {
        grades.removeWhere(isUniversity);
      } else {
        final s = _schools;
        grades.add(s.length == 1 ? s.first : kUnivGeneric);
      }
    } else if (!grades.remove(t)) {
      grades.add(t);
    }
    onChanged();
  }

  void _pickSchool(String school) {
    final i = grades.indexWhere(isUniversity);
    if (i >= 0) {
      grades[i] = school;
    } else {
      grades.add(school);
    }
    grades.removeWhere((g) => isUniversity(g) && g != school);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final univ = grades.where(isUniversity).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: big ? 10 : 8, runSpacing: big ? 10 : 4, children: [
        for (final t in _tracks)
          if (big)
            _Big(
              key: Key('$keyPrefix-$t'),
              label: t,
              selected: _selected(t),
              onTap: () => _toggle(t),
            )
          else
            FilterChip(
              key: Key('$keyPrefix-$t'),
              label: Text(t),
              selected: _selected(t),
              onSelected: (_) => _toggle(t),
            ),
      ]),
      if (univ != null) ...[
        SizedBox(height: big ? 18 : 12),
        _SchoolField(
          key: Key('$keyPrefix-school'),
          value: univ,
          schools: _schools,
          allowGeneric: _genericOk,
          onPicked: _pickSchool,
        ),
      ],
    ]);
  }
}

class _SchoolField extends StatelessWidget {
  const _SchoolField(
      {super.key, required this.value, required this.schools, required this.allowGeneric, required this.onPicked});
  final String value;
  final List<String> schools;
  final bool allowGeneric;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final options = [...schools, if (allowGeneric) kUnivGeneric];
    final shown = value == kUnivGeneric ? '' : value;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('학교', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
      const SizedBox(height: 6),
      Autocomplete<String>(
        key: ValueKey('school-$value'),
        initialValue: TextEditingValue(text: shown),
        optionsBuilder: (v) {
          final q = v.text.trim();
          if (q.isEmpty) return options;
          return options.where((o) => o.toLowerCase().contains(q.toLowerCase()));
        },
        displayStringForOption: (o) => o == kUnivGeneric ? '목록에 없는 학교' : o,
        onSelected: onPicked,
        fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
          controller: ctrl,
          focusNode: focus,
          decoration: InputDecoration(
            hintText: '학교 이름을 입력하거나 고르세요',
            prefixIcon: const Icon(Icons.account_balance_rounded),
            helperText: value == kUnivGeneric
                ? (allowGeneric ? '목록에 없으면 "목록에 없는 학교"를 고르세요 (모든 대학 공통 교재가 보여요)' : '학교를 골라 주세요')
                : '$value 교재와 모든 대학 공통 교재가 보여요',
          ),
          onSubmitted: (t) {
            final hit = options.where((o) => o == t.trim()).firstOrNull;
            if (hit != null) onPicked(hit);
            onSubmit();
          },
        ),
      ),
    ]);
  }
}

class _Big extends StatelessWidget {
  const _Big({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 120,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.ink)),
        ),
      ),
    );
  }
}
