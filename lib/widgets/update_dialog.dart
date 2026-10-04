import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../services/updater.dart';

/// Download the new build right away, then open the installer.
Future<void> showUpdateDialog(BuildContext context, AppUpdate u) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(update: u),
    );

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.update});
  final AppUpdate update;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { downloading, needPermission, installing, failed }

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  _Phase _phase = _Phase.downloading;
  double _progress = 0;
  String _error = '';
  File? _apk;
  bool _waitingSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _download();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from "이 출처의 앱 설치 허용" settings → try again
    if (state == AppLifecycleState.resumed && _waitingSettings) {
      _waitingSettings = false;
      _install();
    }
  }

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    try {
      final f = await Updater.download(widget.update, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      _apk = f;
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e is HttpException ? e.message : '인터넷 연결을 확인하고 다시 시도해 주세요';
      });
    }
  }

  Future<void> _install() async {
    final f = _apk;
    if (f == null || !mounted) return;
    if (!await Updater.canInstall()) {
      if (mounted) setState(() => _phase = _Phase.needPermission);
      return;
    }
    setState(() => _phase = _Phase.installing);
    final ok = await Updater.install(f);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _phase = _Phase.failed;
        _error = '설치 화면을 열지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final Widget body;
    final List<Widget> actions;
    switch (_phase) {
      case _Phase.downloading:
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('새 버전을 받는 중… ${(_progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8, borderRadius: BorderRadius.circular(4)),
        ]);
        actions = [TextButton(onPressed: () => Navigator.pop(context), child: const Text('나중에'))];
      case _Phase.needPermission:
        body = const Text(
          '처음 한 번만 허용이 필요해요.\n설정에서 "이 출처의 앱 설치 허용"을 켜고 돌아오면 바로 설치 화면이 열려요.',
          style: TextStyle(height: 1.5),
        );
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('나중에')),
          FilledButton(
            onPressed: () {
              _waitingSettings = true;
              Updater.openInstallSettings();
            },
            child: const Text('설정 열기'),
          ),
        ];
      case _Phase.installing:
        body = const Text('설치 화면에서 "업데이트"를 누르면 끝나요. 기록은 그대로 남아요.', style: TextStyle(height: 1.5));
        actions = [
          TextButton(onPressed: _install, child: const Text('설치 화면 다시 열기')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ];
      case _Phase.failed:
        body = Text(_error, style: const TextStyle(color: AppColors.wrong, fontWeight: FontWeight.w700));
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('나중에')),
          FilledButton(onPressed: _download, child: const Text('다시 시도')),
        ];
    }
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.system_update_rounded, color: AppColors.accent),
        const SizedBox(width: 10),
        Text('새 버전 #${u.build}'),
      ]),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (u.notes.isNotEmpty) ...[
            Text(u.notes, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft)),
            const SizedBox(height: 16),
          ],
          body,
        ]),
      ),
      actions: actions,
    );
  }
}

/// 설정: 앱 버전 · 업데이트 확인.
class UpdateTile extends StatefulWidget {
  const UpdateTile({super.key});

  @override
  State<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<UpdateTile> {
  int _build = 0;
  bool _checking = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    Updater.installedBuild().then((b) {
      if (mounted) setState(() => _build = b);
    });
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _msg = '';
    });
    final u = await Updater.check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _msg = u == null ? '최신 버전이에요' : '';
    });
    if (u != null) await showUpdateDialog(context, u);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('update-tile'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.system_update_rounded),
      title: Text('앱 버전 ${_build > 0 ? '#$_build' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(_msg.isNotEmpty ? _msg : '새 버전이 나오면 앱을 열 때 자동으로 받아서 설치 화면을 띄워요'),
      trailing: !Updater.supported
          ? null
          : _checking
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : TextButton(onPressed: _check, child: const Text('업데이트 확인')),
    );
  }
}
