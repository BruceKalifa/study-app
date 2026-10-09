import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 테스트용 문제 은행. 앱에는 싣지 않고 `test/fixtures/problems/` 에서 읽는다.
/// (앱에 들어 있는 `assets/problems/` 는 과목 이름만 있는 골격이다 — 교재는 서버에서 받는다.)
class FixtureBundle extends CachingAssetBundle {
  static const _prefix = 'assets/problems/';

  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(_prefix)) throw FlutterError('테스트 문제 은행에 없는 파일: $key');
    final f = File('test/fixtures/problems/${key.substring(_prefix.length)}');
    if (!f.existsSync()) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()));
  }
}

final FixtureBundle fixtureBundle = FixtureBundle();
