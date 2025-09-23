import 'package:flutter/material.dart';

class NumericKeypad extends StatelessWidget {
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;

  const NumericKeypad({super.key, required this.onKey, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    final keys = [
      '1','2','3',
      '4','5','6',
      '7','8','9',
      '.', '0', '<',
    ];
    return GridView.builder(
      shrinkWrap: true,
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.6),
      itemBuilder: (context, index) {
        final k = keys[index];
        if (k == '<') {
          return IconButton(
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined),
          );
        }
        return ElevatedButton(
          onPressed: () => onKey(k),
          child: Text(k, style: const TextStyle(fontSize: 20)),
        );
      },
    );
  }
}
