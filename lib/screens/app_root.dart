import 'package:flutter/material.dart';

import '../app/app_state.dart';
import 'home_shell.dart';
import 'teacher_shell.dart';
import 'welcome_screen.dart';

/// Picks the first screen: 로그인 → 선생님 화면 / 학생 화면.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.needsWelcome) return const WelcomeScreen();
    if (app.isTeacher) return TeacherShell(key: ValueKey('t-${app.profile.id}'));
    return HomeShell(key: ValueKey('s-${app.profile.id}'));
  }
}
