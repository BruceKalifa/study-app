import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../core/problem.dart';
import '../widgets/common.dart';
import '../widgets/math_text.dart';
import 'workbook_screen.dart' show byTableOfContents;

/// 답안표 — 교재의 정답을 목차별로 보고 고친다 (선생님).
/// 고친 정답은 이 태블릿의 교재 파일에 저장되고, 서버에도 다시 올라가 학생 태블릿에 반영된다.
class AnswerKeyScreen extends StatefulWidget {
  const AnswerKeyScreen({super.key, required this.workbookId});
  final String workbookId;

  static Future<void> open(BuildContext context, String workbookId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AnswerKeyScreen(workbookId: workbookId)));

  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends State<AnswerKeyScreen> {
  final _edited = <String, String>{}; // 문항 id → 고친 정답
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  String _msg = '';

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Problem p) =>
      _controllers.putIfAbsent(p.id, () => TextEditingController(text: p.answer));

  Future<void> _save(AppState app, String bookId) async {
    FocusScope.of(context).unfocus();
    final changes = Map<String, String>.from(_edited);
    if (changes.isEmpty) {
      setState(() => _msg = '고친 정답이 없어요');
      return;
    }
    setState(() {
      _saving = true;
      _msg = '';
    });
    try {
      final n = await app.updateAnswers(bookId, changes);
      _edited.clear();
      if (mounted) {
        setState(() => _msg = app.isTeacher ? '$n개 고쳤어요 · 서버에 올리는 중이에요' : '$n개 고쳤어요');
      }
    } catch (e) {
      if (mounted) setState(() => _msg = '저장하지 못했어요');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final w = app.bank.workbook(widget.workbookId);
    if (w == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('문제집을 찾을 수 없어요')));
    final ps = app.bank.problemsOf(w);
    // 정답을 고치는 건 선생님만 (학생 태블릿에서는 보기만)
    final bookId = app.isTeacher ? app.bookIdOfWorkbook(w.id) : null;
    final course = app.bank.subject(w.course);
    final color = Color(course?.color ?? 0xFF5B6475);

    return Scaffold(
      appBar: AppBar(
        title: Text('${w.title} · 답안표'),
        actions: [
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(_msg,
                    key: const Key('answers-msg'),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.correct)),
              ),
            ),
          if (bookId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                key: const Key('answers-save'),
                onPressed: _saving ? null : () => _save(app, bookId),
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_edited.isEmpty ? '저장' : '저장 (${_edited.length})'),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 60),
        children: [
          Text(
            bookId == null
                ? (app.isTeacher
                    ? '이 교재는 앱에 들어 있는 문제라 여기서는 정답을 고칠 수 없어요'
                    : '정답은 선생님만 고칠 수 있어요')
                : '칸을 눌러 정답을 고치면 저장할 때 학생 태블릿까지 반영돼요',
            style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          for (final (section, idx) in byTableOfContents(ps)) ...[
            if (section.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 6),
                child: Row(children: [
                  Container(width: 5, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 10),
                  Text(section, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(width: 8),
                  Text('${idx.length}문항',
                      style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var k = 0; k < idx.length; k++) ...[
                  if (k > 0) const Divider(height: 1),
                  _AnswerRow(
                    n: idx[k] + 1,
                    problem: ps[idx[k]],
                    color: color,
                    controller: _controllerFor(ps[idx[k]]),
                    editable: bookId != null,
                    changed: _edited.containsKey(ps[idx[k]].id),
                    onChanged: (v) {
                      final p = ps[idx[k]];
                      setState(() {
                        if (v.trim() == p.answer.trim()) {
                          _edited.remove(p.id);
                        } else {
                          _edited[p.id] = v.trim();
                        }
                      });
                    },
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.n,
    required this.problem,
    required this.color,
    required this.controller,
    required this.editable,
    required this.changed,
    required this.onChanged,
  });
  final int n;
  final Problem problem;
  final Color color;
  final TextEditingController controller;
  final bool editable;
  final bool changed;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = problem.choices.isNotEmpty;
    return Container(
      color: changed ? AppColors.reviewSoft : null,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 36,
          child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.inkSoft)),
        ),
        SizedBox(
          width: 150,
          child: Text(problem.label ?? (problem.topic.isEmpty ? problem.unit : problem.topic),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text(MathText.plain(problem.stem).replaceAll('\n', ' '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkMuted)),
        ),
        const SizedBox(width: 12),
        if (choices) Pill('5지선다', color: AppColors.inkSoft, dense: true),
        const SizedBox(width: 10),
        SizedBox(
          width: 130,
          child: TextField(
            key: Key('answer-${problem.id}'),
            controller: controller,
            enabled: editable,
            textAlign: TextAlign.center,
            keyboardType: choices ? TextInputType.number : TextInputType.text,
            inputFormatters: choices ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)] : null,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: changed ? AppColors.review : AppColors.ink),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              hintText: '정답',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: changed ? AppColors.review : AppColors.line)),
            ),
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}
