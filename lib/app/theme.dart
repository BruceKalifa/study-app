import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// 앱 이름 — 바꿀 때는 여기와 tools/patch_android.sh 의 android:label 을 함께 고친다.
const String kAppName = 'Solvit';

/// 앱이 쓰는 서버. 학생·선생님이 주소를 입력할 일이 없게 여기서 정한다
/// (바꾸려면: 서버를 옮길 때 이 줄만 고치고 다시 배포하면 된다).
/// 무한 풀기 (내 교재·과목·단원·약점 유형을 끝없이 풀기). 지금은 숨겨 둠 — 나중에 쓸 때 true 로 바꾸면 진입점이 다시 나온다.
/// 코드(SolveScreen.endless, AppState.nextEndless)는 그대로 있다.
const bool kEndlessEnabled = false;

const String kDefaultServer = 'https://pulinote-server.onrender.com';

/// Design tokens — "engineering pad" (공학용 계산지):
/// 서늘한 회녹색 종이, 흑연(graphite) 글자, 설계도 파랑 하나, 형광펜 노랑은 강조 한 곳에만.
/// (따뜻한 크림 종이 + 코랄 은 흔한 생성형 기본값이라 버렸다)
class AppColors {
  static const paper = Color(0xFFF1F3F0);
  static const paperDeep = Color(0xFFE6EAE5);
  static const surface = Color(0xFFFFFFFF);
  static const sheet = Color(0xFFFDFEFC);
  static const line = Color(0xFFDDE2DB);
  static const lineStrong = Color(0xFFC6CEC4);

  /// 모눈 (계산지 격자)
  static const grid = Color(0xFFE4EAE2);

  static const ink = Color(0xFF1C2126);
  static const inkSoft = Color(0xFF515A64);
  static const inkMuted = Color(0xFF858E98);

  /// 설계도 파랑 — 주요 동작·진행 (흰 글자가 올라간다)
  static const accent = Color(0xFF2B59C3);
  static const accentSoft = Color(0xFFE4EBFA);
  static const blue = Color(0xFF2B59C3);
  static const blueSoft = Color(0xFFE4EBFA);

  /// 형광펜 — 선택된 것·오늘 할 것 밑줄. 배경으로만 쓰고 위에는 흑연 글자.
  static const highlight = Color(0xFFFFE45C);
  static const highlightSoft = Color(0xFFFFF6BF);

  static const correct = Color(0xFF16956A);
  static const correctSoft = Color(0xFFDDF3E9);
  static const wrong = Color(0xFFE0443F);
  static const wrongSoft = Color(0xFFFCE3E2);
  static const review = Color(0xFFC77D0A);
  static const reviewSoft = Color(0xFFFCEFD6);

  static const rail = Color(0xFF1C2126);

  /// 숫자는 고정폭 (진도·시간이 바뀔 때 글자가 흔들리지 않게)
  static const tabular = [FontFeature.tabularFigures()];
}

class AppTheme {
  static const String font = 'Pretendard';

  /// Exam-paper body face (나눔명조, OFL).
  static const String serif = 'NanumMyeongjo';

  /// TeX 원문 교재의 본문 글꼴 (Noto Serif KR, OFL) — texStyle 문항.
  static const String texSerif = 'NotoSerifKR';

  /// 교재 머리표 색 (원문 definecolor{accent}{RGB}{217,119,87}, faintgray 150,148,140).
  static const Color texAccent = Color(0xFFD97757);
  static const Color texFaint = Color(0xFF96948C);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.ink,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.wrong,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: AppColors.paper,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    final t = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink, fontFamily: font);
    return base.copyWith(
      textTheme: t.copyWith(
        displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: t.bodyLarge?.copyWith(height: 1.55),
        bodyMedium: t.bodyMedium?.copyWith(height: 1.5, color: AppColors.ink),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamily: font, fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.5),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.inkSoft,
          selectedBackgroundColor: AppColors.ink,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: AppColors.line),
          textStyle: const TextStyle(fontFamily: font, fontSize: 14.5, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: AppColors.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: const TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600, color: AppColors.ink),
        secondaryLabelStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.6),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontFamily: font, color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.ink : AppColors.lineStrong),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: AppColors.ink,
        thumbColor: AppColors.ink,
        inactiveTrackColor: AppColors.line,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: font, color: AppColors.ink, fontWeight: FontWeight.w600),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontFamily: font, color: Colors.white, fontSize: 13),
      ),
    );
  }
}

/// Small helpers used across screens.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

Color subjectColor(int argb) => Color(argb);

/// Display label for a multiple-choice answer.
String circled(int n) => n <= 0 ? '-' : '$n번';

String fmtDuration(int ms) {
  final s = (ms / 1000).round();
  final m = s ~/ 60;
  final r = s % 60;
  if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
  if (m > 0) return '$m분 ${r.toString().padLeft(2, '0')}초';
  return '$r초';
}

String fmtClock(int ms) {
  final s = ms ~/ 1000;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

String fmtDate(int epochMs, {bool withTime = true}) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final date = '${d.month}월 ${d.day}일';
  if (!withTime) return date;
  final h = d.hour, m = d.minute.toString().padLeft(2, '0');
  final ap = h < 12 ? '오전' : '오후';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$date $ap $hh:$m';
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
