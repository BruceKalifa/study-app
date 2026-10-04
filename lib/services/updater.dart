import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// A newer build published by CI (version.json next to the APK in the "latest" release).
class AppUpdate {
  final int build;
  final String notes;
  final String apkUrl;
  const AppUpdate(this.build, this.notes, this.apkUrl);
}

/// In-app updates for the sideloaded Android app: check → download the APK → open the system installer.
/// Android always asks the user to confirm an install, and the first time asks to allow "이 출처의 앱 설치".
class Updater {
  Updater._();

  /// Turned off for the emulator smoke build (`--dart-define=AUTO_UPDATE=false`).
  static const bool enabled = bool.fromEnvironment('AUTO_UPDATE', defaultValue: true);
  static const String manifestUrl =
      'https://github.com/BruceKalifa/study-app/releases/download/latest/version.json';
  static const String _defaultApk = 'https://github.com/BruceKalifa/study-app/releases/download/latest/pulinote.apk';
  static const MethodChannel _ch = MethodChannel('pulinote/update');

  static bool get supported => Platform.isAndroid;

  static int? _installed;

  /// versionCode of the installed app (= CI build number).
  static Future<int> installedBuild() async {
    if (_installed != null) return _installed!;
    if (!supported) return 0;
    try {
      _installed = await _ch.invokeMethod<int>('versionCode') ?? 0;
    } catch (_) {
      _installed = 0;
    }
    return _installed!;
  }

  /// The newer build, or null (no update, offline, or not Android).
  static Future<AppUpdate?> check() async {
    if (!supported) return null;
    final installed = await installedBuild();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await res.transform(utf8.decoder).join());
      if (j is! Map) return null;
      final build = (j['build'] as num?)?.toInt() ?? 0;
      if (installed <= 0 || build <= installed) return null;
      return AppUpdate(build, '${j['notes'] ?? ''}', '${j['apk'] ?? _defaultApk}');
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads the APK into the cache folder (the installer reads it from there). Reports 0..1.
  static Future<File> download(AppUpdate u, {void Function(double progress)? onProgress}) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/pulinote-${u.build}.apk');
    final part = File('${file.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(u.apkUrl)).timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('다운로드 실패 (${res.statusCode})');
      final total = res.contentLength;
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress?.call(got / total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw const HttpException('다운로드가 중간에 끊겼어요');
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      // older downloads are no longer needed
      for (final f in dir.listSync()) {
        if (f is File && f.path != file.path) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
      return file;
    } finally {
      client.close(force: true);
    }
  }

  /// Android 8+: has the user allowed this app to install apps?
  static Future<bool> canInstall() async {
    try {
      return await _ch.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallSettings() async {
    try {
      await _ch.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }

  /// Opens the system installer for [apk] (the user taps 업데이트).
  static Future<bool> install(File apk) async {
    try {
      return await _ch.invokeMethod<bool>('install', {'path': apk.path}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
