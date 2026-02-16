import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class GlitchLogo extends StatefulWidget {
  const GlitchLogo({super.key, required this.text, this.fontSize = 64});

  final String text;
  final double fontSize;

  @override
  State<GlitchLogo> createState() => _GlitchLogoState();
}

class _GlitchLogoState extends State<GlitchLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.displayMedium?.copyWith(
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final flicker = (_controller.value * 60).round() % 7 == 0;
        final shift = flicker ? (_random.nextDouble() * 8) - 4 : 0.0;

        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Transform.translate(
              offset: Offset(-2 + shift, 0),
              child: Text(
                widget.text,
                style: style?.copyWith(
                  color: context.glitchPalette.accent.withValues(alpha: 0.75),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(2 - shift, 0),
              child: Text(
                widget.text,
                style: style?.copyWith(
                  color: context.glitchPalette.accentSecondary.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: flicker ? 0.85 : 1,
              child: Text(widget.text, style: style),
            ),
          ],
        );
      },
    );
  }
}
