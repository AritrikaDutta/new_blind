import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class TtcProgressBar extends StatelessWidget {
  final double ttcSec;
  final double safeTtcLimit;

  const TtcProgressBar({
    super.key,
    required this.ttcSec,
    required this.safeTtcLimit,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSafe = ttcSec == double.infinity || ttcSec >= safeTtcLimit;
    
    // Calculate progress ratio (0.0 = crash/imminent, 1.0 = safe/far)
    double progressRatio = 1.0;
    if (ttcSec != double.infinity && safeTtcLimit > 0) {
      progressRatio = (ttcSec / safeTtcLimit).clamp(0.0, 1.0);
    }

    Color barColor = AppColors.safe;
    if (progressRatio < 0.3) {
      barColor = AppColors.stop;
    } else if (progressRatio < 0.6) {
      barColor = AppColors.wait;
    } else if (progressRatio < 0.8) {
      barColor = AppColors.walkFast;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Time-to-Collision (TTC)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              isSafe ? 'No Threat' : '${ttcSec.toStringAsFixed(1)}s',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSafe ? AppColors.safe : barColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6.0),
        ClipRRect(
          borderRadius: BorderRadius.circular(4.0),
          child: LinearProgressIndicator(
            value: progressRatio,
            backgroundColor: AppColors.glassBorder,
            color: barColor,
            minHeight: 8.0,
          ),
        ),
        const SizedBox(height: 2.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Imminent',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 9.0,
                  ),
            ),
            Text(
              'Safe Limit (${safeTtcLimit.toStringAsFixed(1)}s)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 9.0,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
