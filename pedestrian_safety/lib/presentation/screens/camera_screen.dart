import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_colors.dart';
import '../../data/datasources/mock_datasource.dart';
import '../providers/safety_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/camera_provider.dart';
import '../widgets/safety_banner.dart';
import '../widgets/metrics_panel.dart';
import '../widgets/risk_gauge.dart';
import '../widgets/ttc_progress_bar.dart';
import '../widgets/zone_overlay.dart';
import '../widgets/vehicle_badge.dart';
import 'report_screen.dart';
import '../../data/models/state_output.dart';
import '../../domain/entities/safety_state.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  Timer? _simulationTimer;
  bool _isSimulating = true;

  late SafetyProvider _safetyProvider;
  late AudioProvider _audioProvider;
  late CameraProvider _cameraProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _safetyProvider = Provider.of<SafetyProvider>(context, listen: false);
    _audioProvider = Provider.of<AudioProvider>(context, listen: false);
    _cameraProvider = Provider.of<CameraProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCameraAndPipeline();
    });
  }

  Future<void> _initCameraAndPipeline() async {
    final cameraProvider = Provider.of<CameraProvider>(context, listen: false);
    final safetyProvider = Provider.of<SafetyProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);

    await safetyProvider.reset();
    await cameraProvider.initialize();

    if (cameraProvider.isInitialized) {
      setState(() {
        _isSimulating = false;
      });
      cameraProvider.startStreaming(
          safetyProvider, settingsProvider, audioProvider);
    } else {
      // Start simulation timer if hardware camera is not available (e.g., in emulator)
      _startSimulationLoop();
    }
  }

  void _startSimulationLoop() {
    _simulationTimer?.cancel();
    final safetyProvider = Provider.of<SafetyProvider>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final audioProvider = Provider.of<AudioProvider>(context, listen: false);

    _simulationTimer =
        Timer.periodic(const Duration(milliseconds: 33), (timer) {
      safetyProvider.processFrame(null, settingsProvider.config, audioProvider);
    });
  }

  void _stopSimulationLoop() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  @override
  void dispose() {
    _stopSimulationLoop();

    // Flag the pipeline as stopped FIRST so any in-flight inference discards
    // its callbacks (TTS / haptics / notifyListeners) before they fire
    _safetyProvider.stop(_audioProvider); // non-blocking fire-and-forget
    _cameraProvider.disposeCamera();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safetyProvider = Provider.of<SafetyProvider>(context);
    final cameraProvider = Provider.of<CameraProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final audioProvider = Provider.of<AudioProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background: Camera Preview or Mock Grid ──
          Positioned.fill(
            child: (!cameraProvider.isInitialized || _isSimulating)
                ? Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F0F26),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_off_rounded,
                            color: AppColors.textMuted.withValues(alpha: 0.4),
                            size: 64.0,
                          ),
                          const SizedBox(height: 12.0),
                          Text(
                            'Simulation Mode Active',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            'Rendering virtual traffic scenario...',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  )
                : CameraPreview(cameraProvider.controller!),
          ),

          // ── Spatial Overlays (Zones and Vehicles) ──
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double w = constraints.maxWidth;
                final double h = constraints.maxHeight;
                return Stack(
                  children: [
                    ZoneOverlay(width: w, height: h),
                    VehicleOverlay(
                      vehicles: safetyProvider.activeVehicles,
                      topKThreats: safetyProvider.topKThreats,
                      width: w,
                      height: h,
                      originalWidth: MediaQuery.of(context).orientation ==
                              Orientation.portrait
                          ? 480.0
                          : 640.0,
                      originalHeight: MediaQuery.of(context).orientation ==
                              Orientation.portrait
                          ? 640.0
                          : 480.0,
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Top Bar Control Panel ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8.0,
            left: 16.0,
            right: MediaQuery.of(context).orientation == Orientation.landscape
                ? MediaQuery.of(context).size.width * 0.5
                : 16.0,
            child: OrientationBuilder(
              builder: (context, orientation) {
                if (orientation == Orientation.landscape) {
                  return Row(
                    children: [
                      // Back button
                      _buildIconButton(
                        context,
                        Icons.arrow_back_ios_new_rounded,
                        'Back',
                        onPressed: () async {
                          _stopSimulationLoop();
                          try {
                            await cameraProvider.stopStreaming();
                          } catch (e) {
                            debugPrint('Error stopping streaming: $e');
                          }
                          try {
                            await safetyProvider.stop(audioProvider);
                          } catch (e) {
                            debugPrint('Error stopping safety provider: $e');
                          }
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 12.0),

                      // Compact Safety State Pill/Banner
                      Expanded(
                        child: CompactSafetyBanner(
                          stateOutput: safetyProvider.latestState,
                        ),
                      ),
                      const SizedBox(width: 12.0),

                      // Scenario drop-down selector
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<MockScenario>(
                            value: safetyProvider.currentScenario,
                            dropdownColor: AppColors.surface,
                            icon: const Icon(Icons.arrow_drop_down,
                                color: AppColors.textPrimary),
                            selectedItemBuilder: (BuildContext context) {
                              return MockScenario.values
                                  .map<Widget>((MockScenario sc) {
                                String shortName = sc.displayName;
                                 if (sc == MockScenario.clearRoad) {
                                   shortName = 'Clear';
                                 }
                                 if (sc == MockScenario.approachingCar) {
                                   shortName = 'Approaching';
                                 }
                                 if (sc == MockScenario.passingTraffic) {
                                   shortName = 'Passing';
                                 }
                                 if (sc == MockScenario.retreatingVehicle) {
                                   shortName = 'Retreating';
                                 }
                                return Center(
                                  child: Text(
                                    shortName,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              }).toList();
                            },
                            items: MockScenario.values.map((sc) {
                              return DropdownMenuItem<MockScenario>(
                                value: sc,
                                child: Text(
                                  sc.displayName,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (newScenario) {
                              if (newScenario != null) {
                                safetyProvider.changeScenario(newScenario);
                                if (_isSimulating) {
                                  _startSimulationLoop();
                                }
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12.0),

                      // Mute / Unmute
                      _buildIconButton(
                        context,
                        audioProvider.isMuted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        audioProvider.isMuted ? 'Unmute' : 'Mute',
                        color: audioProvider.isMuted
                            ? AppColors.stop
                            : AppColors.safe,
                        onPressed: () {
                          audioProvider.setMuted(!audioProvider.isMuted);
                        },
                      ),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Back button
                          _buildIconButton(
                            context,
                            Icons.arrow_back_ios_new_rounded,
                            'Back',
                            onPressed: () async {
                              _stopSimulationLoop();
                              try {
                                await cameraProvider.stopStreaming();
                              } catch (e) {
                                debugPrint('Error stopping streaming: $e');
                              }
                              try {
                                await safetyProvider.stop(audioProvider);
                              } catch (e) {
                                debugPrint(
                                    'Error stopping safety provider: $e');
                              }
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),

                          // Scenario drop-down selector
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(12.0),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<MockScenario>(
                                value: safetyProvider.currentScenario,
                                dropdownColor: AppColors.surface,
                                icon: const Icon(Icons.arrow_drop_down,
                                    color: AppColors.textPrimary),
                                items: MockScenario.values.map((sc) {
                                  return DropdownMenuItem<MockScenario>(
                                    value: sc,
                                    child: Text(
                                      sc.displayName,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newScenario) {
                                  if (newScenario != null) {
                                    safetyProvider.changeScenario(newScenario);
                                    if (_isSimulating) {
                                      _startSimulationLoop();
                                    }
                                  }
                                },
                              ),
                            ),
                          ),

                          // Mute / Unmute
                          _buildIconButton(
                            context,
                            audioProvider.isMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            audioProvider.isMuted ? 'Unmute' : 'Mute',
                            color: audioProvider.isMuted
                                ? AppColors.stop
                                : AppColors.safe,
                            onPressed: () {
                              audioProvider.setMuted(!audioProvider.isMuted);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12.0),

                      // Primary state banner
                      SafetyBanner(stateOutput: safetyProvider.latestState),
                    ],
                  );
                }
              },
            ),
          ),

          // ── Bottom Panel: Risk gauge, TTC & metrics ──
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16.0,
            left: 16.0,
            right: MediaQuery.of(context).orientation == Orientation.landscape
                ? MediaQuery.of(context).size.width * 0.5
                : 16.0,
            child: OrientationBuilder(
              builder: (context, orientation) {
                if (orientation == Orientation.landscape) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(
                      children: [
                        // Compact Risk display
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RISK: ${((safetyProvider.latestState?.riskScore ?? 0.0) * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.0,
                              ),
                            ),
                            Text(
                              'Conf: ${((safetyProvider.latestState?.confidence ?? 1.0) * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20.0),

                        // TTC Progress Bar taking remaining space
                        Expanded(
                          child: TtcProgressBar(
                            ttcSec: safetyProvider.topKThreats.isNotEmpty
                                ? safetyProvider.topKThreats.first.ttcSec
                                : double.infinity,
                            safeTtcLimit: settingsProvider.safeTtcLimitSec,
                          ),
                        ),
                        const SizedBox(width: 20.0),

                        // Small metrics summary
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FPS: ${safetyProvider.fps.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.0,
                              ),
                            ),
                            Text(
                              'Tier: ${safetyProvider.tier == 1 ? "Full" : safetyProvider.tier == 2 ? "Balanced" : "Fast"}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20.0),

                        // Compact End button
                        ElevatedButton.icon(
                          onPressed: () async {
                            _stopSimulationLoop();
                            try {
                              await cameraProvider.stopStreaming();
                            } catch (e) {
                              debugPrint('Error stopping streaming: $e');
                            }
                            try {
                              await safetyProvider.stop(audioProvider);
                            } catch (e) {
                              debugPrint('Error stopping safety provider: $e');
                            }

                            final report =
                                await safetyProvider.getSessionReport();
                            if (!context.mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReportScreen(report: report),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.stop,
                            foregroundColor: AppColors.textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12.0, vertical: 8.0),
                          ),
                          icon:
                              const Icon(Icons.stop_circle_rounded, size: 16.0),
                          label: const Text(
                            'END',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Horizontal layout for risk score circular gauge and TTC linear progress indicator
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Row(
                          children: [
                            RiskGauge(
                              riskScore:
                                  safetyProvider.latestState?.riskScore ?? 0.0,
                              confidence:
                                  safetyProvider.latestState?.confidence ?? 1.0,
                            ),
                            const SizedBox(width: 20.0),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TtcProgressBar(
                                    ttcSec:
                                        safetyProvider.topKThreats.isNotEmpty
                                            ? safetyProvider
                                                .topKThreats.first.ttcSec
                                            : double.infinity,
                                    safeTtcLimit:
                                        settingsProvider.safeTtcLimitSec,
                                  ),
                                  const SizedBox(height: 12.0),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      // Stop everything FIRST before navigating
                                      _stopSimulationLoop();
                                      try {
                                        await cameraProvider.stopStreaming();
                                      } catch (e) {
                                        debugPrint(
                                            'Error stopping streaming: $e');
                                      }
                                      try {
                                        await safetyProvider
                                            .stop(audioProvider);
                                      } catch (e) {
                                        debugPrint(
                                            'Error stopping safety provider: $e');
                                      }

                                      final report = await safetyProvider
                                          .getSessionReport();
                                      if (!context.mounted) return;
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ReportScreen(report: report),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.stop,
                                      foregroundColor: AppColors.textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12.0),
                                    ),
                                    icon: const Icon(Icons.stop_circle_rounded),
                                    label: const Text(
                                      'END SESSION',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12.0),

                      // Metrics row
                      MetricsPanel(
                        fps: safetyProvider.fps,
                        tier: safetyProvider.tier,
                        falseSafeCount: safetyProvider.latestState != null
                            ? safetyProvider.latestState!.riskScore == 0.0
                                ? 0
                                : safetyProvider.topKThreats.any((v) =>
                                        v.approaching &&
                                        v.ttcSec <
                                            settingsProvider.safeTtcLimitSec)
                                    ? 1
                                    : 0
                            : 0, // dynamic count
                        stateSwitches: 1, // static representation
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(
    BuildContext context,
    IconData icon,
    String semanticsLabel, {
    Color color = AppColors.textPrimary,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12.0),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12.0),
          child: Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20.0,
            ),
          ),
        ),
      ),
    );
  }
}

class CompactSafetyBanner extends StatelessWidget {
  final StateOutput? stateOutput;

  const CompactSafetyBanner({super.key, this.stateOutput});

  @override
  Widget build(BuildContext context) {
    final state = stateOutput?.internalState ?? SafetyState.safe;
    final cardColor = AppColors.stateBgColor(state.nameString);
    final contentColor = AppColors.stateColor(state.nameString);
    String bannerTitle = '';
    IconData iconData = Icons.security;

    switch (state) {
      case SafetyState.safe:
        bannerTitle = 'SAFE';
        iconData = Icons.directions_walk;
        break;
      case SafetyState.walkFast:
        bannerTitle = 'FAST';
        iconData = Icons.run_circle_outlined;
        break;
      case SafetyState.wait:
        bannerTitle = 'WAIT';
        iconData = Icons.hourglass_empty;
        break;
      case SafetyState.uncertain:
        bannerTitle = 'UNCERTAIN';
        iconData = Icons.help_outline;
        break;
      case SafetyState.stop:
        bannerTitle = 'STOP';
        iconData = Icons.warning_amber_rounded;
        break;
    }

    final reason = stateOutput?.spokenText ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: contentColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, color: contentColor, size: 20.0),
          const SizedBox(width: 8.0),
          Text(
            bannerTitle,
            style: TextStyle(
              color: contentColor,
              fontWeight: FontWeight.bold,
              fontSize: 12.0,
              letterSpacing: 1.0,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(width: 8.0),
            Container(
              width: 1.0,
              height: 12.0,
              color: contentColor.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                reason,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
