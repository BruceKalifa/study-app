import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import 'common.dart';
import '../services/content_import.dart';

/// 설정: 교재 파일(.pulinote) 가져오기 · 넣은 교재 목록 · 빼기 (학생·선생님 공통).
class BookFilesCard extends StatefulWidget {
  const BookFilesCard({super.key});

  /// Replaced in tests (the Android file picker is not available there).
  static Future<Uint8List?> Function() picker = BookFiles.pick;

  @override
  State<BookFilesCard> createState() => _BookFilesCardState();
}

class _BookFilesCardState extends State<BookFilesCard> {
  bool _busy = false;
  String _msg = '';
  bool _error = false;

  Future<void> _import(AppState app) async {
    setState(() {
      _busy = true;
      _msg = '';
    });
    final bytes = await BookFilesCard.picker();
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      final books = await app.importBooks(bytes);
      final n = books.fold<int>(0, (n, b) => n + b.problemCount);
      final what = books.length == 1 ? '「${books.first.title}」을' : '교재 ${books.length}권을';
      _msg = '$what 넣었어요 · $n문항${app.isTeacher ? '' : ' · 내 교재에 담았어요'}';
      _error = false;
    } on FormatException catch (e) {
      _msg = e.message;
      _error = true;
    } catch (e) {
      _msg = '교재 파일을 넣지 못했어요';
      _error = true;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(AppState app, ImportedBook b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${b.title}」 빼기'),
        content: const Text('이 태블릿에서 교재를 지워요. 푼 기록은 남고, 파일을 다시 넣으면 이어서 풀 수 있어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
              key: const Key('books-remove-ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('빼기')),
        ],
      ),
    );
    if (ok == true) await app.removeImportedBook(b.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final books = app.importedBooks;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ActionRow(
            leading: const Icon(Icons.auto_stories_rounded, color: AppColors.inkSoft),
            actions: [
              _busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : FilledButton.icon(
                      key: const Key('books-import'),
                      onPressed: () => _import(app),
                      icon: const Icon(Icons.file_open_rounded, size: 18),
                      label: const Text('파일 가져오기'),
                    ),
            ],
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('교재 파일', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              SizedBox(height: 2),
              Text('선생님께 받은 .pulinote 파일을 넣으면 그 교재를 앱에서 풀 수 있어요',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 13.5)),
            ]),
          ),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_msg,
                key: const Key('books-msg'),
                style: TextStyle(fontWeight: FontWeight.w700, color: _error ? AppColors.wrong : AppColors.correct)),
          ],
          if (books.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final b in books)
              ListTile(
                key: Key('book-${b.id}'),
                contentPadding: const EdgeInsets.only(left: 36),
                dense: true,
                title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${b.problems}문항'),
                trailing: IconButton(
                  key: Key('book-remove-${b.id}'),
                  tooltip: '빼기',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _remove(app, b),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}
