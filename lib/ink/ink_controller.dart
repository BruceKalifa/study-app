import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'ink_model.dart';
import 'shape_snap.dart';

/// Receives ink changes for live sharing (implemented by LiveSync).
abstract class InkSyncSink {
  void strokeBegin(InkStroke s);
  void strokePoints(String id, List<InkPoint> pts);
  void strokeEnd(String id);
  void erase(List<String> ids);
  void restore(List<InkStroke> all);
  void clear();
}

enum EraserMode { stroke, area }

enum PaperStyle { blank, lines, grid, dots }

/// User-adjustable ink preferences (persisted by AppState).
class InkSettings {
  int penColor;
  double penWidth;
  int highlighterColor;
  double highlighterWidth;
  EraserMode eraserMode;
  double eraserSize;
  bool fingerDraws;
  bool pressure;
  bool holdToStraighten;

  /// 손으로 그린 원·삼각형·사각형 따위를 손을 떼면 반듯하게 맞춘다.
  bool shapeSnap;
  bool twoFingerUndo;
  PaperStyle paper;
  List<int> palette;

  InkSettings({
    this.penColor = 0xFF1B2A4A,
    this.penWidth = 3.2,
    this.highlighterColor = 0x66FFD54A,
    this.highlighterWidth = 22,
    this.eraserMode = EraserMode.stroke,
    this.eraserSize = 22,
    this.fingerDraws = false,
    this.pressure = true,
    this.holdToStraighten = true,
    this.shapeSnap = true,
    this.twoFingerUndo = true,
    this.paper = PaperStyle.grid,
    List<int>? palette,
  }) : palette = palette ?? List<int>.of(defaultPalette);

  static const List<int> defaultPalette = [
    0xFF1B2A4A, // ink navy
    0xFF111111, // black
    0xFF2F6BFF, // blue
    0xFFE5484D, // red
    0xFF16A34A, // green
    0xFF8B5CF6, // violet
    0xFFF97316, // orange
  ];

  static const List<int> highlighterPalette = [
    0x66FFD54A,
    0x5539E39B,
    0x55FF7AB6,
    0x5560A5FA,
    0x55FB923C,
  ];

  Map<String, dynamic> toJson() => {
        'penColor': penColor,
        'penWidth': penWidth,
        'highlighterColor': highlighterColor,
        'highlighterWidth': highlighterWidth,
        'eraserMode': eraserMode.name,
        'eraserSize': eraserSize,
        'fingerDraws': fingerDraws,
        'pressure': pressure,
        'holdToStraighten': holdToStraighten,
        'shapeSnap': shapeSnap,
        'twoFingerUndo': twoFingerUndo,
        'paper': paper.name,
        'palette': palette,
      };

  static InkSettings fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    double d(Object? v, double f) => v is num ? v.toDouble() : f;
    int i(Object? v, int f) => v is num ? v.toInt() : f;
    bool b(Object? v, bool f) => v is bool ? v : f;
    final pal = j['palette'];
    return InkSettings(
      penColor: i(j['penColor'], 0xFF1B2A4A),
      penWidth: d(j['penWidth'], 3.2),
      highlighterColor: i(j['highlighterColor'], 0x66FFD54A),
      highlighterWidth: d(j['highlighterWidth'], 22),
      eraserMode: pick(EraserMode.values, j['eraserMode'], EraserMode.stroke),
      eraserSize: d(j['eraserSize'], 22),
      fingerDraws: b(j['fingerDraws'], false),
      pressure: b(j['pressure'], true),
      holdToStraighten: b(j['holdToStraighten'], true),
      shapeSnap: b(j['shapeSnap'], true),
      twoFingerUndo: b(j['twoFingerUndo'], true),
      paper: pick(PaperStyle.values, j['paper'], PaperStyle.grid),
      palette: pal is List ? [for (final c in pal) if (c is num) c.toInt()] : null,
    );
  }
}

/// Owns a page of ink and every editing operation on it.
/// All coordinates are page coordinates (width [kPageWidth]).
class InkController extends ChangeNotifier {
  InkController({InkDocument? document, InkSettings? settings, this.autoExtend = true})
      : settings = settings ?? InkSettings(),
        _strokes = List<InkStroke>.of(document?.strokes ?? const []),
        pageHeight = document?.pageHeight ?? 1400;

  InkSettings settings;
  final bool autoExtend;
  InkSyncSink? sink;

