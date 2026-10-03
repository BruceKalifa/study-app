import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../core/problem_bank.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'solve_screen.dart';

/// 내 문제: teachers/students add their own problems (with LaTeX preview).
class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.customProblems;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('내 문제', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
              SizedBox(height: 4),
              Text('직접 문제를 만들면 문제집·채점·오답노트에 그대로 들어가요. 수식은 \$ 사이에 LaTeX로 써요.',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 15)),
            ]),
          ),
          if (list.isNotEmpty) ...[
            OutlinedButton.icon(
              onPressed: () => SolveScreen.open(context, title: '내 문제', problems: list),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('모두 풀기'),
            ),
            const SizedBox(width: 10),
          ],
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProblemEditor())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('새 문제'),
          ),
        ]),
        const SizedBox(height: 20),
        if (list.isEmpty)
          EmptyState(
            icon: Icons.edit_note_rounded,
            title: '아직 만든 문제가 없어요',
            message: '수업에서 나온 문제나 틀리기 쉬운 문제를 직접 등록해 보세요.',
            action: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProblemEditor())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('첫 문제 만들기'),
            ),
          )
        else
          Card(
            child: Column(children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: Color(app.bank.subject(list[i].subjectId)?.color ?? 0xFF5B6475),
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  title: Text('${list[i].subjectName} · ${list[i].topic.isEmpty ? list[i].unit : list[i].topic}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(MathText.plain(list[i].stem), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: '풀기',
                      onPressed: () => SolveScreen.open(context, title: '내 문제', problems: [list[i]]),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                    ),
                    IconButton(
                      tooltip: '수정',
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => ProblemEditor(existing: list[i]))),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '삭제',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('문제를 삭제할까요?'),
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
                        if (ok == true) app.deleteCustom(list[i].id);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.wrong),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
      ],
    );
  }
}

class ProblemEditor extends StatefulWidget {
  const ProblemEditor({super.key, this.existing});
  final Problem? existing;

  @override
  State<ProblemEditor> createState() => _ProblemEditorState();
}

