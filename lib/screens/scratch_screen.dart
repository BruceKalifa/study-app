import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_controller.dart';
import '../ink/ink_model.dart';
import '../ink/ink_toolbar.dart';
import '../ink/shape_hint.dart';

/// Free notebook (연습장): multiple pages, auto-saved.
class ScratchScreen extends StatefulWidget {
  const ScratchScreen({super.key});

  @override
  State<ScratchScreen> createState() => _ScratchScreenState();
}

class _ScratchScreenState extends State<ScratchScreen> {
  late AppState _app;
  bool _init = false;
  int _pages = 1;
  int _page = 0;
  InkController? _ink;
  Timer? _save;
  final GlobalKey<InkCanvasState> _canvas = GlobalKey<InkCanvasState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _app = AppScope.read(context);
      _load();
    }
  }

  Future<void> _load() async {
    final raw = await _app.readProfileFile('notes/index.json');
    if (raw != null) {
      try {
        _pages = ((jsonDecode(raw) as Map)['pages'] as num).toInt().clamp(1, 999);
      } catch (_) {}
    }
    await _openPage(0);
  }

  Future<void> _openPage(int i) async {
    _flush();
    final old = _ink;
    if (old != null) {
      old.committed.removeListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final c = InkController(settings: _app.ink);
    final raw = await _app.readProfileFile('notes/page_$i.json');
    if (raw != null) {
      try {
        c.load(InkDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    c.committed.addListener(_changed);
    if (!mounted) return;
    setState(() {
      _ink = c;
      _page = i;
    });
  }

  void _changed() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 1), _flush);
  }

  void _flush() {
    _save?.cancel();
    final c = _ink;
    if (c == null) return;
    _app.writeProfileFile('notes/page_$_page.json', jsonEncode(c.toDocument().toJson()));
  }

  Future<void> _addPage() async {
    setState(() => _pages++);
    await _app.writeProfileFile('notes/index.json', jsonEncode({'pages': _pages}));
    await _openPage(_pages - 1);
  }

  @override
  void dispose() {
    _flush();
    final c = _ink;
    if (c != null) {
      c.committed.removeListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 8),
          const Text('연습장', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -1)),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < _pages; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${i + 1}쪽'),
                      selected: _page == i,
                      onSelected: (_) => _openPage(i),
                    ),
                  ),
                IconButton(tooltip: '새 페이지', onPressed: _addPage, icon: const Icon(Icons.add_circle_outline_rounded)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: c == null
              ? const Center(child: CircularProgressIndicator())
              : ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(children: [
                    Positioned.fill(child: InkCanvas(key: _canvas, controller: c)),
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 12,
                      child: InkToolbar(
                        controller: c,
                        onSettingsChanged: () => _app.updateInk((_) {}),
                        onResetView: () => _canvas.currentState?.resetView(),
                      ),
                    ),
                    Positioned(left: 0, right: 0, bottom: 18, child: Center(child: ShapeSnapHint(controller: c))),
                    Positioned(left: 16, right: 16, bottom: 64, child: Center(child: PlacingHint(controller: c))),
                    Positioned(
                      right: 18,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Text('${_page + 1} / $_pages',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                      ),
                    ),
                  ]),
                ),
        ),
      ]),
    );
  }
}
