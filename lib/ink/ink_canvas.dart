import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'ink_controller.dart';
import 'ink_model.dart';
import 'stroke_renderer.dart';

/// A zoomable, pannable sheet of paper you can write on.
///
/// Input model (GoodNotes / Samsung Notes style):
/// * S Pen / stylus draws with the current tool.
/// * S Pen side button held (or eraser tip) → temporary eraser; release → back to the pen.
/// * One finger pans, two fingers pinch-zoom (unless "finger draws" is on).
/// * Two-finger tap = undo, three-finger tap = redo.
/// * Palm rejection: touches are ignored while the stylus is down or hovering.
class InkCanvas extends StatefulWidget {
  const InkCanvas({
    super.key,
    required this.controller,
    this.underlay,
    this.interactive = true,
    this.readOnly = false,
    this.paper,
    this.paperColor,
    this.columnRuleX,
    this.onStylusDown,
    this.onTapPage,
    this.minZoom = 0.6,
    this.maxZoom = 4,
  });

  final InkController controller;

  /// Content laid out at the top of the page in page coordinates (width 1000).
  final Widget? underlay;

  /// Allow pan / zoom gestures.
  final bool interactive;
  final bool readOnly;
  final PaperStyle? paper;
  final Color? paperColor;

  /// 시험지 단 경계선 — 페이지 좌표(0~1000)의 x. 문제는 왼쪽, 풀이는 오른쪽.
  final double? columnRuleX;
  final VoidCallback? onStylusDown;

  /// A quick tap (pen or finger) at a page position. Return true to consume it:
  /// a pen tap then leaves no dot on the page (used to pick 객관식 choices).
  final bool Function(Offset pagePos, bool stylus)? onTapPage;
  final double minZoom, maxZoom;

  /// True while the pen is writing (or just lifted): touches elsewhere are probably the palm.
  static bool get penBusy =>
      DateTime.now().millisecondsSinceEpoch - InkCanvasState._lastStylusContact < 450;

  @override
  State<InkCanvas> createState() => InkCanvasState();
}

class _Ptr {
  final PointerDeviceKind kind;
  Offset start;
  Offset last;
  final int downAt;
  _Ptr(this.kind, this.start, this.downAt) : last = start;
}

class InkCanvasState extends State<InkCanvas> with SingleTickerProviderStateMixin {
  InkController get c => widget.controller;

  double _zoom = 1;
  Offset _offset = Offset.zero; // screen px
  Size _viewport = Size.zero;

  final Map<int, _Ptr> _touches = {};
  final Set<int> _ignored = {}; // pointers judged to be a palm / resting hand
  int? _drawPointer;
  bool _drawIsStylus = false;
  bool _drawIsEraser = false;
  Offset _drawLast = Offset.zero;
  Offset _drawStart = Offset.zero;
  int _drawDownAt = 0;
  double _drawTravel = 0;

  // Palm-rejection state is shared by every canvas on screen (page + answer pad):
  // a palm resting on the answer pad must be rejected while the pen writes on the page.
  static int _lastStylusContact = 0;
  static int _lastHover = 0;
  static Offset? _penGlobal;
  static bool _stylusSeen = false;

  // pinch/pan state
  double _gestureStartZoom = 1;
  double _gestureStartDist = 1;
  Offset _gestureStartFocal = Offset.zero;
  Offset _gestureStartOffset = Offset.zero;
  bool _multiTouchMoved = false;
  bool _tapEligible = true;
  int _maxTouchesInGesture = 0;
  int _gestureStartedAt = 0;

  // fling (velocity in px per ms)
  late final Ticker _ticker;
  Offset _velocity = Offset.zero;
  Duration _lastFlingTick = Duration.zero;
  final List<(int, Offset)> _panTrail = [];

  double get _fit => _viewport.width <= 0 ? 1 : _viewport.width / kPageWidth;
  double get scale => _fit * _zoom;
  double get zoom => _zoom;

