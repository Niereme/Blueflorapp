import 'dart:convert';

import 'package:blueflora/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Solo memoria: no accede a las preferencias del celular.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Abre Inicio y permite navegar entre las cuatro pestañas', (
    tester,
  ) async {
    // Se prueba el widget raíz; main() inicializa servicios nativos aparte.
    await tester.pumpWidget(const Blueflora());
    await tester.pumpAndSettle();

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .items
          .map((item) => item.label),
      ['Inicio', 'Árboles', 'Historial', 'Perfil'],
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Inicio')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.forest));
    await tester.pumpAndSettle();
    expect(find.text('Mis árboles'), findsOneWidget);
    expect(find.text('Árbol de prueba'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Historial'),
      ),
      findsOneWidget,
    );
    expect(find.text('Mis árboles'), findsNothing);

    await tester.tap(find.byIcon(Icons.account_circle));
    await tester.pumpAndSettle();
    expect(find.text('Perfil'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Historial'),
      ),
      findsNothing,
    );
  });

  testWidgets('Muestra los árboles guardados en el formato local actual', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'trees': [
        jsonEncode({
          'nombre': 'Jacaranda de prueba',
          'especie': 'Jacaranda mimosifolia',
          'altura': 2.5,
          'frecuenciaRiego': '3 días',
          'ultimoRiego': null,
        }),
      ],
    });
    await tester.pumpWidget(const Blueflora());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.forest));
    await tester.pumpAndSettle();

    expect(find.text('Jacaranda de prueba'), findsOneWidget);
    expect(find.text('Árbol de prueba'), findsNothing);
    expect(find.text('Último riego desconocido'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Registrar riego'),
      findsOneWidget,
    );
  });
}
