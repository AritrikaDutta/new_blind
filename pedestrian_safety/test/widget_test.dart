import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedestrian_safety/app.dart';
import 'package:provider/provider.dart';
import 'package:pedestrian_safety/presentation/providers/settings_provider.dart';
import 'package:pedestrian_safety/presentation/providers/safety_provider.dart';
import 'package:pedestrian_safety/presentation/providers/camera_provider.dart';
import 'package:pedestrian_safety/presentation/providers/audio_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      final WriteBuffer buffer = WriteBuffer();
      const StandardMessageCodec().writeValue(buffer, <Object?, Object?>{});
      return buffer.done();
    }
    if (key.endsWith('.png') || key.endsWith('.jpg') || key.endsWith('.jpeg')) {
      final List<int> pngBytes = [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        6,
        0,
        0,
        0,
        31,
        21,
        196,
        137,
        0,
        0,
        0,
        13,
        73,
        68,
        65,
        84,
        120,
        156,
        98,
        100,
        0,
        0,
        0,
        5,
        0,
        1,
        13,
        10,
        45,
        180,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130
      ];
      return ByteData.sublistView(Uint8List.fromList(pngBytes));
    }
    return ByteData(0);
  }
}

void main() {
  testWidgets('App renders home screen smoke test',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    await settingsProvider.loadSettings();

    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: MockAssetBundle(),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settingsProvider),
            ChangeNotifierProvider(create: (_) => SafetyProvider()),
            ChangeNotifierProvider(create: (_) => CameraProvider()),
            ChangeNotifierProvider(create: (_) => AudioProvider()),
          ],
          child: const PedestrianSafetyApp(),
        ),
      ),
    );

    expect(find.byType(PedestrianSafetyApp), findsOneWidget);
  });
}
