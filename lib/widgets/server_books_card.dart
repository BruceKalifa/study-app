import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import 'common.dart';
import '../services/account_api.dart';
import '../services/content_import.dart';
import 'book_files_card.dart';

/// 설정: 서버 교재 — 선생님은 올리고, 연결된 학생은 받아서 바로 푼다.
/// 교재 내용은 서버에만 두고, 로그인한 사람만 받을 수 있다 (server/books.js).
class ServerBooksCard extends StatefulWidget {
  const ServerBooksCard({super.key});

  /// Replaced in tests (no server there).
  static AccountApi? Function(AppState app)? apiOf;

  @override
  State<ServerBooksCard> createState() => _ServerBooksCardState();
}

class _ServerBooksCardState extends State<ServerBooksCard> {
  List<ServerBook>? _books;
  bool _loading = false;
  String _msg = '';
  bool _error = false;
  String _busyId = ''; // 받는 중 · 지우는 중인 교재
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  AccountApi? get _api {
    final app = AppScope.read(context);
    return ServerBooksCard.apiOf != null ? ServerBooksCard.apiOf!(app) : app.api;
  }

  Future<void> _load({bool quiet = true}) async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _loading = true;
      if (!quiet) _msg = '';
    });
    try {
      final books = await api.books();
      if (!mounted) return;
      setState(() {
        _books = books;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet) {
          _msg = e is ApiError ? e.message : '교재 목록을 불러오지 못했어요';
          _error = true;
        }
      });
    }
  }

  void _say(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _msg = msg;
      _error = error;
    });
  }

  /// 자동으로 도는 주고받기를 지금 한 번 돌린다.
  Future<void> _syncNow(AppState app) async {
    setState(() {
      _loading = true;
      _msg = '';
    });
    final msg = await app.syncBooks();
    if (!mounted) return;
    if (msg.isNotEmpty) _say(msg);
    await _load();
  }

  Future<void> _get(AppState app, ServerBook b) async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _busyId = b.id;
      _msg = '';
    });
    try {
      final bytes = await api.bookBytes(b.id);
      final books = await app.importBooks(bytes);
      final n = books.fold<int>(0, (n, x) => n + x.problemCount);
      _say('「${b.title}」을 받았어요 · $n문항${app.isTeacher ? '' : ' · 내 교재에 담았어요'}');
    } on FormatException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say(e is ApiError ? e.message : '교재를 받지 못했어요', error: true);
    }
    if (mounted) setState(() => _busyId = '');
  }

  Future<void> _upload(AppState app) async {
    final api = _api;
    if (api == null) return;
    final bytes = await BookFilesCard.picker();
    if (!mounted || bytes == null) return;
    setState(() {
      _uploading = true;
      _msg = '';
    });
    try {
      ContentImport.decodeAll(bytes); // 올리기 전에 이 자리에서 확인
      final b = await api.uploadBook(Uint8List.fromList(bytes));
      _say('「${b.title}」을 서버에 올렸어요 · 학생이 받을 수 있어요');
      await _load();
    } on FormatException catch (e) {
      _say(e.message, error: true);
    } catch (e) {
      _say(e is ApiError ? e.message : '교재를 올리지 못했어요', error: true);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _remove(ServerBook b) async {
    final api = _api;
    if (api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${b.title}」 서버에서 빼기'),
        content: const Text('학생이 더 이상 이 교재를 받을 수 없어요. 이미 받은 태블릿에는 그대로 남아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
              key: const Key('server-book-remove-ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('빼기')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = b.id);
    try {
      await api.deleteBook(b.id);
      _say('「${b.title}」을 서버에서 뺐어요');
      await _load();
    } catch (e) {
      _say(e is ApiError ? e.message : '교재를 빼지 못했어요', error: true);
    }
    if (mounted) setState(() => _busyId = '');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.signedIn) return const SizedBox.shrink();
    final teacher = app.isTeacher;
    final books = _books ?? const <ServerBook>[];
    final have = {for (final b in app.importedBooks) b.id};
    final msg = _msg.isNotEmpty ? _msg : app.bookSyncMessage;
    final busy = _uploading || app.bookSyncing || (_loading && _books == null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ActionRow(
            leading: const Icon(Icons.cloud_download_rounded, color: AppColors.inkSoft),
            actions: [
              if (busy)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              else if (teacher)
                FilledButton.icon(
                  key: const Key('server-books-upload'),
                  onPressed: () => _upload(app),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text('서버에 올리기'),
                )
              else
                IconButton(
                  key: const Key('server-books-refresh'),
                  tooltip: '지금 받기',
                  onPressed: () => _syncNow(app),
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(teacher ? '서버 교재' : '선생님 교재',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(
                  teacher
                      ? '이 태블릿에 넣은 교재는 저절로 올라가요 · 연결된 학생만 받을 수 있어요'
                      : '선생님이 올린 교재는 로그인하면 저절로 들어와요',
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5)),
            ]),
          ),
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(msg,
                key: const Key('server-books-msg'),
                style: TextStyle(fontWeight: FontWeight.w700, color: _error ? AppColors.wrong : AppColors.correct)),
          ],
          if (_books != null && books.isEmpty) ...[
            const SizedBox(height: 10),
            Text(teacher ? '아직 올린 교재가 없어요' : '선생님이 올린 교재가 아직 없어요',
                key: const Key('server-books-empty'),
                style: const TextStyle(color: AppColors.inkSoft)),
          ],
          for (final b in books)
            ListTile(
              key: Key('server-book-${b.id}'),
              contentPadding: const EdgeInsets.only(left: 36),
              dense: true,
              title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([
                '${b.problems}문항',
                b.sizeLabel,
                if (!teacher && b.teacherName.isNotEmpty) b.teacherName,
                if (teacher && !b.open) '숨김',
              ].join(' · ')),
              trailing: _busyId == b.id
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (b.bookIds.isNotEmpty && b.bookIds.every(have.contains))
                        TextButton(
                          key: Key('server-book-again-${b.id}'),
                          onPressed: () => _get(app, b),
                          child: const Text('다시 받기'),
                        )
                      else
                        FilledButton.tonal(
                          key: Key('server-book-get-${b.id}'),
                          onPressed: () => _get(app, b),
                          child: const Text('받기'),
                        ),
                      if (teacher)
                        IconButton(
                          key: Key('server-book-remove-${b.id}'),
                          tooltip: '서버에서 빼기',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _remove(b),
                        ),
                    ]),
            ),
        ]),
      ),
    );
  }
}
