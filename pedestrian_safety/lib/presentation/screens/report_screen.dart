
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/safety_report.dart';
import '../widgets/glass_card.dart';

class ReportScreen extends StatelessWidget {
  final SafetyReport report;

  const ReportScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final bool hasNoFalseSafe = report.falseSafeCount == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                AppStrings.sessionReport,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
              ),
              const SizedBox(height: 8.0),
              const Text(
                'Safety metrics and threat progression logs',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12.0),
              ),
              const SizedBox(height: 24.0),

              // KPI Row
              Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      context,
                      title: AppStrings.falseSafeEvents,
                      value: report.falseSafeCount.toString(),
                      icon: Icons.security_update_warning_rounded,
                      color: hasNoFalseSafe ? AppColors.safe : AppColors.stop,
                    ),
                  ),
                  const SizedBox(width: 16.0),
                  Expanded(
                    child: _buildKpiCard(
                      context,
                      title: AppStrings.falseSafeRate,
                      value:
                          '${(report.falseSafeRate * 100).toStringAsFixed(1)}%',
                      icon: Icons.percent,
                      color: hasNoFalseSafe ? AppColors.safe : AppColors.wait,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),

              _buildKpiCard(
                context,
                title: AppStrings.totalStateSwitches,
                value: report.stateSwitches.toString(),
                icon: Icons.swap_calls_rounded,
                color: AppColors.accent,
                isHorizontal: true,
              ),

              const SizedBox(height: 24.0),

              // Timeline graph card
              Expanded(
                child: GlassCard(
                  borderColor: AppColors.glassBorder,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Risk Score Progression Timeline',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4.0),
                      const Text(
                        'Tracks the threat levels during the crossing duration.',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 10.0),
                      ),
                      const SizedBox(height: 20.0),
                      Expanded(
                        child: report.riskHistory.isEmpty
                            ? const Center(
                                child: Text(
                                  'No risk history recorded.',
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                              )
                            : CustomPaint(
                                painter: RiskTimelinePainter(
                                  points: report.riskHistory,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24.0),

              // Return to Home button
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: const Text(
                  'RETURN TO MAIN MENU',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isHorizontal = false,
  }) {
    final content = [
      Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24.0),
      ),
      if (!isHorizontal)
        const SizedBox(height: 16.0)
      else
        const SizedBox(width: 20.0),
      Expanded(
        child: Column(
          crossAxisAlignment: isHorizontal
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(
              title,
              textAlign: isHorizontal ? TextAlign.left : TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
            ),
          ],
        ),
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(16.0),
      borderColor: color.withValues(alpha: 0.2),
      child: isHorizontal
          ? Row(
              children: content,
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: content,
            ),
    );
  }
}

class RiskTimelinePainter extends CustomPainter {
  final List<double> points;

  RiskTimelinePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Draw baseline grid
    final gridPaint = Paint()
      ..color = AppColors.glassBorder.withValues(alpha: 0.1)
      ..strokeWidth = 1.0;

    for (int i = 1; i < 4; i++) {
      final double y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final double stepX =
        size.width / (points.length > 1 ? points.length - 1 : 1);

    final path = Path();
    path.moveTo(0, size.height * (1.0 - points.first));

    for (int i = 1; i < points.length; i++) {
      final double x = i * stepX;
      final double y = size.height * (1.0 - points[i]);
      path.lineTo(x, y);
    }

    // Path stroke paint with color gradient based on threat height
    final linePaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.safe, AppColors.wait, AppColors.stop],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw filled area under path
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.safe.withValues(alpha: 0.1),
          AppColors.stop.withValues(alpha: 0.1),
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant RiskTimelinePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
