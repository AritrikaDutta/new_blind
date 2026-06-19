import 'dart:ui';

class Zone {
  final String name;
  final Rect rect;

  const Zone({
    required this.name,
    required this.rect,
  });

  bool overlaps(Rect other) {
    return rect.overlaps(other);
  }

  static Map<String, Zone> defineZones(double width, double height) {
    const double leftW = 0.20;
    const double rightW = 0.20;
    const double crossingTop = 0.40;
    const double crossingBottom = 1.0;

    return {
      'CROSSING': Zone(
        name: 'CROSSING',
        rect: Rect.fromLTRB(
          width * leftW,
          height * crossingTop,
          width * (1.0 - rightW),
          height * crossingBottom,
        ),
      ),
      'LEFT': Zone(
        name: 'LEFT',
        rect: Rect.fromLTRB(
          0.0,
          0.0,
          width * leftW,
          height,
        ),
      ),
      'RIGHT': Zone(
        name: 'RIGHT',
        rect: Rect.fromLTRB(
          width * (1.0 - rightW),
          0.0,
          width,
          height,
        ),
      ),
      'CENTER_DISTANT': Zone(
        name: 'CENTER_DISTANT',
        rect: Rect.fromLTRB(
          width * leftW,
          0.0,
          width * (1.0 - rightW),
          height * crossingTop,
        ),
      ),
    };
  }
}
