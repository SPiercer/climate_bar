import 'dart:math';

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool on = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(),
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        // Transparent so the native blur shows through.
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Glass only refracts what Flutter draws, so give it something to bend.
            Positioned.fill(child: _DriftingBlobs(on: on)),
            Center(
              child: TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 400),
                tween: ColorTween(
                  end: on
                      ? Colors.lightBlueAccent.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.12),
                ),
                builder: (context, tint, _) => LiquidGlassLayer(
                  settings: LiquidGlassSettings(
                    thickness: 24,
                    blur: 3,
                    glassColor: tint!,
                    lightIntensity: 0.7,
                    chromaticAberration: 0.5,
                  ),
                  child: LiquidStretch(
                    child: LiquidGlass(
                      shape: const LiquidOval(),
                      child: GlassGlow(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => on = !on),
                          child: SizedBox.square(
                            dimension: 120,
                            child: Icon(
                              Icons.power_settings_new,
                              size: 44,
                              color: on ? Colors.white : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft coloured circles orbiting behind the button; cooler and brighter when on.
class _DriftingBlobs extends StatefulWidget {
  const _DriftingBlobs({required this.on});

  final bool on;

  @override
  State<_DriftingBlobs> createState() => _DriftingBlobsState();
}

class _DriftingBlobsState extends State<_DriftingBlobs>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.on
        ? [Colors.cyan, Colors.blue, Colors.indigoAccent]
        : [Colors.blueGrey, Colors.grey, Colors.blueGrey.shade700];
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset.fromDirection(
                controller.value * 2 * pi + i * 2 * pi / 3,
                60,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[i].withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
