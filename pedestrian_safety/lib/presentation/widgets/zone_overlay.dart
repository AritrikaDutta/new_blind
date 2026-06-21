import 'package:flutter/material.dart';
import '../../domain/entities/zone.dart';

class ZoneOverlay extends StatelessWidget {
  final double width;
  final double height;

  const ZoneOverlay({
    super.key,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final zones = Zone.defineZones(width, height);

    return CustomPaint(
      size: Size(width, height),
      painter: ZonePainter(zones: zones),
    );
  }
}

class ZonePainter extends CustomPainter {
  final Map<String, Zone> zones;

  ZonePainter({required this.zones});

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, Color> colorMap = {
      'CROSSING': const Color(0x6000E676), // transparent green
      'LEFT': const Color(0x306C63FF),     // transparent blue/purple
      'RIGHT': const Color(0x306C63FF),    // transparent blue/purple
      'CENTER_DISTANT': const Color(0x20FFD740), // transparent yellow
    };

    final Map<String, Color> borderColors = {
      'CROSSING': const Color(0xFF00E676),
      'LEFT': const Color(0xFF6C63FF),
      'RIGHT': const Color(0xFF6C63FF),
      'CENTER_DISTANT': const Color(0xFFFFD740),
    };

    for (final entry in zones.entries) {
      final name = entry.key;
      final zone = entry.value;
      final fillPaint = Paint()
        ..color = colorMap[name] ?? Colors.transparent
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = borderColors[name] ?? Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw filled rect
      canvas.drawRect(zone.rect, fillPaint);
      // Draw border
      canvas.drawRect(zone.rect, borderPaint);

      // Draw label text
      final textSpan = TextSpan(
        text: name,
        style: TextStyle(
          color: borderColors[name] ?? Colors.white,
          fontSize: 10.0,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withValues(alpha: 0.6),
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(zone.rect.left + 6.0, zone.rect.top + 6.0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ZonePainter oldDelegate) {
    return false;
  }
}
