import 'package:flutter/material.dart';

/// Premium dark-mode color palette with safety-state-mapped colors.
class AppColors {
  AppColors._();

  // ── Base palette ──────────────────────────────────────────────────────
  static const Color background = Color(0xFF0D0D1A);
  static const Color surface = Color(0xFF161629);
  static const Color surfaceLight = Color(0xFF1E1E3A);
  static const Color surfaceOverlay = Color(0xFF252545);
  static const Color cardBg = Color(0xFF1A1A32);

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F0F8);
  static const Color textSecondary = Color(0xFFB0B0C8);
  static const Color textMuted = Color(0xFF707090);

  // ── Accent / brand ────────────────────────────────────────────────────
  static const Color accent = Color(0xFF6C63FF);
  static const Color accentLight = Color(0xFF8B83FF);
  static const Color accentDim = Color(0xFF3D3899);

  // ── Safety states ─────────────────────────────────────────────────────
  static const Color safe = Color(0xFF00E676);
  static const Color safeBg = Color(0xFF0A2E1A);
  static const Color walkFast = Color(0xFFFFD740);
  static const Color walkFastBg = Color(0xFF2E2A0A);
  static const Color wait = Color(0xFFFF9100);
  static const Color waitBg = Color(0xFF2E1D0A);
  static const Color stop = Color(0xFFFF1744);
  static const Color stopBg = Color(0xFF2E0A10);
  static const Color uncertain = Color(0xFFFF6D00);
  static const Color uncertainBg = Color(0xFF2E1A0A);

  // ── Tier colors ───────────────────────────────────────────────────────
  static const Color tier1 = Color(0xFF00E676);
  static const Color tier2 = Color(0xFFFFAB40);
  static const Color tier3 = Color(0xFFFF1744);

  // ── Detection classes (BGR → RGB) ─────────────────────────────────────
  static const Color bicycle = Color(0xFFFF8C00);
  static const Color bus = Color(0xFFDC143C);
  static const Color car = Color(0xFFFF6464);
  static const Color dog = Color(0xFF64C864);
  static const Color motorcycle = Color(0xFFC800C8);
  static const Color person = Color(0xFFC8E600);
  static const Color scooty = Color(0xFFFF50C8);
  static const Color toto = Color(0xFFFFC800);

  // ── Glassmorphism ─────────────────────────────────────────────────────
  static const Color glassBorder = Color(0x30FFFFFF);
  static const Color glassOverlay = Color(0x18FFFFFF);

  // ── Gradients ─────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF4FC3F7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF1744), Color(0xFFFF6D00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient safeGradient = LinearGradient(
    colors: [Color(0xFF00E676), Color(0xFF00BFA5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Map safety state string to color.
  static Color stateColor(String state) {
    switch (state) {
      case 'SAFE':
        return safe;
      case 'WALK_FAST':
        return walkFast;
      case 'WAIT':
        return wait;
      case 'UNCERTAIN':
        return uncertain;
      case 'STOP':
        return stop;
      default:
        return textMuted;
    }
  }

  /// Map safety state string to background color.
  static Color stateBgColor(String state) {
    switch (state) {
      case 'SAFE':
        return safeBg;
      case 'WALK_FAST':
        return walkFastBg;
      case 'WAIT':
        return waitBg;
      case 'UNCERTAIN':
        return uncertainBg;
      case 'STOP':
        return stopBg;
      default:
        return surface;
    }
  }

  /// Map class ID to color.
  static Color classColor(int classId) {
    switch (classId) {
      case 0:
        return bicycle;
      case 1:
        return bus;
      case 2:
        return car;
      case 3:
        return dog;
      case 4:
        return motorcycle;
      case 5:
        return person;
      case 6:
        return scooty;
      case 7:
        return toto;
      default:
        return textMuted;
    }
  }
}
