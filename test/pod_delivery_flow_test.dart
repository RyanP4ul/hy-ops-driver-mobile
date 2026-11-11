import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/features/trips/delivery_sheets.dart';
import 'package:hyops_flutter/state/app_state.dart';

import 'widget_test.dart' as fixtures;

class PodRepository extends fixtures.FakeRepository {
  PodRepository(super.client);
  Completer<List<Map<String, dynamic>>>? proofRead;
  bool failProofRead = false;
  @override
  Future<List<Map<String, dynamic>>> proofs(String stopId) async {
    if (failProofRead) throw StateError('Proofs unavailable');
    return proofRead == null ? savedProofs : await proofRead!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppState, PodRepository)> setup() async {
    SharedPreferences.setMockInitialValues({});
    final client = fixtures.FakeClient();
    final repo = PodRepository(client);
    final state = AppState(
      await SharedPreferences.getInstance(),
      api: client,
      driverRepository: repo,
      realtime: false,
    );
    addTearDown(state.dispose);
    await state.login('driver@example.test', 'valid-password', remember: false);
    return (state, repo);
  }

  Widget shell(AppState state) => AppScope(
    state: state,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeliverySheet(
              context,
              state.trips.single,
              state.trips.single.stops.single,
            ),
            child: const Text('Record delivery'),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'POD is required before confirmation, including after dismissing it',
    (tester) async {
      final (state, repo) = await setup();
      await tester.pumpWidget(shell(state));
      await tester.tap(find.text('Record delivery'));
      await tester.pumpAndSettle();
      expect(find.text('Proof of Delivery (POD)'), findsOneWidget);
      expect(find.text('Confirm delivery'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to Confirm delivery'),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Confirm delivery'), findsNothing);
      expect(repo.keys, isEmpty);
      await tester.tap(find.text('Record delivery'));
      await tester.pumpAndSettle();
      expect(find.text('Proof of Delivery (POD)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'confirmed saved proof unlocks continuation and delivery submission',
    (tester) async {
      final (state, repo) = await setup();
      repo.proofRead = Completer();
      await tester.pumpWidget(shell(state));
      await tester.tap(find.text('Record delivery'));
      await tester.pumpAndSettle();
      final next = find.widgetWithText(
        FilledButton,
        'Continue to Confirm delivery',
      );
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      repo.savedProofs = [
        {'id': 'proof', 'kind': 'signature', 'createdAt': 'now'},
      ];
      repo.proofRead!.complete(repo.savedProofs);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Proof of Delivery (POD)'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();
      expect(repo.keys, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed proof verification blocks continuation', (tester) async {
    final (state, repo) = await setup();
    repo.failProofRead = true;
    await tester.pumpWidget(shell(state));
    await tester.tap(find.text('Record delivery'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Proofs unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue to Confirm delivery'),
          )
          .onPressed,
      isNull,
    );
    expect(repo.keys, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'outcome checks saved POD again and failed attempts do not require POD',
    () async {
      final (state, repo) = await setup();
      final trip = state.trips.single, stop = state.trips.single.stops.single;
      await expectLater(
        state.recordOutcome(trip, stop),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Submit Proof of Delivery'),
          ),
        ),
      );
      expect(repo.keys, isEmpty);
      repo.failProofRead = true;
      await expectLater(state.recordOutcome(trip, stop), throwsStateError);
      expect(repo.keys, isEmpty);
      await state.recordOutcome(trip, stop, reason: 'Customer unavailable');
      expect(repo.keys, hasLength(1));
    },
  );
}