  Offset toPage(Offset local) => (local - _offset) / scale;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFling);
    c.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant InkCanvas old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _ticker.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  // ---------------- public helpers ----------------
  void resetView() {
    setState(() {
      _zoom = 1;
      _offset = Offset.zero;
    });
  }

  void scrollToTop() => setState(() => _offset = Offset(_offset.dx, 0));

  void setZoom(double z) {
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    _zoomAround(center, z);
  }

  void _zoomAround(Offset focal, double z) {
    z = z.clamp(widget.minZoom, widget.maxZoom);
    final pagePt = toPage(focal);
    setState(() {
      _zoom = z;
      _offset = focal - pagePt * scale;
      _clamp();
    });
  }

  void _clamp() {
    final pageW = kPageWidth * scale;
    final pageH = c.pageHeight * scale;
    double dx;
    if (pageW <= _viewport.width) {
      dx = (_viewport.width - pageW) / 2;
    } else {
      dx = _offset.dx.clamp(_viewport.width - pageW, 0.0);
    }
    final minY = math.min(0.0, _viewport.height - pageH - 80);
    final dy = _offset.dy.clamp(minY, 0.0);
    _offset = Offset(dx, dy);
  }

  // ---------------- pointer handling ----------------
  bool _isStylus(PointerDeviceKind k) => k == PointerDeviceKind.stylus || k == PointerDeviceKind.invertedStylus;

  /// S Pen side button (Android BUTTON_STYLUS_PRIMARY → kPrimaryStylusButton) or eraser tip.
  bool _wantsEraser(PointerEvent e) =>
      e.kind == PointerDeviceKind.invertedStylus ||
      (_isStylus(e.kind) && (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) != 0);

  double _pressure(PointerEvent e) {
    if (!_isStylus(e.kind)) return 0.55;
    final lo = e.pressureMin, hi = e.pressureMax;
    if (hi > lo) return ((e.pressure - lo) / (hi - lo)).clamp(0.0, 1.0);
    return e.pressure.clamp(0.0, 1.0);
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void _markPen(PointerEvent e) {
    _lastStylusContact = _now;
    _penGlobal = e.position;
    _stylusSeen = true;
  }

  /// A touch is treated as a palm if the pen just touched, if it lands near the hovering pen,
  /// or if the contact patch is large.
  bool _isPalm(PointerEvent e) {
    final now = _now;
    if (now - _lastStylusContact < 300) return true;
    final pen = _penGlobal;
    if (now - _lastHover < 600 && pen != null && (e.position - pen).distance < 320) return true;
    if (e.radiusMajor > 32) return true;
    return false;
  }

  void _resetGesture(int now) {
    _maxTouchesInGesture = 0;
    _multiTouchMoved = false;
    _tapEligible = true;
    _gestureStartedAt = now;
  }

  void _onDown(PointerDownEvent e) {
    _ticker.stop();
    final now = _now;
    final isStylus = _isStylus(e.kind);
    final isMouse = e.kind == PointerDeviceKind.mouse;

    // 자리 고르기(함수 그래프 놓기) — 그리는 대신 누른 자리를 받는다
    final req = c.placing.value;
    if (req != null && _placePointer == null) {
      _placePointer = e.pointer;
      c.placePreview = c.placeRectAt(toPage(e.localPosition), req);
      c.activeTick.value++;
      return;
    }

    if (isStylus || isMouse) {
      if (isStylus) _markPen(e);
      if (widget.readOnly) return;
      if (_drawPointer != null) {
        if (_drawIsStylus) return;
        // a finger / palm stroke was running: the pen takes over
        c.pointerCancel();
        _ignored.add(_drawPointer!);
        _drawPointer = null;
      }
      // hands already resting on the screen must not pan while the pen writes
      _ignored.addAll(_touches.keys);
      _touches.clear();
      _startDraw(e, stylus: isStylus || isMouse);
      if (isStylus) widget.onStylusDown?.call();
      return;
    }

    if (e.kind != PointerDeviceKind.touch) return;
    if ((_drawPointer != null && _drawIsStylus) || _isPalm(e)) {
      _ignored.add(e.pointer);
      return;
    }
    final fingerDraw = c.settings.fingerDraws && !_stylusSeen && !widget.readOnly;
    if (fingerDraw && _drawPointer == null && _touches.isEmpty) {
      _startDraw(e, stylus: false);
      return;
    }
    if (_drawPointer != null && !_drawIsStylus) {
      // a finger-drawing stroke becomes a pinch when a second finger lands
      c.pointerCancel();
      final p = _drawPointer!;
      _drawPointer = null;
      _resetGesture(now);
      _touches[p] = _Ptr(PointerDeviceKind.touch, _drawLast, now);
      _tapEligible = false;
    }
    if (_touches.isEmpty) {
      _resetGesture(now);
    } else if (now - _gestureStartedAt > 150) {
      _tapEligible = false; // fingers must land together for tap-undo
    }
    _touches[e.pointer] = _Ptr(e.kind, e.localPosition, now);
    _maxTouchesInGesture = math.max(_maxTouchesInGesture, _touches.length);
    _beginGesture();
  }

  // 자리 고르기
  int? _placePointer;

  /// 누른 채 움직이면 놓일 자리가 따라온다 (떼기 전에 고쳐 잡을 수 있게).
  bool _placeMove(PointerEvent e) {
    if (_placePointer != e.pointer) return false;
    final req = c.placing.value;
    if (req != null) {
      c.placePreview = c.placeRectAt(toPage(e.localPosition), req);
      c.activeTick.value++;
    }
    return true;
  }

  bool _placeUp(PointerEvent e, {required bool cancelled}) {
    if (_placePointer != e.pointer) return false;
    _placePointer = null;
    if (cancelled) {
      c.cancelPlacing();
      return true;
    }
    c.finishPlacing(toPage(e.localPosition));
    return true;
  }

  void _startDraw(PointerEvent e, {required bool stylus}) {
    _drawPointer = e.pointer;
    _drawIsStylus = stylus;
    _drawLast = e.localPosition;
    _drawStart = e.localPosition;
    _drawDownAt = _now;
    _drawTravel = 0;
    _drawIsEraser = _wantsEraser(e);
    c.pointerDown(toPage(e.localPosition), _pressure(e), forceEraser: _drawIsEraser);
  }

  void _beginGesture() {
    final pts = _touches.values.map((t) => t.last).toList();
    if (pts.isEmpty) return;
    _gestureStartZoom = _zoom;
    _gestureStartOffset = _offset;
    _gestureStartFocal = _centroid(pts);
    _gestureStartDist = pts.length >= 2 ? _spread(pts) : 1;
    _panTrail.clear();
  }

  Offset _centroid(List<Offset> pts) {
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }

  double _spread(List<Offset> pts) {
    final ctr = _centroid(pts);
    var d = 0.0;
    for (final p in pts) {
      d += (p - ctr).distance;
    }
    return math.max(1, d / pts.length);
  }

  void _onMove(PointerMoveEvent e) {
    if (_ignored.contains(e.pointer)) return;
    if (_placeMove(e)) return;
    if (e.pointer == _drawPointer) {
      if (_isStylus(e.kind)) _markPen(e);
      _drawTravel = math.max(_drawTravel, (e.localPosition - _drawStart).distance);
      _drawLast = e.localPosition;
      final wantEraser = _wantsEraser(e);
      final pos = toPage(e.localPosition);
      if (wantEraser != _drawIsEraser) {
        _drawIsEraser = wantEraser;
        c.switchGestureTool(pos, _pressure(e), eraser: wantEraser);
      } else {
        c.pointerMove(pos, _pressure(e));
      }
      return;
    }
    final t = _touches[e.pointer];
    if (t == null) return;
    t.last = e.localPosition;
    if ((t.last - t.start).distance > 14) _multiTouchMoved = true;
    if (!widget.interactive) return;
    if (_drawPointer != null && _drawIsStylus) return; // never move the page under the pen
    final pts = _touches.values.map((t) => t.last).toList();
    final focal = _centroid(pts);
    setState(() {
      if (pts.length >= 2) {
        final z = (_gestureStartZoom * _spread(pts) / _gestureStartDist).clamp(widget.minZoom, widget.maxZoom);
        // keep the page point under the starting focal under the current focal
        final startScale = _fit * _gestureStartZoom;
        final pagePt = (_gestureStartFocal - _gestureStartOffset) / startScale;
        _zoom = z;
        _offset = focal - pagePt * scale;
      } else {
        _offset = _gestureStartOffset + (focal - _gestureStartFocal);
      }
      _clamp();
    });
    _panTrail.add((_now, focal));
    if (_panTrail.length > 6) _panTrail.removeAt(0);
  }

  void _onUp(PointerEvent e, {bool cancelled = false}) {
    if (_ignored.remove(e.pointer)) return;
    if (_placeUp(e, cancelled: cancelled)) return;
    if (e.pointer == _drawPointer) {
      if (_isStylus(e.kind)) _markPen(e);
      _drawPointer = null;
      if (cancelled) {
        c.pointerCancel();
      } else if (!_drawIsEraser &&
          widget.onTapPage != null &&
          (c.tool == InkTool.pen || c.tool == InkTool.highlighter) &&
          _now - _drawDownAt < 280 &&
          _drawTravel < 9 &&
          widget.onTapPage!(toPage(_drawStart), _drawIsStylus)) {
        c.pointerCancel(); // the tap selected something: no dot
      } else {
        c.pointerUp();
      }
      return;
    }
    final t = _touches.remove(e.pointer);
    if (t == null) return;
    if (_touches.isEmpty) {
      final now = _now;
      final quick = now - _gestureStartedAt < 320;
      final penDuring = _lastStylusContact >= _gestureStartedAt;
      final cleanTap = !cancelled && quick && !penDuring && !_multiTouchMoved;
      if (cleanTap && _maxTouchesInGesture == 1 && widget.onTapPage != null) {
        widget.onTapPage!(toPage(t.start), false);
      } else if (cleanTap &&
          _tapEligible &&
          (_maxTouchesInGesture == 2 || _maxTouchesInGesture == 3) &&
          c.settings.twoFingerUndo &&
          !widget.readOnly) {
        if (_maxTouchesInGesture == 2) {
          c.undo();
          _toast('실행 취소');
        } else {
          c.redo();
          _toast('다시 실행');
        }
      } else if (_maxTouchesInGesture == 1 && _panTrail.length >= 2 && widget.interactive) {
        final a = _panTrail.first, b = _panTrail.last;
        if (now - b.$1 < 60) {
          final dt = math.max(1, b.$1 - a.$1);
          _velocity = (b.$2 - a.$2) / dt.toDouble(); // px per ms
          if (_velocity.distance > 0.15) {
            _lastFlingTick = Duration.zero;
            _ticker.start();
          }
        }
      }
    } else {
      _beginGesture();
    }
  }

  void _onFling(Duration elapsed) {
    final dtMs = (elapsed - _lastFlingTick).inMicroseconds / 1000.0;
    _lastFlingTick = elapsed;
    if (dtMs <= 0) return;
    _velocity = _velocity * math.exp(-dtMs / 325);
    if (_velocity.distance < 0.02) {
      _ticker.stop();
      return;
    }
    setState(() {
      _offset += _velocity * dtMs;
      _clamp();
    });
  }

  void _onHover(PointerHoverEvent e) {
    if (_isStylus(e.kind)) {
      _lastHover = _now;
      _penGlobal = e.position;
      _stylusSeen = true;
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent && widget.interactive) {
      setState(() {
        _offset -= e.scrollDelta;
        _clamp();
      });
    }
  }

  OverlayEntry? _toastEntry;
  void _toast(String msg) {
    _toastEntry?.remove();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: 90,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xE61B2A4A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _toastEntry = entry;
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (_toastEntry == entry) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final paper = widget.paper ?? c.settings.paper;
    return LayoutBuilder(builder: (context, box) {
      final newViewport = Size(box.maxWidth, box.maxHeight);
      if (newViewport != _viewport) {
        _viewport = newViewport;
        _clamp();
      }
      final s = scale;
      final m = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(1, 1, s)
        ..setEntry(0, 3, _offset.dx)
        ..setEntry(1, 3, _offset.dy);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: (e) => _onUp(e),
        onPointerCancel: (e) => _onUp(e, cancelled: true),
        onPointerHover: _onHover,
        onPointerSignal: _onSignal,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: const Color(0xFFE9E6DF))),
              Positioned(
                left: 0,
                top: 0,
                child: Transform(
                  transform: m,
                  child: SizedBox(
                    width: kPageWidth,
                    height: c.pageHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: PaperPainter(
                                style: paper,
                                color: widget.paperColor ?? const Color(0xFFFFFDF8),
                                columnRuleX: widget.columnRuleX,
                              ),
                            ),
                          ),
                        ),
                        if (widget.underlay != null)
                          Positioned(
                              left: 0, top: 0, width: kPageWidth, child: RepaintBoundary(child: widget.underlay!)),
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(painter: CommittedInkPainter(c)),
                          ),
                        ),
                        Positioned.fill(
                          child: RepaintBoundary(child: CustomPaint(painter: ActiveInkPainter(c))),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class PaperPainter extends CustomPainter {
  PaperPainter({required this.style, required this.color, this.columnRuleX});
  final PaperStyle style;
  final double? columnRuleX;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = color;
    canvas.drawRect(Offset.zero & size, bg);
    // soft page shadow edges
    final edge = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), edge);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), edge);

    const gap = 36.0;
    final line = Paint()
      ..color = const Color(0x1F3B6FE0)
      ..strokeWidth = 1;
    switch (style) {
      case PaperStyle.blank:
        break;
      case PaperStyle.lines:
        for (var y = gap * 3; y < size.height; y += gap) {
          canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), line);
        }
        final margin = Paint()
          ..color = const Color(0x33E5484D)
          ..strokeWidth = 1.2;
        canvas.drawLine(const Offset(72, 0), Offset(72, size.height), margin);
        break;
      case PaperStyle.grid:
        final minor = Paint()
          ..color = const Color(0x143B6FE0)
          ..strokeWidth = 0.8;
        for (var y = 0.0; y < size.height; y += gap / 1.5) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
        }
        for (var x = 0.0; x <= size.width; x += gap / 1.5) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
        }
        break;
      case PaperStyle.dots:
        final dot = Paint()..color = const Color(0x333B6FE0);
        for (var y = gap; y < size.height; y += gap) {
          for (var x = gap; x < size.width; x += gap) {
            canvas.drawCircle(Offset(x, y), 1.4, dot);
          }
        }
        break;
    }

    // 시험지처럼 단을 가르는 세로선 — 왼쪽은 문제, 오른쪽은 풀이 공간
    final rx = columnRuleX;
    if (rx != null && rx > 0 && rx < size.width - 60) {
      canvas.drawLine(
        Offset(rx, 108),
        Offset(rx, size.height - 24),
        Paint()
          ..color = const Color(0x2E1D2433)
          ..strokeWidth = 1.2,
      );
      final label = TextPainter(
        text: const TextSpan(
          text: '풀이',
          style: TextStyle(
            fontFamily: 'Pretendard', // 기본 글꼴에는 한글이 없다
            color: Color(0x5A1D2433),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(rx + 16, 74)); // 머리글 줄에 맞춘다 (위 도구막대에 가리지 않게)
    }
  }

  @override
  bool shouldRepaint(covariant PaperPainter old) =>
      old.style != style || old.color != color || old.columnRuleX != columnRuleX;
}

