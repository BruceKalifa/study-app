import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/problem.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_model.dart';

enum LiveStatus { off, connecting, online, error }

class LiveMessage {
  final String text;
  final String from;
  final DateTime at;
  LiveMessage(this.text, this.from) : at = DateTime.now();
}

/// Streams the student's handwriting to the teacher server (docs/live-protocol.md).
class LiveSync implements InkSyncSink {
  LiveSync({required this.studentId, required this.name});

  String studentId;
  String name;
  String _url = '';
  bool _enabled = false;

  final ValueNotifier<LiveStatus> status = ValueNotifier(LiveStatus.off);
  final StreamController<LiveMessage> _messages = StreamController<LiveMessage>.broadcast();
  Stream<LiveMessage> get messages => _messages.stream;

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  int _retryDelay = 2;
  Map<String, dynamic>? _lastPage;
  List<InkStroke> Function()? _currentStrokes;

  bool get isOnline => status.value == LiveStatus.online;

  /// (Re)configure. Call whenever settings change.
  void configure({required bool enabled, required String url, String? name, String? studentId}) {
    if (name != null) this.name = name;
    if (studentId != null) this.studentId = studentId;
    final normalized = normalizeUrl(url);
    final changed = normalized != _url || enabled != _enabled;
    _url = normalized;
    _enabled = enabled && normalized.isNotEmpty;
    if (!_enabled) {
      _close();
      status.value = LiveStatus.off;
      return;
    }
    if (changed || _ch == null) {
      _close();
      _connect();
    } else {
      _send({'type': 'hello', 'studentId': this.studentId, 'name': this.name, 'device': _device});
    }
  }

  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://')) u = 'ws://${u.substring(7)}';
    if (u.startsWith('https://')) u = 'wss://${u.substring(8)}';
    if (!u.startsWith('ws://') && !u.startsWith('wss://')) u = 'ws://$u';
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty) return '';
    var path = uri.path;
    if (path.isEmpty || path == '/') path = '/ws';
    final port = uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 8080);
    return Uri(scheme: uri.scheme, host: uri.host, port: port, path: path, query: 'role=student').toString();
  }

  String get _device => defaultTargetPlatform == TargetPlatform.iOS ? 'iPad' : 'Android';

  void _connect() {
    if (!_enabled) return;
    status.value = LiveStatus.connecting;
    try {
      // protocol-level pings detect half-open sockets after sleep / Wi-Fi changes
      final WebSocketChannel ch = IOWebSocketChannel.connect(
        Uri.parse(_url),
        pingInterval: const Duration(seconds: 10),
        connectTimeout: const Duration(seconds: 8),
      );
      _ch = ch;
      ch.ready.then((_) {
        if (_ch != ch) return;
        status.value = LiveStatus.online;
        _retryDelay = 2;
        _send({'type': 'hello', 'studentId': studentId, 'name': name, 'device': _device});
        final page = _lastPage;
        if (page != null) {
          _send(page);
          final strokes = _currentStrokes?.call();
          if (strokes != null && strokes.isNotEmpty) restore(strokes);
        }
        _ping?.cancel();
        _ping = Timer.periodic(const Duration(seconds: 15), (_) => _send({'type': 'ping'}));
      }).catchError((Object e) {
        if (_ch == ch) _scheduleRetry();
      });
      _sub = ch.stream.listen(
        _onData,
        onError: (Object _) {
          if (_ch == ch) _scheduleRetry();
        },
        onDone: () {
          if (_ch == ch) _scheduleRetry();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _scheduleRetry();
    }
  }

  /// Force a fresh connection (app resumed, network changed).
  void reconnect() {
    if (!_enabled) return;
    _close();
    _retryDelay = 2;
    _connect();
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    try {
      final m = jsonDecode(data);
      if (m is! Map) return;
      if (m['type'] == 'message') {
        _messages.add(LiveMessage('${m['text'] ?? ''}', '${m['from'] ?? '선생님'}'));
      }
    } catch (_) {}
  }

  void _scheduleRetry() {
    _closeSocketOnly();
    if (!_enabled) return;
    status.value = LiveStatus.error;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _retryDelay), _connect);
    _retryDelay = _retryDelay >= 15 ? 30 : _retryDelay * 2;
  }

  void _closeSocketOnly() {
    _ping?.cancel();
    _ping = null;
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
  }

  void _close() {
    _retry?.cancel();
    _retry = null;
    _closeSocketOnly();
  }

  void _send(Map<String, dynamic> m) {
    if (!isOnline) return;
    try {
      _ch?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  // ---------------- app events ----------------
  void sendPage(Problem p, {required double pageHeight, required List<InkStroke> Function() strokes}) {
    _currentStrokes = strokes;
    _lastPage = {
      'type': 'page',
      'problemId': p.id,
      'title': '${p.subjectName} · ${p.topic.isNotEmpty ? p.topic : p.unit}',
      'subject': p.subjectName,
      'unit': p.unit,
      'topic': p.topic,
      'stem': p.stem,
      'boxItems': p.boxItems.isEmpty ? null : p.boxItems,
      'choices': p.isChoice ? p.choices : null,
      'pageHeight': pageHeight,
    };
    _send(_lastPage!);
    final s = strokes();
    if (s.isNotEmpty) restore(s);
  }

  void leavePage() {
    _currentStrokes = null;
  }

  void sendAnswer({required String problemId, required String answer, required bool correct, required int timeMs}) =>
      _send({'type': 'answer', 'problemId': problemId, 'answer': answer, 'correct': correct, 'timeMs': timeMs});

  void sendStats({
    required int total,
    required int correct,
    required int streak,
    required int todayCount,
    required List<String> weakTopics,
  }) =>
      _send({
        'type': 'stats',
        'total': total,
        'correct': correct,
        'streak': streak,
        'todayCount': todayCount,
        'weakTopics': weakTopics,
      });

  // ---------------- InkSyncSink ----------------
  @override
  void strokeBegin(InkStroke s) {
    final j = s.toLiveJson();
    _send({'type': 'stroke_begin', ...j});
  }

  @override
  void strokePoints(String id, List<InkPoint> pts) => _send({
        'type': 'stroke_points',
        'id': id,
        'points': [
          for (final p in pts) [(p.x * 10).round() / 10, (p.y * 10).round() / 10, (p.p * 1000).round() / 1000]
        ],
      });

  @override
  void strokeEnd(String id) => _send({'type': 'stroke_end', 'id': id});

  @override
  void erase(List<String> ids) => _send({'type': 'erase', 'ids': ids});

  @override
  void restore(List<InkStroke> all) =>
      _send({'type': 'restore', 'strokes': [for (final s in all) s.toLiveJson()]});

  @override
  void clear() => _send({'type': 'clear'});

  void dispose() {
    _enabled = false;
    _close();
    _messages.close();
  }
}
