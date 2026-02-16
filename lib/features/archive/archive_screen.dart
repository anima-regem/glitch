import 'package:flutter/material.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Archive is intentionally quiet in v1.\nOlder entries can live here later.',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
