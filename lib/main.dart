import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_state.dart';
import 'app/storage.dart';
import 'app/theme.dart';
import 'core/problem_bank.dart';
import 'screens/app_root.dart';
import 'services/content_import.dart';
import 'services/handwriting.dart';
import 'services/updater.dart';
import 'widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final bank = await ProblemBank.load(rootBundle);
  final storage = await FileStorage.create();
  final state = AppState(storage: storage, baseBank: bank);
  await state.init();
  // download the handwriting model in the background (first launch only)
  Handwriting.instance.prepare();
  runApp(PulinoteApp(state: state));
}

class PulinoteApp extends StatefulWidget {
  const PulinoteApp({super.key, required this.state});
  final AppState state;

  @override
  State<PulinoteApp> createState() => _PulinoteAppState();
}

class _PulinoteAppState extends State<PulinoteApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey<ScaffoldMessengerState>();
  DateTime? _lastUpdateCheck;
  bool _updateShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdate();
      _checkOpenedFile();
    });
  }

  /// 다른 앱(카카오톡, 내 파일…)에서 .pulinote 교재 파일을 이 앱으로 열었을 때.
  Future<void> _checkOpenedFile() async {
    if (!Updater.supported) return;
    final bytes = await BookFiles.takeOpened();
    if (bytes == null) return;
    String msg;
    try {
      final book = await widget.state.importBook(bytes);
      msg = '「${book.title}」 교재를 넣었어요 (${book.problemCount}문항)';
    } on FormatException catch (e) {
      msg = e.message;
    } catch (e) {
      msg = '교재 파일을 넣지 못했어요';
    }
    _messenger.currentState?.showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 앱을 열 때(그리고 30분 넘게 지난 뒤 다시 열 때) 새 버전이 있으면 받아서 설치 화면을 띄운다.
  Future<void> _checkUpdate() async {
    if (!Updater.enabled || !Updater.supported || _updateShown) return;
    final now = DateTime.now();
    final last = _lastUpdateCheck;
    if (last != null && now.difference(last) < const Duration(minutes: 30)) return;
    _lastUpdateCheck = now;
    final u = await Updater.check();
    final ctx = _nav.currentState?.overlay?.context;
    if (u == null || ctx == null || !ctx.mounted || _updateShown) return;
    _updateShown = true;
    await showUpdateDialog(ctx, u);
    _updateShown = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      widget.state.saveNow();
    } else if (s == AppLifecycleState.resumed) {
      widget.state.onResumed();
      _checkUpdate();
      _checkOpenedFile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: kAppName,
        navigatorKey: _nav,
        scaffoldMessengerKey: _messenger,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const AppRoot(),
      ),
    );
  }
}
