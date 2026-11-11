import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../core/pdf_ref.dart';
import 'pdf_store.dart';

/// PDF 한 영역을 그림으로 그린다 — 실제 앱은 pdfium(크롬과 같은 PDF 엔진), 테스트는 가짜.
abstract class PdfRasterizer {
  /// [doc] 의 [page](1부터) 쪽에서 [rect](포인트)를 1포인트당 [pxPerPt] 픽셀로 그린다.
  Future<ui.Image?> render(String doc, int page, PdfBox rect, double pxPerPt);

  /// 지금 쓰는 것. 테스트에서 바꿔 끼운다.
  static PdfRasterizer current = PdfiumRasterizer();
}

class PdfiumRasterizer implements PdfRasterizer {
  final Map<String, Future<pdfrx.PdfDocument?>> _docs = {};
  bool _init = false;

  Future<pdfrx.PdfDocument?> _open(String doc) {
    final hit = _docs.remove(doc);
    if (hit != null) {
      _docs[doc] = hit; // 최근에 쓴 것을 뒤로
      return hit;
    }
    if (!_init) {
      _init = true;
      try {
        pdfrx.pdfrxFlutterInitialize();
      } catch (e) {
        debugPrint('pdfrx init: $e');
      }
    }
    final f = () async {
      final bytes = await PdfStore.instance?.bytes(doc);
      if (bytes == null) return null;
      try {
        return await pdfrx.PdfDocument.openData(bytes, sourceName: doc);
      } catch (e) {
        debugPrint('pdf $doc open failed: $e');
        return null;
      }
    }();
    _docs[doc] = f;
    while (_docs.length > 4) {
      final old = _docs.remove(_docs.keys.first);
      old?.then((d) => d?.dispose());
    }
    return f;
  }

  @override
  Future<ui.Image?> render(String doc, int page, PdfBox rect, double pxPerPt) async {
    final d = await _open(doc);
    if (d == null || page < 1 || page > d.pages.length) return null;
    final pg = d.pages[page - 1];
    final w = (rect.width * pxPerPt).round(), h = (rect.height * pxPerPt).round();
    if (w <= 0 || h <= 0) return null;
    final img = await pg.render(
      x: (rect.x0 * pxPerPt).round(),
      y: (rect.y0 * pxPerPt).round(),
      width: w,
      height: h,
      fullWidth: pg.width * pxPerPt,
      fullHeight: pg.height * pxPerPt,
    );
    if (img == null) return null;
    try {
      return await img.createImage();
    } finally {
      img.dispose();
    }
  }
}

/// PDF 의 한 영역을 원본 그대로 — 화면에서 실제로 보이는 크기(확대 배율 포함)에 맞춰 다시 그려서 늘 선명하다.
/// 가로는 주어진 폭에 맞추고, 세로는 영역 비율대로.
class PdfRegionView extends StatefulWidget {
  const PdfRegionView({super.key, required this.doc, required this.page, required this.rect, this.overlay});

  PdfRegionView.region(PdfRegion r, {Key? key, Widget? overlay})
      : this(key: key, doc: r.doc, page: r.page, rect: r.rect, overlay: overlay);

  final String doc;
  final int page;
  final PdfBox rect;

  /// 그림 위에 겹칠 것 (선지 누를 자리 등). 같은 크기로 깔린다.
  final Widget? overlay;

  @override
  State<PdfRegionView> createState() => _PdfRegionViewState();
}

class _PdfRegionViewState extends State<PdfRegionView> {
  ui.Image? _img;
  double _scale = 0; // _img 를 그린 배율 (픽셀/포인트)
  bool _busy = false;
  bool _failed = false;
  Timer? _watch;
  int _seq = 0;

  // 한 장의 최대 크기 — 아주 크게 확대해도 메모리를 다 쓰지 않게
  static const _maxSide = 4096.0;
  static const _maxPixels = 14e6;

  @override
  void initState() {
    super.initState();
    // 확대·축소는 부모의 변환으로만 바뀌어 다시 그려지지 않을 수 있어, 가끔 화면 배율을 살핀다
    _watch = Timer.periodic(const Duration(milliseconds: 350), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(PdfRegionView old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc || old.page != widget.page || old.rect != widget.rect) {
      _seq++;
      _img?.dispose();
      _img = null;
      _scale = 0;
      _failed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _seq++;
    _img?.dispose();
    super.dispose();
  }

  /// 지금 화면에서 필요한 배율 (픽셀/포인트).
  double? _wanted() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.width <= 0) return null;
    final m = box.getTransformTo(null);
    final screen = m.getMaxScaleOnAxis() * box.size.width; // 논리 픽셀
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    var s = screen * dpr / widget.rect.width;
    s = math.min(s, _maxSide / math.max(widget.rect.width, widget.rect.height));
    s = math.min(s, math.sqrt(_maxPixels / (widget.rect.width * widget.rect.height)));
    return s;
  }

  void _check() {
    if (!mounted || _busy || _failed) return;
    final want = _wanted();
    if (want == null || want <= 0) return;
    // 더 크게 보이면 다시, 훨씬 작아지면 메모리를 아끼려 다시
    if (_img != null && want <= _scale * 1.25 && want >= _scale / 3) return;
    _render(want);
  }

  Future<void> _render(double scale) async {
    _busy = true;
    final seq = ++_seq;
    try {
      final img = await PdfRasterizer.current.render(widget.doc, widget.page, widget.rect, scale);
      if (!mounted || seq != _seq) {
        img?.dispose();
        return;
      }
      if (img == null) {
        setState(() => _failed = _img == null);
        return;
      }
      setState(() {
        _img?.dispose();
        _img = img;
        _scale = scale;
      });
    } catch (e) {
      debugPrint('pdf render: $e');
      if (mounted && _img == null) setState(() => _failed = true);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.rect.width / widget.rect.height;
    final img = _img;
    return AspectRatio(
      aspectRatio: aspect,
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.white),
        if (img != null)
          RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium)
        else if (_failed)
          const Center(
            child: Text('원본 PDF 를 열 수 없어요 · 교재를 다시 받아 주세요',
                style: TextStyle(fontSize: 14, color: Color(0xFF8A90A0))),
          ),
        if (widget.overlay != null) widget.overlay!,
      ]),
    );
  }
}
