import 'package:flutter_test/flutter_test.dart';

import 'package:app_cobradiario/main.dart';

void main() {
  testWidgets('muestra la pantalla de inicio de sesion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CobraDiarioApp());

    expect(find.text('Cobra Diario'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
  });
}