  List<InkStroke> _strokes;
  List<InkStroke> get strokes => _strokes;
  double pageHeight;

  InkTool _tool = InkTool.pen;
  InkTool get tool => _tool;
  set tool(InkTool t) {
    if (_tool == t) return;
    _tool = t;
    if (t != InkTool.lasso) {
      clearSelection(notify: false);
      activeTick.value++;
      committed.value++;
    }
    notifyListeners();
  }

  /// Bumps whenever committed strokes change (drives the committed layer).
  final ValueNotifier<int> committed = ValueNotifier<int>(0);

  /// Bumps for every live change (active stroke, lasso, cursor).
  final ValueNotifier<int> activeTick = ValueNotifier<int>(0);

  // ---------- active gesture state ----------
  InkStroke? active;
  InkTool? _gestureTool;
  InkTool? get gestureTool => _gestureTool;
  int _strokeStart = 0;
  List<Offset>? lassoPath;
  Offset? eraserCursor;
  double get eraserRadius => settings.eraserSize / 2;

  // straighten
  Timer? _holdTimer;
  bool _straightened = false;
  Offset? _holdAnchor;

  // eraser gesture bookkeeping
  bool _eraseSnapshotTaken = false;
  Offset? _lastErasePos;

  // live point batching
  final List<InkPoint> _pendingLive = [];
  int _lastLiveFlush = 0;

  // ---------- selection ----------
  final Set<String> selection = <String>{};
  Offset selectionOffset = Offset.zero;
  bool _draggingSelection = false;
  bool get draggingSelection => _draggingSelection;
  Offset? _dragStart;

