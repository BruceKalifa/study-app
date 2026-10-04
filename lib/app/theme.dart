import 'package:flutter/material.dart';

/// 앱 이름 — 바꿀 때는 여기와 tools/patch_android.sh 의 android:label 을 함께 고친다.
const String kAppName = '풀이노트';

/// Design tokens — "paper & ink": warm paper surfaces, deep ink navy text,
/// one coral accent, subject colours for wayfinding.
class AppColors {
  static const paper = Color(0xFFF5F2EC);
  static const paperDeep = Color(0xFFECE7DE);
  static const surface = Color(0xFFFFFFFF);
  static const sheet = Color(0xFFFFFDF8);
  static const line = Color(0xFFE6E0D5);
  static const lineStrong = Color(0xFFD5CDBF);

  static const ink = Color(0xFF1B2A4A);
  static const inkSoft = Color(0xFF4A5672);
  static const inkMuted = Color(0xFF8A90A0);

  static const accent = Color(0xFFFF6B4A);
  static const accentSoft = Color(0xFFFFE6DE);
  static const blue = Color(0xFF2F6BFF);
  static const blueSoft = Color(0xFFE3ECFF);

  static const correct = Color(0xFF169C6B);
  static const correctSoft = Color(0xFFDDF5EA);
  static const wrong = Color(0xFFE5484D);
  static const wrongSoft = Color(0xFFFDE4E4);
  static const review = Color(0xFFE8A317);
  static const reviewSoft = Color(0xFFFFF2D6);

  static const rail = Color(0xFF1B2A4A);
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
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 52),
          side: const BorderSide(color: AppColors.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        labelStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600, color: AppColors.ink),
        secondaryLabelStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
