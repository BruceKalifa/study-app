import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/storage.dart';
import '../core/problem.dart';
import '../core/problem_bank.dart';

/// Result of one sync with the content server.
class SyncResult {
  final bool ok;
  final int updated;
  final int total;
  final String message;
  const SyncResult(this.ok, this.updated, this.total, this.message);
}

/// Downloads course packs + workbooks from the content server (docs/content-api.md)
/// and keeps them in local storage so the app works offline with the last copy.
class ContentSync {
  ContentSync(this.storage);
  final Storage storage;

  static const _indexPath = 'content/_versions.json';

  /// "192.168.0.5:8080", "ws://…/ws", "http://…" → "http://host:port"
  static String? httpBase(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return null;
    if (u.startsWith('ws://')) u = 'http://${u.substring(5)}';
    if (u.startsWith('wss://')) u = 'https://${u.substring(6)}';
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 8080);
    return '${uri.scheme}://${uri.host}:$port';
  }

  /// Courses and workbooks saved by the last sync.
  Future<(List<Subject>, List<Workbook>?)> loadCached() async {
    final out = <Subject>[];
    List<Workbook>? wbs;
    try {
      final raw = await storage.read(_indexPath);
      if (raw == null) return (out, null);
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final packs = (j['packs'] as Map?)?.keys.map((k) => '$k').toList() ?? const <String>[];
      for (final id in packs) {
        final body = await storage.read('content/$id.json');
        if (body == null) continue;
        try {
          out.add(ProblemBank.parseCourse(body));
        } catch (e) {
          debugPrint('cached pack $id broken: $e');
        }
      }
      if (j['workbooks'] != null) {
        final body = await storage.read('content/workbooks.json');
        if (body != null) wbs = Workbook.listFromJson(jsonDecode(body));
      }
    } catch (e) {
      debugPrint('content cache: $e');
    }
    return (out, wbs);
  }

  Future<SyncResult> sync(String serverUrl) async {
    final base = httpBase(serverUrl);
    if (base == null) return const SyncResult(false, 0, 0, '서버 주소를 먼저 입력하세요');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final index = jsonDecode(await _get(client, '$base/api/content/index')) as Map<String, dynamic>;
      Map<String, dynamic> saved = {};
      final rawSaved = await storage.read(_indexPath);
      if (rawSaved != null) {
        try {
          saved = jsonDecode(rawSaved) as Map<String, dynamic>;
        } catch (_) {}
      }
      final savedPacks = (saved['packs'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final newPacks = <String, String>{};
      var updated = 0;
      final packs = (index['packs'] as List? ?? const []);
      for (final p in packs) {
        final m = (p as Map).cast<String, dynamic>();
        final id = '${m['id']}';
        final ver = '${m['version']}';
        if (id.isEmpty || id.contains('/') || id.contains('..')) continue;
        if (savedPacks[id] != ver) {
          final body = await _get(client, '$base/api/content/pack/${Uri.encodeComponent(id)}');
          ProblemBank.parseCourse(body); // only keep packs that parse
          await storage.write('content/$id.json', body);
          updated++;
        }
        newPacks[id] = ver;
      }
      for (final old in savedPacks.keys) {
        if (!newPacks.containsKey(old)) await storage.delete('content/$old.json');
      }
      String? wbVer = saved['workbooks'] as String?;
      final wbInfo = index['workbooks'];
      if (wbInfo is Map && wbInfo['version'] != null && '${wbInfo['version']}' != wbVer) {
        final body = await _get(client, '$base/api/content/workbooks');
        Workbook.listFromJson(jsonDecode(body));
        await storage.write('content/workbooks.json', body);
        wbVer = '${wbInfo['version']}';
        updated++;
      }
      await storage.write(_indexPath, jsonEncode({'packs': newPacks, 'workbooks': wbVer, 'at': DateTime.now().millisecondsSinceEpoch}));
      return SyncResult(true, updated, newPacks.length,
          updated == 0 ? '이미 최신 문항이에요 (${newPacks.length}과목)' : '$updated개를 새로 받았어요 (${newPacks.length}과목)');
    } on SocketException {
      return const SyncResult(false, 0, 0, '서버에 연결할 수 없어요 · 주소와 와이파이를 확인하세요');
    } on TimeoutException {
      return const SyncResult(false, 0, 0, '서버 응답이 없어요');
    } catch (e) {
      return SyncResult(false, 0, 0, '받기 실패: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _get(HttpClient c, String url) async {
    final req = await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    return body;
  }
}
