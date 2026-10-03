import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_state.dart';
import 'app/storage.dart';
import 'app/theme.dart';
import 'core/problem_bank.dart';
import 'screens/home_shell.dart';
import 'services/handwriting.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: '풀이노트',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const HomeShell(),
      ),
    );
  }
}
