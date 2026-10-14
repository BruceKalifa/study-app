import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

import '../app/theme.dart';

/// 3D 수업 HTML(`Solvit3D.lesson(…)`)에 솔빗 런타임(three.js)을 끼우고, 바깥으로 나가는 통로를 막는다.
///
/// - 선생님이 외부에서 만든 HTML 에 들어 있는 `<script src="solvit3d-runtime.js">`(미리보기용)는 빼고, 앱의 런타임을 인라인으로 넣는다.
/// - CSP: 스크립트·스타일은 이 페이지 안에서만, 그림은 data:/blob: 만, 네트워크(connect/frame/form)는 모두 막는다.
String composeLessonHtml(String lesson, String runtime) {
  var html = lesson;
  // 미리보기용 런타임 불러오기 · 앱이 끼울 자리 표시는 지운다 (런타임은 아래에서 한 번만 넣는다)
  html = html.replaceAll(RegExp(r'<script\b[^>]*\bsrc\s*=\s*["\x27][^"\x27]*solvit3d[^"\x27]*["\x27][^>]*>\s*</script>', caseSensitive: false), '');
  html = html.replaceAll('<!--SOLVIT3D-->', '');
  // 인라인 스크립트 안의 `</script` 가 런타임 줄을 끊지 않게
  final inline = runtime.replaceAll('</script', r'<\/script');
  const csp = '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; '
      'style-src \'unsafe-inline\'; img-src data: blob:; font-src data:; connect-src \'none\'; media-src \'none\'; '
      'frame-src \'none\'; form-action \'none\'; base-uri \'none\'">';
  final head = '<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">'
      '$csp<script>$inline</script>';
  final m = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (m != null) {
    return html.replaceRange(m.end, m.end, head);
  }
  final h = RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(html);
  if (h != null) return html.replaceRange(h.end, h.end, '<head>$head</head>');
  return '<!doctype html><html><head>$head</head><body>$html</body></html>';
}

/// 3D 수업 한 장 — 돌려 보기(손가락 드래그·두 손가락 확대), 단계 넘기기, 재생·일시정지·슬라이더는 수업 화면 안에 있다.
class Lesson3DView extends StatefulWidget {
  const Lesson3DView({super.key, required this.html});
  final String html;

  @override
  State<Lesson3DView> createState() => _Lesson3DViewState();
}

class _Lesson3DViewState extends State<Lesson3DView> {
  WebViewController? _c;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(Lesson3DView old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _load();
  }

  Future<void> _load() async {
    try {
      final runtime = await rootBundle.loadString('assets/lesson3d/solvit3d-runtime.js');
      final page = composeLessonHtml(widget.html, runtime);
      final c = _c ??
          (WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(const Color(0xFFF7F5EF))
            ..setNavigationDelegate(NavigationDelegate(
              // 처음 불러온 페이지 밖으로는 못 나간다 (링크·주소 이동 모두 막는다)
              onNavigationRequest: (r) => r.url == 'about:blank' ? NavigationDecision.navigate : NavigationDecision.prevent,
              onPageFinished: (_) {
                if (mounted) setState(() => _ready = true);
              },
            )));
      await c.loadHtmlString(page);
      if (!mounted) return;
      setState(() {
        _c = c;
        _error = null;
      });
    } catch (e) {
      debugPrint('lesson3d: $e');
      if (mounted) setState(() => _error = '이 기기에서는 3D 수업을 열 수 없어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_error != null || c == null) {
      return Container(
        key: const Key('lesson3d-view'),
        color: const Color(0xFFF7F5EF),
        alignment: Alignment.center,
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700))
            : const CircularProgressIndicator(),
      );
    }
    return Stack(key: const Key('lesson3d-view'), children: [
      Positioned.fill(child: WebViewWidget(controller: c)),
      if (!_ready) const Positioned.fill(child: ColoredBox(color: Color(0xFFF7F5EF), child: Center(child: CircularProgressIndicator()))),
    ]);
  }
}