  Rect? get selectionBounds {
    if (selection.isEmpty) return null;
    Rect? r;
    for (final s in _strokes) {
      if (!selection.contains(s.id)) continue;
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    return r?.shift(selectionOffset);
  }

  // ---------- undo / redo (snapshot based; strokes are immutable once committed) ----------
  final List<List<InkStroke>> _undo = [];
  final List<List<InkStroke>> _redo = [];
  static const int _maxUndo = 120;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _snapshot() {
    _undo.add(List<InkStroke>.of(_strokes));
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  void _commitChanged() {
    committed.value++;
    notifyListeners();
  }

  void undo() {
    if (!canUndo || active != null) return;
    _redo.add(_strokes);
    _strokes = _undo.removeLast();
    clearSelection(notify: false);
    sink?.restore(_strokes);
    _commitChanged();
  }

  void redo() {
    if (!canRedo || active != null) return;
    _undo.add(_strokes);
    _strokes = _redo.removeLast();
    clearSelection(notify: false);
    sink?.restore(_strokes);
    _commitChanged();
  }

  void clearAll() {
    if (_strokes.isEmpty) return;
    _snapshot();
    _strokes = [];
    clearSelection(notify: false);
    sink?.clear();
    _commitChanged();
  }

  /// Replace the whole document (e.g. loading a saved attempt).
  void load(InkDocument doc) {
    _strokes = List<InkStroke>.of(doc.strokes);
    pageHeight = doc.pageHeight;
    _undo.clear();
    _redo.clear();
    clearSelection(notify: false);
    _commitChanged();
  }

  InkDocument toDocument() => InkDocument(strokes: List<InkStroke>.of(_strokes), pageHeight: pageHeight);

  bool get isEmpty => _strokes.isEmpty;

  // =====================================================================
  // Pointer API (called by InkCanvas with page coordinates)
  // =====================================================================

  /// Starts a gesture. [forceEraser] = S Pen side button / eraser tip.
  void pointerDown(Offset pos, double pressure, {bool forceEraser = false}) {
    _cancelHold();
    final t = forceEraser ? InkTool.eraser : _tool;

    // Selection dragging takes precedence when touching inside the selection.
    final sb = selectionBounds;
    if (!forceEraser && sb != null) {
      if (sb.inflate(12).contains(pos)) {
        _draggingSelection = true;
        _dragStart = pos;
        _gestureTool = InkTool.lasso;
        activeTick.value++;
        committed.value++;
        return;
      }
      clearSelection();
    }

    _gestureTool = t;
    switch (t) {
      case InkTool.pen:
      case InkTool.highlighter:
        _beginStroke(pos, pressure, t);
        break;
      case InkTool.eraser:
        _eraseSnapshotTaken = false;
        _lastErasePos = pos;
        eraserCursor = pos;
        _eraseAt(pos);
        activeTick.value++;
        break;
      case InkTool.lasso:
        lassoPath = [pos];
        activeTick.value++;
        break;
    }
  }

  void pointerMove(Offset pos, double pressure) {
    final g = _gestureTool;
    if (g == null) return;
    if (_draggingSelection) {
      selectionOffset = pos - (_dragStart ?? pos);
      activeTick.value++;
      return;
    }
    switch (g) {
      case InkTool.pen:
      case InkTool.highlighter:
        _extendStroke(pos, pressure);
        break;
      case InkTool.eraser:
        final last = _lastErasePos ?? pos;
        final d = (pos - last).distance;
        final step = math.max(2.0, eraserRadius * 0.5);
        final n = (d / step).ceil().clamp(1, 60);
        for (var i = 1; i <= n; i++) {
          _eraseAt(Offset.lerp(last, pos, i / n)!);
        }
        _lastErasePos = pos;
        eraserCursor = pos;
        activeTick.value++;
        break;
      case InkTool.lasso:
        final lp = lassoPath;
        if (lp != null && (lp.isEmpty || (lp.last - pos).distance > 2)) {
          lp.add(pos);
          activeTick.value++;
        }
        break;
    }
  }

  void pointerUp() {
    _cancelHold();
    final g = _gestureTool;
    _gestureTool = null;
    if (_draggingSelection) {
      _finishSelectionDrag();
      return;
    }
    if (g == null) return;
    switch (g) {
      case InkTool.pen:
      case InkTool.highlighter:
        _endStroke();
        break;
      case InkTool.eraser:
        eraserCursor = null;
        _lastErasePos = null;
        activeTick.value++;
        if (_eraseSnapshotTaken) _commitChanged();
        _eraseSnapshotTaken = false;
        break;
      case InkTool.lasso:
        _finishLasso();
        break;
    }
  }

  void pointerCancel() {
    _cancelHold();
    if (active != null) {
      sink?.erase([active!.id]);
      active = null;
    }
    _gestureTool = null;
    lassoPath = null;
    eraserCursor = null;
    _draggingSelection = false;
    selectionOffset = Offset.zero;
    activeTick.value++;
    if (_eraseSnapshotTaken) _commitChanged();
    _eraseSnapshotTaken = false;
  }

  /// Switch tool mid-gesture (S Pen button pressed/released while touching).
  void switchGestureTool(Offset pos, double pressure, {required bool eraser}) {
    final g = _gestureTool;
    if (g == null) return;
    final isEraser = g == InkTool.eraser;
    if (isEraser == eraser) return;
    pointerUp();
    pointerDown(pos, pressure, forceEraser: eraser);
  }

  // ---------------- strokes ----------------
  void _beginStroke(Offset pos, double pressure, InkTool t) {
    _strokeStart = DateTime.now().millisecondsSinceEpoch;
    _straightened = false;
    final s = InkStroke(
      id: newInkId(),
      tool: t,
      color: t == InkTool.highlighter ? settings.highlighterColor : settings.penColor,
      width: t == InkTool.highlighter ? settings.highlighterWidth : settings.penWidth,
      startedAt: _strokeStart,
      points: [InkPoint(pos.dx, pos.dy, _p(pressure), 0)],
    );
    active = s;
    _pendingLive.clear();
    _lastLiveFlush = _strokeStart;
    sink?.strokeBegin(s);
    _armHold(pos);
    activeTick.value++;
  }

  double _p(double pressure) => settings.pressure ? pressure.clamp(0.0, 1.0) : 0.55;

  void _extendStroke(Offset pos, double pressure) {
    final s = active;
    if (s == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_straightened) {
      // keep it a straight line; move the end point
      final first = s.points.first;
      final p = s.points.last.p;
      s.points
        ..clear()
        ..add(first)
        ..add(InkPoint(pos.dx, pos.dy, p, now - _strokeStart));
      s.invalidate();
      activeTick.value++;
      return;
    }
    final last = s.points.last;
    if ((Offset(last.x, last.y) - pos).distance < 0.35) return;
    final pt = InkPoint(pos.dx, pos.dy, _p(pressure), now - _strokeStart);
    s.points.add(pt);
    s.invalidate();
    _pendingLive.add(pt);
    if (now - _lastLiveFlush >= 50) _flushLive(now);
    if (_holdAnchor == null || (pos - _holdAnchor!).distance > 4) _armHold(pos);
    if (autoExtend && pos.dy > pageHeight - 260) {
      pageHeight += 800;
      notifyListeners();
    }
    activeTick.value++;
  }

  void _flushLive(int now) {
    final s = active;
    if (s == null || _pendingLive.isEmpty) return;
    sink?.strokePoints(s.id, List<InkPoint>.of(_pendingLive));
    _pendingLive.clear();
    _lastLiveFlush = now;
  }

  void _endStroke() {
    final s = active;
    if (s == null) return;
    _flushLive(DateTime.now().millisecondsSinceEpoch);
    active = null;
    s.invalidate();
    _snapshot();
    var changed = _straightened;
    // 도형 맞추기 — 원·삼각형·사각형처럼 그리면 반듯하게 (글씨 크기는 건드리지 않는다)
    if (settings.shapeSnap && !_straightened && (s.tool == InkTool.pen || s.tool == InkTool.highlighter)) {
      final snapped = snapShape(s.points);
      if (snapped != null) {
        _snappedOriginal = List<InkPoint>.of(s.points);
        _snappedStrokeId = s.id;
        s.points
          ..clear()
          ..addAll(snapped.points);
        s.invalidate();
        changed = true;
        lastSnap.value = snapped.kind;
      }
    }
    _strokes = [..._strokes, s];
    if (changed) {
      sink?.erase([s.id]);
      sink?.strokeBegin(s);
    }
    sink?.strokeEnd(s.id);
    activeTick.value++;
    _commitChanged();
  }

  // ---------------- 자리 고르기 (함수 그래프 놓기) ----------------
  /// 자리를 고르는 중이면 캔버스가 그리는 대신 누른 자리를 받는다.
  final ValueNotifier<PlaceRequest?> placing = ValueNotifier<PlaceRequest?>(null);

  /// 손가락이 놓인 자리에 놓일 네모 (캔버스가 점선으로 미리 그린다).
  Rect? placePreview;

  void startPlacing(PlaceRequest r) {
    placing.value = r;
    placePreview = null;
    activeTick.value++;
  }

  void cancelPlacing() {
    if (placing.value == null) return;
    placing.value = null;
    placePreview = null;
    activeTick.value++;
  }

  /// 누른 자리를 가운데로 한 네모 — 종이 밖으로 나가면 안으로 밀어 넣는다.
  Rect placeRectAt(Offset center, PlaceRequest r) {
    final w = math.min(r.defaultSize.width, kPageWidth - 16);
    final h = math.min(r.defaultSize.height, math.max(40.0, pageHeight - 16));
    final left = (center.dx - w / 2).clamp(8.0, math.max(8.0, kPageWidth - w - 8));
    final top = (center.dy - h / 2).clamp(8.0, math.max(8.0, pageHeight - h - 8));
    return Rect.fromLTWH(left, top, w, h);
  }

  /// 캔버스가 부른다 — 누른 자리를 가운데로 [PlaceRequest.onPick] 을 부른다.
  void finishPlacing(Offset center) {
    final r = placing.value;
    final rect = r == null ? null : placeRectAt(center, r);
    placing.value = null;
    placePreview = null;
    activeTick.value++;
    if (r != null) r.onPick(rect!);
  }

  // ---------------- 도형 맞추기 ----------------
  /// 마지막으로 맞춘 도형 (화면이 "원으로 맞췄어요 · 되돌리기" 를 띄우는 데 쓴다).
  final ValueNotifier<ShapeKind?> lastSnap = ValueNotifier<ShapeKind?>(null);
  List<InkPoint>? _snappedOriginal;
  String? _snappedStrokeId;

  /// 방금 맞춘 도형을 손으로 그린 모양으로 되돌린다.
  void undoShapeSnap() {
    final id = _snappedStrokeId;
    final orig = _snappedOriginal;
    _snappedStrokeId = null;
    _snappedOriginal = null;
    lastSnap.value = null;
    if (id == null || orig == null) return;
    final i = _strokes.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final s = _strokes[i];
    s.points
      ..clear()
      ..addAll(orig);
    s.invalidate();
    sink?.erase([s.id]);
    sink?.strokeBegin(s);
    sink?.strokeEnd(s.id);
    _commitChanged();
  }

  /// 만들어 둔 획들을 그대로 넣는다 (함수 그래프·좌표축). 한 번에 되돌릴 수 있다.
  void addStrokes(List<InkStroke> added) {
    if (added.isEmpty) return;
    _snapshot();
    _strokes = [..._strokes, ...added];
    for (final s in added) {
      sink?.strokeBegin(s);
      sink?.strokeEnd(s.id);
    }
    var bottom = pageHeight;
    for (final s in added) {
      bottom = math.max(bottom, s.bounds.bottom + 120);
    }
    if (autoExtend && bottom > pageHeight) pageHeight = bottom;
    _commitChanged();
    notifyListeners();
  }

  // hold-to-straighten
  void _armHold(Offset pos) {
    _holdTimer?.cancel();
    _holdAnchor = pos;
    if (!settings.holdToStraighten) return;
    _holdTimer = Timer(const Duration(milliseconds: 650), _straighten);
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdAnchor = null;
  }

  void _straighten() {
    final s = active;
    if (s == null || s.points.length < 4 || _straightened) return;
    final first = s.points.first, last = s.points.last;
    final chord = (last.offset - first.offset).distance;
    if (chord < 40) return;
    // only straighten if the stroke is roughly line-like (not a scribble)
    var pathLen = 0.0;
    for (var i = 1; i < s.points.length; i++) {
      pathLen += (s.points[i].offset - s.points[i - 1].offset).distance;
    }
    if (pathLen > chord * 1.6) return;
    var avgP = 0.0;
    for (final p in s.points) {
      avgP += p.p;
    }
    avgP /= s.points.length;
    s.points
      ..clear()
      ..add(InkPoint(first.x, first.y, avgP, 0))
      ..add(InkPoint(last.x, last.y, avgP, last.t));
    s.invalidate();
    _straightened = true;
    _pendingLive.clear();
    activeTick.value++;
  }

  // ---------------- eraser ----------------
  void _ensureEraseSnapshot() {
    if (_eraseSnapshotTaken) return;
    _snapshot();
    _eraseSnapshotTaken = true;
  }

  bool _strokeHit(InkStroke s, Offset p, double r) {
    if (!s.bounds.inflate(r).contains(p)) return false;
    final pts = s.points;
    final rr = r + s.width / 2;
    if (pts.length == 1) return (pts.first.offset - p).distance <= rr;
    for (var i = 1; i < pts.length; i++) {
      if (distToSegment(p, pts[i - 1].offset, pts[i].offset) <= rr) return true;
    }
    return false;
  }

  void _eraseAt(Offset p) {
    final r = eraserRadius;
    if (settings.eraserMode == EraserMode.stroke) {
      final hit = <String>[];
      for (final s in _strokes) {
        if (_strokeHit(s, p, r)) hit.add(s.id);
      }
      if (hit.isEmpty) return;
      _ensureEraseSnapshot();
      _strokes = [for (final s in _strokes) if (!hit.contains(s.id)) s];
      sink?.erase(hit);
      committed.value++;
      return;
    }
    // area eraser: split strokes around the eraser disc
    var changed = false;
    final out = <InkStroke>[];
    for (final s in _strokes) {
      if (!_strokeHit(s, p, r)) {
        out.add(s);
        continue;
      }
      final rr = r + s.width * 0.3;
      // densify so long segments (fast strokes, straightened lines) can be cut in the middle
      final dense = <InkPoint>[];
      final step = math.max(1.0, rr / 2);
      for (var i = 0; i < s.points.length; i++) {
        final b = s.points[i];
        if (i > 0) {
          final a = s.points[i - 1];
          final d = (b.offset - a.offset).distance;
          final n = (d / step).floor();
          for (var k = 1; k < n; k++) {
            final f = k / n;
            dense.add(InkPoint(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.p + (b.p - a.p) * f,
                a.t + ((b.t - a.t) * f).round()));
          }
        }
        dense.add(b);
      }
      if (!dense.any((pt) => (pt.offset - p).distance <= rr)) {
        out.add(s);
        continue;
      }
      changed = true;
      final pieces = <List<InkPoint>>[];
      var cur = <InkPoint>[];
      for (final pt in dense) {
        if ((pt.offset - p).distance <= rr) {
          if (cur.isNotEmpty) pieces.add(cur);
          cur = <InkPoint>[];
        } else {
          cur.add(pt);
        }
      }
      if (cur.isNotEmpty) pieces.add(cur);
      sink?.erase([s.id]);
      for (final piece in pieces) {
        if (piece.length < 2 && s.points.length > 1) continue;
        final ns = s.copyWith(id: newInkId(), points: piece);
        out.add(ns);
        sink?.strokeBegin(ns);
        sink?.strokeEnd(ns.id);
      }
    }
    if (!changed) return;
    _ensureEraseSnapshot();
    _strokes = out;
    committed.value++;
  }

  // ---------------- lasso / selection ----------------
  void _finishLasso() {
    final poly = lassoPath;
    lassoPath = null;
    selection.clear();
    selectionOffset = Offset.zero;
    if (poly != null && poly.length > 4) {
      for (final s in _strokes) {
        if (s.points.isEmpty) continue;
        final b = s.bounds;
        // quick reject using polygon bounds
        var inside = 0;
        final stepN = math.max(1, s.points.length ~/ 24);
        var total = 0;
        for (var i = 0; i < s.points.length; i += stepN) {
          total++;
          if (pointInPolygon(s.points[i].offset, poly)) inside++;
        }
        if (total > 0 && inside / total >= 0.6) {
          selection.add(s.id);
        } else if (s.points.length == 1 && pointInPolygon(b.center, poly)) {
          selection.add(s.id);
        }
      }
    }
    activeTick.value++;
    _commitChanged();
  }

  void _finishSelectionDrag() {
    _draggingSelection = false;
    final d = selectionOffset;
    selectionOffset = Offset.zero;
    if (d.distance > 0.5) {
      _snapshot();
      _strokes = [
        for (final s in _strokes) selection.contains(s.id) ? s.translated(d.dx, d.dy) : s,
      ];
      if (autoExtend) {
        for (final s in _strokes) {
          if (selection.contains(s.id) && s.bounds.bottom > pageHeight - 200) {
            pageHeight = s.bounds.bottom + 600;
          }
        }
      }
      sink?.restore(_strokes);
    }
    activeTick.value++;
    _commitChanged();
  }

  void clearSelection({bool notify = true}) {
    if (selection.isEmpty && selectionOffset == Offset.zero) return;
    selection.clear();
    selectionOffset = Offset.zero;
    _draggingSelection = false;
    if (notify) {
      activeTick.value++;
      _commitChanged();
    }
  }

  void deleteSelection() {
    if (selection.isEmpty) return;
    _snapshot();
    final ids = selection.toList();
    _strokes = [for (final s in _strokes) if (!selection.contains(s.id)) s];
    selection.clear();
    sink?.erase(ids);
    activeTick.value++;
    _commitChanged();
  }

  void recolorSelection(int color) {
    if (selection.isEmpty) return;
    _snapshot();
    _strokes = [
      for (final s in _strokes)
        selection.contains(s.id) && s.tool == InkTool.pen ? s.copyWith(color: color) : s,
    ];
    sink?.restore(_strokes);
    _commitChanged();
  }

  void duplicateSelection() {
    if (selection.isEmpty) return;
    _snapshot();
    final copies = <InkStroke>[];
    for (final s in _strokes) {
      if (selection.contains(s.id)) {
        copies.add(s.translated(24, 24).copyWith(id: newInkId()));
      }
    }
    _strokes = [..._strokes, ...copies];
    selection
      ..clear()
      ..addAll(copies.map((e) => e.id));
    sink?.restore(_strokes);
    activeTick.value++;
    _commitChanged();
  }

  /// Ink recognition helpers: strokes inside [rect] (page coords).
  List<InkStroke> strokesIn(Rect rect) => [for (final s in _strokes) if (rect.overlaps(s.bounds)) s];

  void notifySettingsChanged() => notifyListeners();

  @override
  void dispose() {
    _holdTimer?.cancel();
    committed.dispose();
    activeTick.dispose();
    lastSnap.dispose();
    placing.dispose();
    super.dispose();
  }
}

/// 캔버스에서 자리를 고르는 요청 (함수 그래프를 놓을 자리).
class PlaceRequest {
  const PlaceRequest({required this.hint, required this.defaultSize, required this.onPick});

  /// 화면 위에 띄울 안내 ("그래프를 놓을 자리를 한 번 누르세요").
  final String hint;

  /// 누른 자리를 가운데로 놓을 크기.
  final Size defaultSize;
  final void Function(Rect rect) onPick;
}
