import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? BluefloraTheme.dark : BluefloraTheme.light;
    test('Contraste de texto y estados ${dark ? "oscuro" : "claro"}', () {
      final scheme = theme.colorScheme;
      final pairs = [
        (scheme.primary, scheme.onPrimary),
        (scheme.primaryContainer, scheme.onPrimaryContainer),
        (scheme.surface, scheme.onSurface),
        for (final status in FloraStatus.values)
          theme.extension<FloraStatusColors>()!.pair(status, scheme),
      ];
      for (final (background, foreground) in pairs) {
        expect(contrast(background, foreground), greaterThanOrEqualTo(4.5));
      }
    });
    testWidgets(
      'Componentes con texto al 200%, ancho 320 y movimiento reducido: $dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: ListView(
                  children: [
                    for (final status in FloraStatus.values)
                      FloraMessage(
                        title: 'Tu jardín',
                        message:
                            'Información del calendario de riego de tus plantas.',
                        status: status,
                      ),
                    const FloraLoading(),
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Guardar cambios'),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final widget in tester.widgetList<AnimatedContainer>(
          find.byType(AnimatedContainer),
        )) {
          expect(widget.duration, Duration.zero);
        }
        await tester.scrollUntilVisible(find.byType(FloraLoading), 250);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
        expect(
          theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
          greaterThanOrEqualTo(48),
        );
      },
    );
  }
}
