import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/state_output.dart';
import '../../domain/entities/safety_state.dart';

class SafetyBanner extends StatelessWidget {
  final StateOutput? stateOutput;

  const SafetyBanner({super.key, this.stateOutput});

  @override
  Widget build(BuildContext context) {
    final state = stateOutput?.internalState ?? SafetyState.safe;

    // Choose colors, icons and texts based on state
    Color cardColor = AppColors.stateBgColor(state.nameString);
    Color contentColor = AppColors.stateColor(state.nameString);
    String bannerTitle = '';
    String reason = stateOutput?.fullSpoken ?? 'Scanning environment...';
    IconData iconData = Icons.security;

    switch (state) {
      case SafetyState.safe:
        bannerTitle = 'SAFE TO CROSS';
        iconData = Icons.directions_walk;
        break;
      case SafetyState.walkFast:
        bannerTitle = 'WALK FAST';
        iconData = Icons.run_circle_outlined;
        break;
      case SafetyState.wait:
        bannerTitle = 'PLEASE WAIT';
        iconData = Icons.hourglass_empty;
        break;
      case SafetyState.uncertain:
        bannerTitle = 'UNCERTAIN';
        iconData = Icons.help_outline;
        break;
      case SafetyState.stop:
        bannerTitle = 'STOP!';
        iconData = Icons.warning_amber_rounded;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: contentColor.withValues(alpha: 0.5),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: contentColor.withValues(alpha: 0.2),
            blurRadius: 12.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: contentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconData,
              color: contentColor,
              size: 28.0,
            ),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bannerTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: contentColor,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  reason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
