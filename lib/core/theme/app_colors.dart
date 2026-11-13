import 'dart:ui' show Color;

/// True-black OLED palette (semantic tokens of the design system).
abstract final class AppColors {
  // --- surfaces -------------------------------------------------------------
  /// Main scaffold & keypad container background.
  static const Color bgObsidian = Color(0xFF090B10);

  /// Persistent display card.
  static const Color cardSurface = Color(0xFF11151F);

  /// 1px outline of the display card.
  static const Color cardBorder = Color(0xFF1E2536);

  /// Pill track of the segmented tab bar.
  static const Color tabTrack = Color(0xFF151A26);

  /// Selected pill of the segmented tab bar.
  static const Color tabThumb = Color(0xFF1E293B);

  /// Raised panels inside the tabs (lists, fields).
  static const Color panel = Color(0xFF0F131C);
  static const Color panelBorder = Color(0xFF1A2130);

  // --- keys -----------------------------------------------------------------
  static const Color keyDigit = Color(0xFF181E2C);
  static const Color keyDigitText = Color(0xFFF8FAFC);

  static const Color keyFunc = Color(0xFF131824);
  static const Color keyFuncText = Color(0xFF94A3B8);

  static const Color keyOperator = Color(0xFF1E293B);
  static const Color keyOperatorText = Color(0xFF38BDF8);

  static const Color keyDanger = Color(0xFF2A161D);
  static const Color keyDangerText = Color(0xFFFB7185);

  static const Color keyEqualsStart = Color(0xFF0EA5E9);
  static const Color keyEqualsEnd = Color(0xFF2563EB);
  static const Color keyEqualsText = Color(0xFFFFFFFF);

  /// A toggle key (INV, HYP) while it is active.
  static const Color keyActive = Color(0xFF0C4A6E);
  static const Color keyActiveText = Color(0xFF7DD3FC);

  /// Hairline on the top edge of every key.
  static const Color keyEdge = Color(0x14FFFFFF);

  // --- text -----------------------------------------------------------------
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textFaint = Color(0xFF475569);

  // --- accents --------------------------------------------------------------
  static const Color accent = Color(0xFF38BDF8);
  static const Color accentSoft = Color(0x3338BDF8);
  static const Color accentFaint = Color(0x1A38BDF8);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color error = Color(0xFFFB7185);
  static const Color errorSoft = Color(0x33FB7185);

  // --- MathPrint ------------------------------------------------------------
  static const Color mathDigit = Color(0xFFF8FAFC);
  static const Color mathOperator = Color(0xFF38BDF8);
  static const Color mathFunction = Color(0xFFCBD5E1);
  static const Color mathConstant = Color(0xFFFBBF24);
  static const Color mathVariable = Color(0xFFC4B5FD);
  static const Color mathParen = Color(0xFF94A3B8);
  static const Color mathPlaceholder = Color(0xFF334155);
  static const Color caret = Color(0xFF38BDF8);

  static const Color scrim = Color(0xB3090B10);
  static const Color transparent = Color(0x00000000);
}
