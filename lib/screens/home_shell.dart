import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../services/live_sync.dart';
import 'dashboard_screen.dart';
import 'editor_screen.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'scratch_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'wrong_note_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class _Dest {
  final IconData icon, activeIcon;
  final String label;
  const _Dest(this.icon, this.activeIcon, this.label);
}

class HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _dests = [
    _Dest(Icons.home_outlined, Icons.home_rounded, '홈'),
    _Dest(Icons.menu_book_outlined, Icons.menu_book_rounded, '문제집'),
    _Dest(Icons.assignment_late_outlined, Icons.assignment_late_rounded, '오답노트'),
    _Dest(Icons.insights_outlined, Icons.insights_rounded, '통계'),
    _Dest(Icons.history_rounded, Icons.history_rounded, '기록'),
    _Dest(Icons.draw_outlined, Icons.draw_rounded, '연습장'),
    _Dest(Icons.edit_note_outlined, Icons.edit_note_rounded, '내 문제'),
    _Dest(Icons.settings_outlined, Icons.settings_rounded, '설정'),
  ];

  void go(int tab) => setState(() => _tab = tab);

  Widget _page(int i) {
    switch (i) {
      case 0:
        return DashboardScreen(onNavigate: go);
      case 1:
        return const LibraryScreen();
      case 2:
        return const WrongNoteScreen();
      case 3:
        return const StatsScreen();
      case 4:
        return const HistoryScreen();
      case 5:
        return const ScratchScreen();
      case 6:
        return const EditorScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final due = app.dueCount;
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(key: ValueKey(_tab), child: _page(_tab)),
    );
    if (!wide) {
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab > 4 ? 0 : _tab,
          onDestinationSelected: go,
          destinations: [
            for (final d in _dests.take(5))
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.activeIcon), label: d.label),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(children: [
        _Rail(
          index: _tab,
          dests: _dests,
          onTap: go,
          due: due,
          profileName: app.profile.name,
          profileColor: Color(app.profile.color),
          live: app.live,
          liveEnabled: app.settings.liveEnabled,
        ),
        Expanded(child: SafeArea(left: false, child: body)),
      ]),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.dests,
    required this.onTap,
    required this.due,
    required this.profileName,
    required this.profileColor,
    required this.live,
    required this.liveEnabled,
  });
  final int index;
  final List<_Dest> dests;
  final ValueChanged<int> onTap;
  final int due;
  final String profileName;
  final Color profileColor;
  final LiveSync? live;
  final bool liveEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      color: AppColors.rail,
      child: SafeArea(
        right: false,
        child: Column(children: [
          const SizedBox(height: 18),
          // logo mark
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.draw_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          const Text('풀이노트',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: -0.3)),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                for (var i = 0; i < dests.length; i++)
                  _RailItem(
                    dest: dests[i],
                    selected: index == i,
                    badge: i == 2 && due > 0 ? '$due' : null,
                    onTap: () => onTap(i),
                  ),
              ]),
            ),
          ),
          if (live != null && liveEnabled)
            ValueListenableBuilder<LiveStatus>(
              valueListenable: live!.status,
              builder: (context, s, _) => Tooltip(
                message: s == LiveStatus.online ? '선생님과 실시간 공유 중' : '공유 서버에 연결되지 않음',
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Icon(Icons.podcasts_rounded,
                      color: s == LiveStatus.online ? const Color(0xFF5BE0A8) : Colors.white38, size: 22),
                ),
              ),
            ),
          GestureDetector(
            onTap: () => onTap(7),
            child: Tooltip(
              message: profileName,
              child: CircleAvatar(
                radius: 21,
                backgroundColor: profileColor,
                child: Text(profileName.isEmpty ? '?' : String.fromCharCode(profileName.runes.first),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ]),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.dest, required this.selected, required this.onTap, this.badge});
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 80,
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56,
                height: 34,
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(selected ? dest.activeIcon : dest.icon,
                    color: selected ? Colors.white : Colors.white60, size: 23),
              ),
              if (badge != null)
                Positioned(
                  right: 4,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                    child: Text(badge!,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(dest.label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                )),
          ]),
        ),
      ),
    );
  }
}