class _ProblemEditorState extends State<ProblemEditor> {
  late String _subjectId;
  late ProblemType _type;
  late int _difficulty;
  final _unit = TextEditingController();
  final _topic = TextEditingController();
  final _stem = TextEditingController();
  final _box = TextEditingController();
  final List<TextEditingController> _choices = List.generate(5, (_) => TextEditingController());
  int _choiceAnswer = 1;
  final _answer = TextEditingController();
  final _unitLabel = TextEditingController();
  final _solution = TextEditingController();
  final _hint = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _subjectId = e?.subjectId ?? ProblemBank.customSubjectId;
    _type = e?.type ?? ProblemType.choice;
    _difficulty = e?.difficulty ?? 2;
    if (e != null) {
      _unit.text = e.unit;
      _topic.text = e.topic;
      _stem.text = e.stem;
      _box.text = e.boxItems.join('\n');
      for (var i = 0; i < 5 && i < e.choices.length; i++) {
        _choices[i].text = e.choices[i];
      }
      if (e.isChoice) {
        _choiceAnswer = int.tryParse(e.answer) ?? 1;
      } else {
        _answer.text = e.answer;
      }
      _unitLabel.text = e.answerUnit ?? '';
      _solution.text = e.solution;
      _hint.text = e.hint ?? '';
    }
    for (final c in [_stem, _box, _solution, ..._choices]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_unit, _topic, _stem, _box, _answer, _unitLabel, _solution, _hint, ..._choices]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    if (_stem.text.trim().isEmpty) return false;
    if (_type == ProblemType.choice) {
      return _choices.every((c) => c.text.trim().isNotEmpty);
    }
    return _answer.text.trim().isNotEmpty;
  }

  void _save() {
    final app = AppScope.read(context);
    final sub = app.bank.subject(_subjectId);
    final p = Problem(
      id: widget.existing?.id ?? app.newCustomId(),
      subjectId: _subjectId,
      subjectName: sub?.name ?? ProblemBank.customSubjectName,
      unit: _unit.text.trim().isEmpty ? '직접 만든 문제' : _unit.text.trim(),
      topic: _topic.text.trim(),
      stem: _stem.text.trim(),
      answer: _type == ProblemType.choice ? '$_choiceAnswer' : _answer.text.trim(),
      solution: _solution.text.trim(),
      difficulty: _difficulty,
      type: _type,
      boxItems: _box.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      choices: _type == ProblemType.choice ? _choices.map((c) => c.text.trim()).toList() : const <String>[],
      answerUnit: _unitLabel.text.trim().isEmpty ? null : _unitLabel.text.trim(),
      hint: _hint.text.trim().isEmpty ? null : _hint.text.trim(),
      custom: true,
    );
    app.saveCustom(p);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('문제를 저장했어요')));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final subjects = [
      for (final s in app.bank.subjects) (s.id, s.name),
      if (!app.bank.subjects.any((s) => s.id == ProblemBank.customSubjectId))
        (ProblemBank.customSubjectId, ProblemBank.customSubjectName),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '새 문제 만들기' : '문제 수정'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _valid ? _save : null,
              icon: const Icon(Icons.save_rounded),
              label: const Text('저장'),
            ),
          ),
        ],
      ),
      body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 12, 40),
            children: [
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _subjectId,
                    decoration: const InputDecoration(labelText: '과목'),
                    items: [for (final (id, name) in subjects) DropdownMenuItem(value: id, child: Text(name))],
                    onChanged: (v) => setState(() => _subjectId = v ?? _subjectId),
                  ),
                ),
                SizedBox(width: 220, child: TextField(controller: _unit, decoration: const InputDecoration(labelText: '단원'))),
                SizedBox(width: 220, child: TextField(controller: _topic, decoration: const InputDecoration(labelText: '유형'))),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                SegmentedButton<ProblemType>(
                  segments: const [
                    ButtonSegment(value: ProblemType.choice, label: Text('5지선다'), icon: Icon(Icons.list_rounded)),
                    ButtonSegment(value: ProblemType.short, label: Text('단답형'), icon: Icon(Icons.pin_rounded)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(width: 24),
                const Text('난이도', style: TextStyle(fontWeight: FontWeight.w700)),
                Expanded(
                  child: Slider(
                    value: _difficulty.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$_difficulty',
                    onChanged: (v) => setState(() => _difficulty = v.round()),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _stem,
                maxLines: 6,
                minLines: 4,
                decoration: const InputDecoration(
                  labelText: '문제',
                  alignLabelWithHint: true,
                  hintText: r'예) 정지 상태에서 가속도 $2\,\text{m/s}^2$ 으로 3초 동안 이동한 거리는?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _box,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(
                    labelText: '〈보기〉 (선택, 한 줄에 하나)', alignLabelWithHint: true, hintText: 'ㄱ. ...\nㄴ. ...\nㄷ. ...'),
              ),
              const SizedBox(height: 16),
              if (_type == ProblemType.choice) ...[
                const Text('선택지 (정답을 눌러 표시하세요)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      InkWell(
                        onTap: () => setState(() => _choiceAnswer = i + 1),
                        borderRadius: BorderRadius.circular(20),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: _choiceAnswer == i + 1 ? AppColors.correct : AppColors.paperDeep,
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _choiceAnswer == i + 1 ? Colors.white : AppColors.inkSoft)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: _choices[i])),
                    ]),
                  ),
              ] else
                Row(children: [
                  Expanded(
                    child: TextField(
                        controller: _answer,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: '정답 (숫자, 분수, 2√3 등)')),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                      width: 160,
                      child: TextField(controller: _unitLabel, decoration: const InputDecoration(labelText: '단위 (선택)'))),
                ]),
              const SizedBox(height: 16),
              TextField(
                controller: _solution,
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(labelText: '해설', alignLabelWithHint: true),
              ),
              const SizedBox(height: 12),
              TextField(controller: _hint, decoration: const InputDecoration(labelText: '힌트 (선택)')),
            ],
          ),
        ),
        SizedBox(
          width: 420,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 24, 24),
            child: Card(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Pill('미리보기', icon: Icons.visibility_rounded),
                  const SizedBox(height: 14),
                  MathText(_stem.text.isEmpty ? '문제를 입력하면 여기에 보여요' : _stem.text,
                      style: const TextStyle(fontSize: 17, color: AppColors.ink, height: 1.7)),
                  if (_box.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.lineStrong), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final l in _box.text.split('\n').where((e) => e.trim().isNotEmpty))
                          MathText(l, style: const TextStyle(fontSize: 15, color: AppColors.ink)),
                      ]),
                    ),
                  ],
                  if (_type == ProblemType.choice) ...[
                    const SizedBox(height: 12),
                    for (var i = 0; i < 5; i++)
                      if (_choices[i].text.isNotEmpty)
                        MathText('${circled(i + 1)} ${_choices[i].text}',
                            style: TextStyle(
                                fontSize: 15,
                                color: _choiceAnswer == i + 1 ? AppColors.correct : AppColors.ink,
                                fontWeight: _choiceAnswer == i + 1 ? FontWeight.w800 : FontWeight.w500)),
                  ],
                  if (_solution.text.isNotEmpty) ...[
                    const Divider(height: 28),
                    const Text('해설', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    MathText(_solution.text, style: const TextStyle(fontSize: 14.5, color: AppColors.ink, height: 1.7)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
