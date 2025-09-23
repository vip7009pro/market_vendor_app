import 'package:flutter/material.dart';

class QuantityStepper extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final double step;

  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: () => onChanged((value - step).clamp(0, 999999)),
        ),
        Text(value.toStringAsFixed(value % 1 == 0 ? 0 : 2)),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(value + step),
        ),
      ],
    );
  }
}
