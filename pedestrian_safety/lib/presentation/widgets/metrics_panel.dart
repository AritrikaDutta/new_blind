import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import './glass_card.dart';

class MetricsPanel extends StatelessWidget {
  final double fps;
  final int tier;
  final int falseSafeCount;
  final int stateSwitches;

  const MetricsPanel({
    super.key,
    required this.fps,
    required this.tier,
    required this.falseSafeCount,
    required this.stateSwitches,
  });

  @override
  Widget build(BuildContext context) {
    String tierLabel = 'Unknown';
    Color tierColor = AppColors.textMuted;
    switch (tier) {
      case 1:
        tierLabel = 'Full';
        tierColor = AppColors.tier1;
        break;
      case 2:
        tierLabel = 'Balanced';
        tierColor = AppColors.tier2;
        break;
      case 3:
        tierLabel = 'Fast';
        tierColor = AppColors.tier3;
        break;
    }

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricItem(
            context,
            'FPS',
            fps.toStringAsFixed(0),
            Icons.speed,
            AppColors.accent,
          ),
          _buildDivider(),
          _buildMetricItem(
            context,
            'Tier',
            tierLabel,
            Icons.layers,
            tierColor,
          ),
          _buildDivider(),
          _buildMetricItem(
            context,
            'False-Safe',
            falseSafeCount.toString(),
            Icons.error_outline,
            falseSafeCount > 0 ? AppColors.stop : AppColors.safe,
          ),
          _buildDivider(),
          _buildMetricItem(
            context,
            'Switches',
            stateSwitches.toString(),
            Icons.swap_horiz,
            AppColors.accentLight,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16.0),
            const SizedBox(width: 4.0),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10.0,
              ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 24.0,
      width: 1.0,
      color: AppColors.glassBorder,
    );
  }
}