class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter(this.c) : super(repaint: c.committed);
  final InkController c;

  @override
  void paint(Canvas canvas, Size size) {
    final dragging = c.draggingSelection;
    if (dragging && c.selection.isNotEmpty) {
      StrokeRenderer.paintAll(canvas, c.strokes.where((s) => !c.selection.contains(s.id)));
    } else {
      StrokeRenderer.paintAll(canvas, c.strokes);
    }
  }

  @override
  bool shouldRepaint(covariant CommittedInkPainter old) => old.c != c;
}

class ActiveInkPainter extends CustomPainter {
  ActiveInkPainter(this.c) : super(repaint: Listenable.merge([c.activeTick, c.committed]));
  final InkController c;

  static final Paint _lasso = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = const Color(0xFF2F6BFF);
  static final Paint _lassoFill = Paint()..color = const Color(0x142F6BFF);
  static final Paint _cursor = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = const Color(0x99555555);
  static final Paint _cursorFill = Paint()..color = const Color(0x22FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final a = c.active;
    if (a != null) StrokeRenderer.paint(canvas, a, live: true);

    // selection (moving copy + bounds)
    if (c.selection.isNotEmpty) {
      if (c.draggingSelection) {
        canvas.save();
        canvas.translate(c.selectionOffset.dx, c.selectionOffset.dy);
        StrokeRenderer.paintAll(canvas, c.strokes.where((s) => c.selection.contains(s.id)));
        canvas.restore();
      }
      final b = c.selectionBounds;
      if (b != null) {
        final r = RRect.fromRectAndRadius(b.inflate(10), const Radius.circular(10));
        canvas.drawRRect(r, _lassoFill);
        _dashedRRect(canvas, r, _lasso);
      }
    }

    final lp = c.lassoPath;
    if (lp != null && lp.length > 1) {
      final path = Path()..moveTo(lp.first.dx, lp.first.dy);
      for (final p in lp.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(Path.from(path)..close(), _lassoFill);
      _dashedPath(canvas, path, _lasso);
    }

    final ec = c.eraserCursor;
    if (ec != null) {
      canvas.drawCircle(ec, c.eraserRadius, _cursorFill);
      canvas.drawCircle(ec, c.eraserRadius, _cursor);
    }

    // 자리 고르기 — 끌고 있는 사각형
    final pp = c.placePreview;
    if (pp != null && pp.width.abs() > 1 && pp.height.abs() > 1) {
      final r = RRect.fromRectAndRadius(pp, const Radius.circular(8));
      canvas.drawRRect(r, _lassoFill);
      _dashedRRect(canvas, r, _lasso);
    }
  }

  void _dashedRRect(Canvas canvas, RRect r, Paint p) => _dashedPath(canvas, Path()..addRRect(r), p);

  void _dashedPath(Canvas canvas, Path path, Paint p) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final seg = metric.extractPath(d, math.min(d + 8, metric.length));
        canvas.drawPath(seg, p);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(covariant ActiveInkPainter old) => old.c != c;
}
