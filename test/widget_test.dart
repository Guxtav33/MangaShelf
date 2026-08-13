import 'package:flutter_test/flutter_test.dart';
import 'package:mangashelf/main.dart';

void main() {
  testWidgets(
    'MangaShelf inicia corretamente',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MangaShelfApp(),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('MangaShelf'),
        findsWidgets,
      );
    },
  );
}
