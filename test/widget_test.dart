import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangashelf/main.dart';

void main() {
  testWidgets(
    'MangaShelf builda sem erros e exibe o indicador de carregamento inicial',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MangaShelfApp(),
      );

      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
      );
    },
  );
}
