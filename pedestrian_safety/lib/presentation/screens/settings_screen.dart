import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../providers/settings_provider.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          AppStrings.accessibilitySettings,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0),
        ),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Banner
              GlassCard(
                borderColor: AppColors.accent.withValues(alpha: 0.3),
                bgColor: AppColors.accent.withValues(alpha: 0.05),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.accent, size: 24.0),
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: Text(
                        'Configure crossing parameters matched to your walking pace to ensure accurate audio alerts.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),

              Text(
                AppStrings.pedestrianSettings,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16.0),

              // Walking Speed
              _buildSliderSetting(
                context,
                title: 'Walking Speed (m/s)',
                subtitle: 'Typical range: 0.5 - 1.5 m/s. Lower speed is safer.',
                value: settingsProvider.walkSpeedMps,
                min: 0.4,
                max: 2.0,
                divisions: 16,
                valueSuffix: ' m/s',
                onChanged: (val) {
                  settingsProvider.updateWalkSpeed(val);
                },
              ),
              const SizedBox(height: 16.0),

              // Road Width
              _buildSliderSetting(
                context,
                title: 'Road Width (meters)',
                subtitle: 'Indian roads are usually 7.0 - 9.0 meters wide.',
                value: settingsProvider.roadWidthM,
                min: 3.0,
                max: 15.0,
                divisions: 24,
                valueSuffix: ' m',
                onChanged: (val) {
                  settingsProvider.updateRoadWidth(val);
                },
              ),
              const SizedBox(height: 16.0),

              // Safety Margin
              _buildSliderSetting(
                context,
                title: 'Safety Margin (seconds)',
                subtitle: 'Buffer time added after you finish crossing. Standard is 2.5s.',
                value: settingsProvider.safetyMarginSec,
                min: 0.5,
                max: 5.0,
                divisions: 9,
                valueSuffix: ' s',
                onChanged: (val) {
                  settingsProvider.updateSafetyMargin(val);
                },
              ),
              const SizedBox(height: 24.0),

              // Derived Calculations Card
              GlassCard(
                borderColor: AppColors.glassBorder,
                bgColor: AppColors.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Calculated Requirements',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16.0),
                    _buildCalculationRow(
                      context,
                      label: AppStrings.crossingTime,
                      value: '${settingsProvider.crossingTimeSec.toStringAsFixed(1)} seconds',
                      desc: 'Time needed to cross the street.',
                    ),
                    const SizedBox(height: 12.0),
                    _buildCalculationRow(
                      context,
                      label: AppStrings.safeTtcLimit,
                      value: '${settingsProvider.safeTtcLimitSec.toStringAsFixed(1)} seconds',
                      desc: 'Minimum safe vehicle gap (TTC) to start crossing.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderSetting(
    BuildContext context, {
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueSuffix,
    required ValueChanged<double> onChanged,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                '${value.toStringAsFixed(1)}$valueSuffix',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                ),
          ),
          const SizedBox(height: 8.0),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.glassBorder,
              thumbColor: AppColors.textPrimary,
              overlayColor: AppColors.accent.withValues(alpha: 0.2),
              valueIndicatorColor: AppColors.accent,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculationRow(
    BuildContext context, {
    required String label,
    required String value,
    required String desc,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12.0,
              ),
            ),
            Text(
              desc,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.safe,
            fontWeight: FontWeight.w900,
            fontSize: 14.0,
          ),
        ),
      ],
    );
  }
}
