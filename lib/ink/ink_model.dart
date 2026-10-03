import 'dart:math' as math;
import 'dart:ui';

/// Tools a stroke can be drawn with. Eraser/lasso never become strokes.
enum InkTool { pen, highlighter, eraser, lasso }

/// Logical page width shared by every device (see docs/live-protocol.md).
const double kPageWidth = 1000;

class InkPoint {
  final double x;
  final double y;

  /// Normalised pressure 0..1.
  final double p;

  /// Milliseconds since the stroke started.
  final int t;

  const InkPoint(this.x, this.y, this.p, this.t);

  Offset get offset => Offset(x, y);

  InkPoint translate(double dx, double dy) => InkPoint(x + dx, y + dy, p, t);

  List<num> toJson() => [_r(x), _r(y), _r3(p), t];

  static InkPoint fromJson(Object? raw) {
    final l = raw as List;
    final n = l.length;
    return InkPoint(
      (l[0] as num).toDouble(),
      (l[1] as num).toDouble(),
      n > 2 ? (l[2] as num).toDouble() : 0.5,
      n > 3 ? (l[3] as num).toInt() : 0,
    );
  }

  static double _r(double v) => (v * 10).roundToDouble() / 10;
  static double _r3(double v) => (v * 1000).roundToDouble() / 1000;
}

class InkStroke {
  final String id;
  final InkTool tool;

  /// ARGB colour.
  final int color;

  /// Base width in page units.
  final double width;

  /// Wall-clock start (ms since epoch) — used for replay ordering.
  final int startedAt;
  final List<InkPoint> points;

  InkStroke({
    required this.id,
    required this.tool,
    required this.color,
    required this.width,
    required this.startedAt,
    required this.points,
  });

  // ---- caches (not serialised) ----
  Rect? _bounds;

  /// Render geometry cache owned by the stroke renderer; cleared via [invalidate].
  Object? renderCache;

  void invalidate() {
    renderCache = null;
    _bounds = null;
  }

  Rect get bounds {
    final b = _bounds;
    if (b != null) return b;
    if (points.isEmpty) return _bounds = Rect.zero;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final pad = width;
    return _bounds = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  int get durationMs => points.isEmpty ? 0 : points.last.t;

  InkStroke copyWith({String? id, int? color, double? width, List<InkPoint>? points, int? startedAt}) =>
      InkStroke(
        id: id ?? this.id,
        tool: tool,
        color: color ?? this.color,
        width: width ?? this.width,
        startedAt: startedAt ?? this.startedAt,
        points: points ?? List<InkPoint>.of(this.points),
      );

  InkStroke translated(double dx, double dy) =>
      copyWith(points: [for (final p in points) p.translate(dx, dy)]);

  String get colorHex => '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool == InkTool.highlighter ? 'highlighter' : 'pen',
        'color': colorHex,
        'alpha': (color >> 24) & 0xFF,
        'width': width,
        'startedAt': startedAt,
        'points': [for (final p in points) p.toJson()],
      };

  /// Wire format for live sync (docs/live-protocol.md).
  Map<String, dynamic> toLiveJson() => {
        'id': id,
        'tool': tool == InkTool.highlighter ? 'highlighter' : 'pen',
        'color': colorHex,
        'width': width,
        'points': [for (final p in points) [InkPoint._r(p.x), InkPoint._r(p.y), InkPoint._r3(p.p)]],
      };

  static InkStroke fromJson(Map<String, dynamic> j) {
    final hex = (j['color'] as String? ?? '#000000').replaceAll('#', '');
    final alpha = (j['alpha'] as num?)?.toInt() ?? 0xFF;
    final rgb = int.tryParse(hex, radix: 16) ?? 0;
    return InkStroke(
      id: j['id'] as String? ?? newInkId(),
      tool: j['tool'] == 'highlighter' ? InkTool.highlighter : InkTool.pen,
      color: (alpha << 24) | (rgb & 0xFFFFFF),
      width: (j['width'] as num?)?.toDouble() ?? 3,
      startedAt: (j['startedAt'] as num?)?.toInt() ?? 0,
      points: [for (final p in (j['points'] as List? ?? const [])) InkPoint.fromJson(p)],
    );
  }
}

/// A page of ink (one per problem attempt / scratch page).
class InkDocument {
  final List<InkStroke> strokes;
  double pageHeight;

  InkDocument({List<InkStroke>? strokes, this.pageHeight = 1400}) : strokes = strokes ?? <InkStroke>[];

  bool get isEmpty => strokes.isEmpty;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'pageHeight': pageHeight,
        'strokes': [for (final s in strokes) s.toJson()],
      };

  static InkDocument fromJson(Map<String, dynamic> j) => InkDocument(
        pageHeight: (j['pageHeight'] as num?)?.toDouble() ?? 1400,
        strokes: [
          for (final s in (j['strokes'] as List? ?? const []))
            InkStroke.fromJson((s as Map).cast<String, dynamic>()),
        ],
      );
}

int _idCounter = 0;
final math.Random _idRand = math.Random();

String newInkId() {
  _idCounter = (_idCounter + 1) & 0xFFFFFF;
  final r = _idRand.nextInt(0x7FFFFFFF).toRadixString(36);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$r${_idCounter.toRadixString(36)}';
}

/// Distance from point p to segment ab.
double distToSegment(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx, aby = b.dy - a.dy;
  final len2 = abx * abx + aby * aby;
  if (len2 <= 1e-9) return (p - a).distance;
  var t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = a.dx + abx * t, cy = a.dy + aby * t;
  final dx = p.dx - cx, dy = p.dy - cy;
  return math.sqrt(dx * dx + dy * dy);
}

/// Even-odd point-in-polygon.
bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if (((a.dy > p.dy) != (b.dy > p.dy)) &&
        (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / ((b.dy - a.dy) == 0 ? 1e-9 : (b.dy - a.dy)) + a.dx)) {
      inside = !inside;
    }
  }
  return inside;
}
