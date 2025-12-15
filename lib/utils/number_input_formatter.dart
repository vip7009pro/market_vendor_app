import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class NumberInputFormatter extends TextInputFormatter {
  final int maxDecimalDigits;

  NumberInputFormatter({this.maxDecimalDigits = 0});

  static double? tryParse(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;

    // US convention in this app:
    // - ',' is grouping separator
    // - '.' is decimal separator
    // So we remove ',' and parse normally.
    final cleaned = t.replaceAll(',', '');
    return double.tryParse(cleaned);
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final newText = newValue.text;
    if (newText.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    final hasTrailingDecimalSeparator = maxDecimalDigits > 0 && newText.endsWith('.');

    final digitsBeforeCursor = _countDigits(newText.substring(0, newValue.selection.baseOffset.clamp(0, newText.length)));

    final normalized = _normalize(newText);
    if (normalized.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    final parts = normalized.split('.');
    final intPartRaw = parts[0].isEmpty ? '0' : parts[0];
    var decPartRaw = parts.length > 1 ? parts[1] : '';

    if (maxDecimalDigits <= 0) {
      decPartRaw = '';
    } else if (decPartRaw.length > maxDecimalDigits) {
      decPartRaw = decPartRaw.substring(0, maxDecimalDigits);
    }

    final intPart = int.tryParse(intPartRaw) ?? 0;
    final formatter = NumberFormat.decimalPattern('en_US');
    final formattedInt = formatter.format(intPart);

    var formatted = decPartRaw.isEmpty ? formattedInt : '$formattedInt.$decPartRaw';
    if (hasTrailingDecimalSeparator && !formatted.contains('.')) {
      formatted = '$formattedInt.';
    }

    final newCursor = hasTrailingDecimalSeparator
        ? formatted.length
        : _cursorFromDigits(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
      composing: TextRange.empty,
    );
  }

  String _normalize(String input) {
    final sb = StringBuffer();
    var hasDecimal = false;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      // US: ',' is thousand separator. Never treat it as decimal.
      if (ch == ',') continue;

      // Use '.' as decimal separator only when decimals are allowed.
      if (ch == '.') {
        if (maxDecimalDigits > 0 && !hasDecimal && sb.isNotEmpty) {
          sb.write('.');
          hasDecimal = true;
        }
        continue;
      }
      if (_isDigit(ch)) sb.write(ch);
    }
    return sb.toString();
  }

  static bool _isDigit(String ch) {
    if (ch.length != 1) return false;
    final c = ch.codeUnitAt(0);
    return c >= 48 && c <= 57;
  }

  static int _countDigits(String s) {
    var c = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (_isDigit(ch)) c++;
    }
    return c;
  }

  static int _cursorFromDigits(String formatted, int digitsBeforeCursor) {
    if (digitsBeforeCursor <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      final ch = formatted[i];
      if (_isDigit(ch)) {
        seen++;
        if (seen >= digitsBeforeCursor) {
          return i + 1;
        }
      }
    }
    return formatted.length;
  }
}
