class CurrencyFormatter {
  const CurrencyFormatter._();

  static String pesos(num value) {
    return '\$${numero(value)}';
  }

  static String numero(num value) {
    final rounded = value.round();
    final sign = rounded < 0 ? '-' : '';
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();

    for (var index = 0; index < digits.length; index++) {
      final remaining = digits.length - index;
      buffer.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write('.');
      }
    }

    return '$sign${buffer.toString()}';
  }

  static double parse(String value) {
    final cleaned = value
        .replaceAll('\$', '')
        .replaceAll('COP', '')
        .replaceAll('cop', '')
        .replaceAll('.', '')
        .replaceAll(',', '')
        .trim();

    return double.tryParse(cleaned) ?? 0;
  }
}
