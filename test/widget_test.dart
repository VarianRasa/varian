import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/main.dart';

void main() {
  testWidgets('Creative Canvas Studio App boots successfully', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CreativeCanvasApp()));
    expect(find.byType(CreativeCanvasApp), findsOneWidget);
  });
}
