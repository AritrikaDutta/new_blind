import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_state_indicator.dart';
import '../../domain/entities/safety_state.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Programmatic grid background — no image file required
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),
          SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Block
                const SizedBox(height: 24.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AnimatedStateIndicator(state: SafetyState.safe),
                    const SizedBox(width: 10.0),
                    Flexible(
                      child: Text(
                        '🚦 CROSSING ASSIST',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 20.0,
                              letterSpacing: 1.5,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                Text(
                  AppStrings.appSubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12.0,
                      ),
                ),
                const Spacer(),

                // Mode Cards
                Semantics(
                  button: true,
                  label: 'Start Live Camera safety assistant',
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CameraScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(20.0),
                    child: GlassCard(
                      padding: const EdgeInsets.all(24.0),
                      borderColor: AppColors.safe.withValues(alpha: 0.3),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: AppColors.safe.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: AppColors.safe,
                              size: 32.0,
                            ),
                          ),
                          const SizedBox(width: 20.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.liveCamera,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  AppStrings.liveCameraDesc,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: AppColors.textSecondary,
                            size: 16.0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20.0),

                Semantics(
                  button: true,
                  label: 'Accessibility Settings',
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(20.0),
                    child: GlassCard(
                      padding: const EdgeInsets.all(24.0),
                      borderColor: AppColors.accent.withValues(alpha: 0.3),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.accessibility_new_rounded,
                              color: AppColors.accent,
                              size: 32.0,
                            ),
                          ),
                          const SizedBox(width: 20.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.settings,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  AppStrings.settingsDesc,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: AppColors.textSecondary,
                            size: 16.0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Bottom Tagline
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 6.0),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Text(
                        AppStrings.appTagline,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10.0,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
              ],
            ),
          ),
        ),
        ],  // Stack children
      ),
    );
  }
}

/// Draws a subtle dot-grid pattern directly on the canvas.
/// Replaces the missing assets/images/bg_grid.png with zero disk I/O.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.background,
    );
    // Dot grid
    final dotPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const double spacing = 28.0;
    const double radius = 1.2;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
