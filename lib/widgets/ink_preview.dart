import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../ink/ink_model.dart';
import '../ink/stroke_renderer.dart';

/// Static thumbnail of a saved attempt's handwriting.
class InkThumbnail extends StatelessWidget {
  const InkThumbnail({super.key, required this.attemptId, this.height = 120});
  final String attemptId;
  final double height;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return FutureBuilder<InkDocument?>(
      future: app.loadAttemptInk(attemptId),
      builder: (context, snap) {
        final doc = snap.data;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.sheet,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: doc == null || doc.isEmpty
              ? const Center(
                  child: Text('필기 없음', style: TextStyle(color: AppColors.inkMuted, fontSize: 12.5)))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CustomPaint(painter: _FitPainter(doc.strokes), size: Size.infinite),
                ),
        );
      },
    );
  }
}

Rect _boundsOf(List<InkStroke> strokes) {
  Rect? r;
  for (final s in strokes) {
    r = r == null ? s.bounds : r.expandToInclude(s.bounds);
  }
  return r ?? Rect.zero;
}

class _FitPainter extends CustomPainter {
  _FitPainter(this.strokes, {this.limit});
  final List<InkStroke> strokes;
  final int? limit; // replay: only draw up to this many ms

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    final b = _boundsOf(strokes).inflate(16);
    final s = math.min(size.width / b.width, size.height / b.height);
    canvas.save();
    canvas.translate((size.width - b.width * s) / 2, (size.height - b.height * s) / 2);
    canvas.scale(s);
    canvas.translate(-b.left, -b.top);
    StrokeRenderer.paintAll(canvas, strokes);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FitPainter old) => old.strokes != strokes;
}

/// Animated replay of how the problem was solved (stroke by stroke, real timing compressed).
class InkReplay extends StatefulWidget {
  const InkReplay({super.key, required this.doc});
  final InkDocument doc;

  @override
  State<InkReplay> createState() => _InkReplayState();
}

class _InkReplayState extends State<InkReplay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final List<InkStroke> _ordered;
  late final List<int> _starts; // compressed timeline start per stroke
  late final int _total;
  double _speed = 2;
  double _t = 0; // ms on compressed timeline
  bool _playing = true;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ordered = [...widget.doc.strokes]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    // compress pauses between strokes to at most 600 ms
    var t = 0;
    _starts = [];
    for (var i = 0; i < _ordered.length; i++) {
      if (i > 0) {
        final prev = _ordered[i - 1];
        final gap = _ordered[i].startedAt - (prev.startedAt + prev.durationMs);
        t += prev.durationMs + math.min(math.max(gap, 0), 600);
      }
      _starts.add(t);
    }
    _total = _ordered.isEmpty ? 0 : _starts.last + _ordered.last.durationMs;
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration d) {
    final dt = (d - _last).inMicroseconds / 1000.0;
    _last = d;
    if (!_playing) return;
    setState(() {
      _t += dt * _speed;
      if (_t >= _total) {
        _t = _total.toDouble();
        _playing = false;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<InkStroke> _visible() {
    final out = <InkStroke>[];
    for (var i = 0; i < _ordered.length; i++) {
      final st = _starts[i];
      if (st > _t) break;
      final s = _ordered[i];
      final local = _t - st;
      if (local >= s.durationMs) {
        out.add(s);
      } else {
        final pts = s.points.where((p) => p.t <= local).toList();
        if (pts.isNotEmpty) out.add(s.copyWith(points: pts));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final all = _ordered;
    final b = _boundsOf(all);
    return Column(children: [
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.sheet,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CustomPaint(
              size: Size.infinite,
              painter: _ReplayPainter(_visible(), b),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        IconButton.filled(
          onPressed: () => setState(() {
            if (_t >= _total) _t = 0;
            _playing = !_playing;
          }),
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        Expanded(
          child: Slider(
            value: _total == 0 ? 0 : (_t / _total).clamp(0.0, 1.0),
            onChanged: (v) => setState(() {
              _t = v * _total;
              _playing = false;
            }),
          ),
        ),
        for (final sp in const [1.0, 2.0, 4.0])
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ChoiceChip(
              label: Text('${sp.toInt()}x'),
              selected: _speed == sp,
              onSelected: (_) => setState(() => _speed = sp),
            ),
          ),
      ]),
    ]);
  }
}

class _ReplayPainter extends CustomPainter {
  _ReplayPainter(this.strokes, this.bounds);
  final List<InkStroke> strokes;
  final Rect bounds;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.isEmpty) return;
    final b = bounds.inflate(20);
    final s = math.min(size.width / b.width, size.height / b.height);
    canvas.save();
    canvas.translate((size.width - b.width * s) / 2, (size.height - b.height * s) / 2);
    canvas.scale(s);
    canvas.translate(-b.left, -b.top);
    for (final st in strokes.where((e) => e.tool == InkTool.highlighter)) {
      StrokeRenderer.paint(canvas, st, live: true);
    }
    for (final st in strokes.where((e) => e.tool != InkTool.highlighter)) {
      StrokeRenderer.paint(canvas, st, live: true);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ReplayPainter old) => true;
}
