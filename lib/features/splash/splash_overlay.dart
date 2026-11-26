import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/app_theme.dart';

/// Launch screen: brand gradient with the app name, laid over [child] (the home screen, which
/// loads underneath) and faded out after [duration].
///
/// Continues the native launch screen: Android 12+ only shows a solid brand color
/// ([nativeColor], `@color/brand_blue_violet`), so the gradient and name fade in on top of it.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.child, this.duration = const Duration(milliseconds: 1200)});

  final Widget child;
  final Duration duration;

  /// Same as `android/app/src/main/res/values/colors.xml` `brand_blue_violet`.
  static const nativeColor = Color(0xFF4848F5);

  static const _fadeIn = Duration(milliseconds: 350);
  static const _fadeOut = Duration(milliseconds: 400);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  bool _shown = false; // gradient + name faded in
  bool _hiding = false; // fading out
  bool _gone = false; // removed from the tree
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
    _timer = Timer(widget.duration, () {
      if (mounted) setState(() => _hiding = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_gone)
          IgnorePointer(
            ignoring: _hiding,
            child: AnimatedOpacity(
              opacity: _hiding ? 0 : 1,
              duration: SplashOverlay._fadeOut,
              onEnd: () {
                if (_hiding && mounted) setState(() => _gone = true);
              },
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
                child: ColoredBox(
                  color: SplashOverlay.nativeColor,
                  child: AnimatedOpacity(
                    opacity: _shown ? 1 : 0,
                    duration: SplashOverlay._fadeIn,
                    curve: Curves.easeOut,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(gradient: AppTheme.brandGradient),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          // One line at any system font size.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Auditorium',
                              textDirection: TextDirection.ltr,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                decoration: TextDecoration.none,
                                shadows: [Shadow(color: Color(0x40140A50), blurRadius: 16, offset: Offset(0, 2))],
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
          ),
      ],
    );
  }
}
