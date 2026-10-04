import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// PNG of what a [RepaintBoundary] (found by [key]) shows right now — e.g. the student's page with
/// their handwriting, attached to a question. Kept under ~2MB (the server limit is 2.5MB).
Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 1.25}) async {
  final ro = key.currentContext?.findRenderObject();
  if (ro is! RenderRepaintBoundary || !ro.attached) return null;
  var ratio = pixelRatio;
  for (var i = 0; i < 4; i++) {
    final img = await ro.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    if (bytes.length <= 2 * 1024 * 1024) return bytes;
    ratio *= 0.7;
  }
  return null;
}
