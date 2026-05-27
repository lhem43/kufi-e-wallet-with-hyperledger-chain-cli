import 'package:flutter/material.dart';

class AppColors {
  static const Color vanilla50 = Color(0xFFFFF9F8);
  static const Color vanilla100 = Color(0xFFFDEDE9);
  static const Color vanilla200 = Color(0xFFF8D8D0);
  static const Color vanilla300 = Color(0xFFF1C0B3);
  static const Color vanilla400 = Color(0xFFE5A48F);
  static const Color vanilla500 = Color(0xFFD58569);
  static const Color vanilla600 = Color(0xFFB8664D);
  static const Color vanilla700 = Color(0xFF8F4C3A);
  static const Color vanilla800 = Color(0xFF643529);

  static const Color violet50 = Color(0xFFFDF3F6);
  static const Color violet100 = Color(0xFFF8E2E8);
  static const Color violet200 = Color(0xFFF0C5D2);
  static const Color violet300 = Color(0xFFE49AB0);
  static const Color violet400 = Color(0xFFD36C8D);
  static const Color violet500 = Color(0xFFBB446C);
  static const Color violet600 = Color(0xFF982F56);
  static const Color violet700 = Color(0xFF722241);
  static const Color violet800 = Color(0xFF4E172D);

  static const Color momoPink = Color(0xFFC2294F);
  static const Color paypalBlue = Color(0xFF394D7A);
  static const Color animeMint = Color(0xFF2C9C86);
  static const Color retroLine = Color(0xFFE9CDD3);

