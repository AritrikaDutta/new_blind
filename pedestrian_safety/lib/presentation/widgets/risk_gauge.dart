import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../core/constants/app_colors.dart';

class RiskGauge extends StatelessWidget {
  final double riskScore;
  final double confidence;

  const RiskGauge({
    super.key,
    required this.riskScore,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    Color gaugeColor = AppColors.safe;
    if (riskScore >= 0.70) {
      gaugeColor = AppColors.stop;
    } else if (riskScore >= 0.50) {
      gaugeColor = AppColors.wait;
    } else if (riskScore >= 0.25) {
      gaugeColor = AppColors.walkFast;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularPercentIndicator(
          radius: 54.0,
          lineWidth: 10.0,
          animation: true,
          animateFromLastPercent: true,
          percent: riskScore.clamp(0.0, 1.0),
          center: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${(riskScore * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                'RISK',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      fontSize: 8.0,
                    ),
              ),
            ],
          ),
          circularStrokeCap: CircularStrokeCap.round,
          progressColor: gaugeColor,
          backgroundColor: AppColors.glassBorder,
        ),
        const SizedBox(height: 8.0),
        Text(
          'Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11.0,
              ),
        ),
      ],
    );
  }
}
