import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'presentation/providers/safety_provider.dart';
import 'presentation/providers/camera_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/audio_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsProvider = SettingsProvider();
  await settingsProvider.loadSettings();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(create: (_) => SafetyProvider()),
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => AudioProvider()),
      ],
      child: const PedestrianSafetyApp(),
    ),
  );
}
