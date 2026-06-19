import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/vehicle.dart';

class VehicleOverlay extends StatelessWidget {
  final List<Vehicle> vehicles;
  final List<Vehicle> topKThreats;
  final double width;
  final double height;
  final double originalWidth;
  final double originalHeight;

  const VehicleOverlay({
    super.key,
    required this.vehicles,
    required this.topKThreats,
    required this.width,
    required this.height,
    this.originalWidth = 640.0,
    this.originalHeight = 480.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: VehicleOverlayPainter(
        vehicles: vehicles,
        topKThreats: topKThreats,
        scaleX: width / originalWidth,
        scaleY: height / originalHeight,
      ),
    );
  }
}

class VehicleOverlayPainter extends CustomPainter {
  final List<Vehicle> vehicles;
  final List<Vehicle> topKThreats;
  final double scaleX;
  final double scaleY;

  VehicleOverlayPainter({
    required this.vehicles,
    required this.topKThreats,
    required this.scaleX,
    required this.scaleY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final topIds = topKThreats.map((v) => v.trackId).toSet();

    for (final v in vehicles) {
      final Color classColor = AppColors.classColor(v.classId);

      // Scale bounding box coordinates
      final Rect scaledBbox = Rect.fromLTRB(
        v.bbox.left * scaleX,
        v.bbox.top * scaleY,
        v.bbox.right * scaleX,
        v.bbox.bottom * scaleY,
      );

      // 1. Draw box background tint for persons/dogs (classId 5 and 3)
      if (v.classId == 5 || v.classId == 3) {
        final fillPaint = Paint()
          ..color = classColor.withOpacity(0.18)
          ..style = PaintingStyle.fill;
        canvas.drawRect(scaledBbox, fillPaint);
      }

      // 2. Draw outer border
      final borderPaint = Paint()
        ..color = classColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRect(scaledBbox, borderPaint);

      // 3. Highlight top-K threats with extra red outline
      if (topIds.contains(v.trackId)) {
        final threatPaint = Paint()
          ..color = AppColors.stop
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRect(scaledBbox.inflate(2.0), threatPaint);
      }

      // 4. Draw information pill badge
      // Construct status string: [1] Car - 12.3m, 40km/h (TTC 2.3s)
      String badgeText = '[${v.trackId}] ${v.classLabel}';
      if (v.distM > 0) {
        badgeText += ' • ${v.distM.toStringAsFixed(1)}m';
      }
      if (v.speedKmh > 0) {
        badgeText += ' • ${v.speedKmh.toStringAsFixed(0)}km/h';
      }
      if (v.ttcSec != double.infinity) {
        badgeText += ' • TTC ${v.ttcSec.toStringAsFixed(1)}s';
      }

      final textSpan = TextSpan(
        text: badgeText,
        style: TextStyle(
          color: classColor,
          fontSize: 9.0,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position text above the bounding box
      double textY = scaledBbox.top - textPainter.height - 4.0;
      if (textY < 0) {
        textY = scaledBbox.top + 4.0; // Draw inside if out of bounds
      }

      final bgRect = Rect.fromLTWH(
        scaledBbox.left,
        textY - 2.0,
        textPainter.width + 6.0,
        textPainter.height + 4.0,
      );

      final bgPaint = Paint()
        ..color = Colors.black.withOpacity(0.75)
        ..style = PaintingStyle.fill;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4.0)),
        bgPaint,
      );

      textPainter.paint(canvas, Offset(scaledBbox.left + 3.0, textY));
    }
  }

  @override
  bool shouldRepaint(covariant VehicleOverlayPainter oldDelegate) {
    return oldDelegate.vehicles != vehicles || oldDelegate.topKThreats != topKThreats;
  }
}
