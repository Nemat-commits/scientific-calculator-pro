import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// The three weights that are bundled for each family
/// (`assets/google_fonts/`).
enum AppWeight {
  regular(FontWeight.w400),
  medium(FontWeight.w500),

  /// Bold for JetBrains Mono, SemiBold for Inter.
  strong(FontWeight.w700);

  const AppWeight(this.mono);

  /// Weight used for JetBrains Mono.
  final FontWeight mono;

  /// Weight used for Inter.
  FontWeight get ui => this == AppWeight.strong ? FontWeight.w600 : mono;
}

/// Typography of the design system: JetBrains Mono (tabular figures) for
/// everything numeric, Inter for labels.
abstract final class AppTypography {
  /// When `false` the styles reference the plain family names
  /// (`JetBrainsMono`, `Inter`) instead of going through `google_fonts`.
  /// Widget tests flip this and register the bundled files themselves.
  static bool useGoogleFonts = true;

  static const String monoFamily = 'JetBrainsMono';
  static const String uiFamily = 'Inter';

  static const List<FontFeature> _tabular = <FontFeature>[FontFeature.tabularFigures()];

  /// Call once before `runApp`: fonts come from the asset bundle only.
  static void configure() {
    GoogleFonts.config.allowRuntimeFetching = false;
  }

  /// Completes when every bundled font variant is ready for painting.
  static Future<void> preload() async {
    if (!useGoogleFonts) return;
    await GoogleFonts.pendingFonts(<TextStyle>[
      for (final w in AppWeight.values) ...<TextStyle>[
        GoogleFonts.jetBrainsMono(fontWeight: w.mono),
        GoogleFonts.inter(fontWeight: w.ui),
      ],
    ]);
  }

  /// JetBrains Mono with tabular figures.
  static TextStyle mono({
    required double size,
    AppWeight weight = AppWeight.regular,
    Color color = AppColors.textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: weight.mono,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: _tabular,
      decoration: TextDecoration.none,
    );
    return useGoogleFonts ? GoogleFonts.jetBrainsMono(textStyle: base) : base.copyWith(fontFamily: monoFamily);
  }

  /// Inter for interface labels.
  static TextStyle ui({
    required double size,
    AppWeight weight = AppWeight.regular,
    Color color = AppColors.textSecondary,
    double? height,
    double? letterSpacing,
  }) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: weight.ui,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: _tabular,
      decoration: TextDecoration.none,
    );
    return useGoogleFonts ? GoogleFonts.inter(textStyle: base) : base.copyWith(fontFamily: uiFamily);
  }
}
