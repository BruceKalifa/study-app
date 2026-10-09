import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../services/content_import.dart';

/// 설정: 이 태블릿에 들어 있는 교재 목록 · 빼기 (학생·선생님 공통).
/// 교재를 넣는 길은 하나뿐이다 — 서버 교재 창고에서 받는다 (AppState.syncBooks).
class BookFilesCard extends StatefulWidget {
  const BookFilesCard({super.key});

  @override
  State<BookFilesCard> createState() => _BookFilesCardState();
}

class _BookFilesCardState extends State<BookFilesCard> {
  Future<void> _remove(AppState app, ImportedBook b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${b.title}」 빼기'),
        content: const Text('이 태블릿에서 교재를 지워요. 푼 기록은 남고, 서버에 그대로 있으면 다시 받아져요.'),
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
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.auto_stories_rounded, color: AppColors.inkSoft),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('넣어 둔 교재', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 2),
                Text('서버에 올라온 교재는 저절로 들어와요 · 여기서 뺄 수 있어요',
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 13.5)),
              ]),
            ),
          ]),
          if (books.isEmpty) ...[
            const SizedBox(height: 10),
            const Text('아직 들어 있는 교재가 없어요',
                key: Key('books-empty'), style: TextStyle(color: AppColors.inkSoft)),
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