  static const Color ink900 = Color(0xFF2C161C);
  static const Color ink700 = Color(0xFF5A3A42);
  static const Color ink500 = Color(0xFF8D6B73);
  static const Color success = Color(0xFF1F8D63);
  static const Color danger = Color(0xFFB92B43);
  static const Color kufiBlue = Color(0xFF2D88FF);
  static const Color kufiMagenta = Color(0xFFD6336C);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFBFA), Color(0xFFFFF4F2), Color(0xFFFBE9E9)],
  );

  static const LinearGradient darkHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF141216), Color(0xFF1A161B), Color(0xFF16131A)],
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5C1931), Color(0xFF782445), Color(0xFF973058)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6D1128), Color(0xFF951E3B), Color(0xFFC43857)],
  );

  static const LinearGradient primaryCtaGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF8C1E37), Color(0xFFB12A47), Color(0xFFD34666)],
  );

  static const LinearGradient retroAnimeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFEAE6), Color(0xFFFADFE5), Color(0xFFF8ECEA)],
  );

  static const LinearGradient subtleCardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFF4F3)],
  );
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.violet600,
      brightness: Brightness.light,
      primary: AppColors.violet600,
      secondary: AppColors.paypalBlue,
      surface: Colors.white,
      error: AppColors.danger,
    );

    const textTheme = TextTheme(
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        fontFamily: 'BeVietnamPro',
        color: AppColors.ink900,
      ),
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        fontFamily: 'BeVietnamPro',
        color: AppColors.ink900,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'BeVietnamPro',
        color: AppColors.ink900,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: 'BeVietnamPro',
        color: AppColors.ink700,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'BeVietnamPro',
        color: AppColors.ink700,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFFFF6F4),
      textTheme: textTheme,
      fontFamily: 'BeVietnamPro',
      splashFactory: InkSparkle.splashFactory,
      dividerColor: AppColors.violet100.withValues(alpha: 0.82),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink900,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          fontFamily: 'BeVietnamPro',
          color: AppColors.ink900,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.95),
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: const Color(0x2A7F253B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.violet100.withValues(alpha: 0.72)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF351E25),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'BeVietnamPro',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.violet600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
          shadowColor: AppColors.violet300.withValues(alpha: 0.35),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            fontFamily: 'BeVietnamPro',
            letterSpacing: 0.2,
          ),
          minimumSize: const Size(0, 54),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.violet600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'BeVietnamPro',
          ),
          minimumSize: const Size(0, 50),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.violet200.withValues(alpha: 0.85)),
          foregroundColor: AppColors.violet700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: 'BeVietnamPro',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.95),
        hintStyle: const TextStyle(
          color: AppColors.ink500,
          fontWeight: FontWeight.w500,
          fontFamily: 'BeVietnamPro',
        ),
        labelStyle: const TextStyle(
          color: AppColors.ink700,
          fontWeight: FontWeight.w500,
          fontFamily: 'BeVietnamPro',
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.violet200.withValues(alpha: 0.92),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.violet200.withValues(alpha: 0.92),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.momoPink, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.98),
        indicatorColor: AppColors.violet100.withValues(alpha: 0.9),
        elevation: 2,
        shadowColor: const Color(0x26853A4E),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.momoPink);
          }
          return const IconThemeData(color: AppColors.ink500);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w700,
            fontFamily: 'BeVietnamPro',
            color: states.contains(WidgetState.selected)
                ? AppColors.momoPink
                : AppColors.ink500,
          );
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: AppColors.violet300),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.violet600;
          }
          return Colors.white;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.violet50,
        selectedColor: AppColors.violet100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: AppColors.violet100.withValues(alpha: 0.9)),
        labelStyle: const TextStyle(
          color: AppColors.ink900,
          fontWeight: FontWeight.w700,
          fontFamily: 'BeVietnamPro',
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.momoPink,
      ),
    );
  }

  // ────────────────────────────────────────────
  //  Dark theme — red velvet + dark background
  // ────────────────────────────────────────────
  static ThemeData get dark {
    const darkBg = Color(0xFF171216);
    const darkSurface = Color(0xFF241D24);
    const darkCard = Color(0xFF2A222A);
    const darkBorder = Color(0xFF45323E);
    const darkText = Color(0xFFF3EAF0);
    const darkSubtext = Color(0xFFD1BCC8);
    const darkAccent = AppColors.momoPink;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFC3334F),
          brightness: Brightness.dark,
          primary: darkAccent,
          secondary: const Color(0xFFE98AA1),
          surface: darkSurface,
          error: AppColors.danger,
        ).copyWith(
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: darkText,
          outline: darkBorder,
        );

    const textTheme = TextTheme(
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        fontFamily: 'BeVietnamPro',
        color: darkText,
      ),
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        fontFamily: 'BeVietnamPro',
        color: darkText,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'BeVietnamPro',
        color: darkText,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: 'BeVietnamPro',
        color: darkSubtext,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFamily: 'BeVietnamPro',
        color: darkSubtext,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBg,
      textTheme: textTheme,
      fontFamily: 'BeVietnamPro',
      splashFactory: InkSparkle.splashFactory,
      dividerColor: darkBorder,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: darkText,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          fontFamily: 'BeVietnamPro',
          color: darkText,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF3A2832),
        contentTextStyle: const TextStyle(
          color: darkText,
          fontWeight: FontWeight.w600,
          fontFamily: 'BeVietnamPro',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            fontFamily: 'BeVietnamPro',
            letterSpacing: 0.2,
          ),
          minimumSize: const Size.fromHeight(54),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'BeVietnamPro',
          ),
          minimumSize: const Size.fromHeight(50),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: darkBorder),
          foregroundColor: const Color(0xFFF2C5D2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: 'BeVietnamPro',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        hintStyle: const TextStyle(
          color: darkSubtext,
          fontWeight: FontWeight.w500,
          fontFamily: 'BeVietnamPro',
        ),
        labelStyle: const TextStyle(
          color: darkSubtext,
          fontWeight: FontWeight.w500,
          fontFamily: 'BeVietnamPro',
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkAccent, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkCard,
        indicatorColor: const Color(0xFF4B2E3A),
        elevation: 2,
        shadowColor: Colors.black38,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkAccent);
          }
          return const IconThemeData(color: darkSubtext);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w700,
            fontFamily: 'BeVietnamPro',
            color: states.contains(WidgetState.selected)
                ? darkAccent
                : darkSubtext,
          );
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: darkBorder),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return darkAccent;
          }
          return darkCard;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: darkAccent.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: darkBorder),
        labelStyle: const TextStyle(
          color: darkText,
          fontWeight: FontWeight.w700,
          fontFamily: 'BeVietnamPro',
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkAccent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return darkAccent;
          }
          return darkSubtext;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return darkAccent.withValues(alpha: 0.3);
          }
          return darkBorder;
        }),
      ),
    );
  }
}
