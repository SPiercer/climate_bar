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
        body: Center(
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
      ),
    );
  }
}
