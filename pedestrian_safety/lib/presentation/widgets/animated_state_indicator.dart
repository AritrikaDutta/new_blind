import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/safety_state.dart';

class AnimatedStateIndicator extends StatefulWidget {
  final SafetyState state;

  const AnimatedStateIndicator({
    super.key,
    required this.state,
  });

  @override
  State<AnimatedStateIndicator> createState() => _AnimatedStateIndicatorState();
}

class _AnimatedStateIndicatorState extends State<AnimatedStateIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color stateColor = AppColors.stateColor(widget.state.nameString);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 24.0 * _pulseAnimation.value,
              height: 24.0 * _pulseAnimation.value,
              decoration: BoxDecoration(
                color: stateColor.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 14.0,
              height: 14.0,
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: stateColor.withOpacity(0.6),
                    blurRadius: 8.0,
                    spreadRadius: 2.0,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
