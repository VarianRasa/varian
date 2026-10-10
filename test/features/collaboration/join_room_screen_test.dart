import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/collaboration/presentation/join_room_screen.dart';

import '../../test_app.dart';

void main() {
  testWidgets('join form normalizes a Room ID and fits a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(null)],
        child: testApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: const JoinRoomScreen(initialRoomCode: '12-ab34567'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join workspace'), findsOneWidget);
    expect(find.text('SIGN IN TO JOIN'), findsOneWidget);
    final roomCodeField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(roomCodeField.controller?.text, '123456');
    expect(tester.takeException(), isNull);
  });
}
