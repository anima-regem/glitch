import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../features/shell/app_shell.dart';
import '../../shared/widgets/glitch_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _goNext();
  }

  Future<void> _goNext() async {
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const GlitchLogo(text: 'glitch'),
            const SizedBox(height: 16),
            Text(
              'single-focus day tracking',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.glitchPalette.textMuted,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
