import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../services/live_sync.dart';
import 'dashboard_screen.dart';
import 'editor_screen.dart';
import 'history_screen.dart';
import 'community_screen.dart';
import 'library_screen.dart';
import 'onboarding_screen.dart';
import 'planner_screen.dart';
import 'questions_screen.dart';
import 'subscription_screen.dart';
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
    _Dest(Icons.collections_bookmark_outlined, Icons.collections_bookmark_rounded, '내 교재'),
    _Dest(Icons.assignment_late_outlined, Icons.assignment_late_rounded, '오답노트'),
    _Dest(Icons.event_note_outlined, Icons.event_note_rounded, '학습관리'),
    _Dest(Icons.contact_support_outlined, Icons.contact_support_rounded, '질문'),
    _Dest(Icons.forum_outlined, Icons.forum_rounded, '커뮤니티'),
    _Dest(Icons.insights_outlined, Icons.insights_rounded, '통계'),
    _Dest(Icons.history_rounded, Icons.history_rounded, '기록'),
    _Dest(Icons.draw_outlined, Icons.draw_rounded, '연습장'),
    _Dest(Icons.edit_note_outlined, Icons.edit_note_rounded, '내 문제'),
    _Dest(Icons.workspace_premium_outlined, Icons.workspace_premium_rounded, '구독'),
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
        return const PlannerScreen();
      case 4:
        return const QuestionsScreen();
      case 5:
        return const CommunityScreen();
      case 6:
        return const StatsScreen();
      case 7:
        return const HistoryScreen();
      case 8:
        return const ScratchScreen();
      case 9:
        return const EditorScreen();
      case 10:
        return const SubscriptionScreen();
      default:
        return const SettingsScreen();
    }
  }

  /// 폰 아래 막대에 두는 탭 (나머지는 더보기).
  static const _phoneTabs = [0, 1, 2, 4];

  static Widget _badged(Widget icon, int n) => n <= 0 ? icon : Badge(label: Text('$n'), child: icon);

  /// 더보기 — 아래 막대에 없는 화면들.
  Future<void> _showMore(BuildContext context) async {
    final rest = [for (var i = 0; i < _dests.length; i++) if (!_phoneTabs.contains(i)) i];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('더보기', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final i in rest)
                  ListTile(
                    key: Key('more-${_dests[i].label}'),
                    leading: Icon(_tab == i ? _dests[i].activeIcon : _dests[i].icon,
                        color: _tab == i ? AppColors.accent : AppColors.inkSoft),
                    title: Text(_dests[i].label,
                        style: TextStyle(fontWeight: FontWeight.w700, color: _tab == i ? AppColors.accent : AppColors.ink)),
                    onTap: () => Navigator.pop(ctx, i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) go(picked);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.needsOnboarding) return const OnboardingScreen();
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final due = app.dueCount;
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(key: ValueKey(_tab), child: _page(_tab)),
    );
    if (!wide) {
      // 폰: 아래 막대에 네 개만 두고 나머지는 "더보기" 에 (12개를 다 넣으면 글자가 안 보인다)
      final sel = _phoneTabs.indexOf(_tab);
      return Scaffold(
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          key: const Key('phone-nav'),
          selectedIndex: sel < 0 ? _phoneTabs.length : sel,
          onDestinationSelected: (i) => i < _phoneTabs.length ? go(_phoneTabs[i]) : _showMore(context),
          destinations: [
            for (final t in _phoneTabs)
              NavigationDestination(
                icon: _badged(Icon(_dests[t].icon), t == 2 ? due : (t == 4 ? app.unreadAnswers : 0)),
                selectedIcon: _badged(Icon(_dests[t].activeIcon), t == 2 ? due : (t == 4 ? app.unreadAnswers : 0)),
                label: _dests[t].label,
              ),
            const NavigationDestination(
                key: Key('phone-more'),
                icon: Icon(Icons.more_horiz_rounded),
                selectedIcon: Icon(Icons.more_horiz_rounded),
                label: '더보기'),
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
          answers: app.unreadAnswers,
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
    required this.answers,
    required this.profileName,
    required this.profileColor,
    required this.live,
    required this.liveEnabled,
  });
  final int index;
  final List<_Dest> dests;
  final ValueChanged<int> onTap;
  final int due;
  final int answers;
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
          const Text(kAppName,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: -0.3)),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                for (var i = 0; i < dests.length; i++)
                  _RailItem(
                    dest: dests[i],
                    selected: index == i,
                    badge: i == 2 && due > 0
                        ? '$due'
                        : (i == 4 && answers > 0 ? '$answers' : null),
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
            onTap: () => onTap(11),
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
