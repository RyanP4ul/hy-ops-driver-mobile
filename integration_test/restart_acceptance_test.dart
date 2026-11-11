import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hyops_flutter/api/api_client.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/services/offline_policy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Remembered session survives actual Android force-stop/relaunch; logout persists across clients',
    (tester) async {
      final client = ApiClient();
      await client.restore();
      expect(client.remember, true);
      final repo = DriverRepository(client);
      final origin = client.dio.options.baseUrl;
      client.dio.options.baseUrl = 'http://127.0.0.1:1';
      expect((await repo.profile()).id, '3');
      expect(repo.offline, true);
      final cachedTrips = await repo.trips();
      expect(cachedTrips.items, isNotEmpty);
      await expectLater(
        repo.startTrip(cachedTrips.items.first),
        throwsA(isA<OfflineActionBlocked>()),
      );
      client.dio.options.baseUrl = origin;
      await client.validate();
      repo.beginReadCycle();
      await repo.profile();
      await repo.trips();
      await repo.history();
      repo.completeRefresh();
      expect(repo.offline, false);
      expect((await DriverRepository(client).profile()).id, '3');
      expect(await client.logout(), true);
      final afterLogout = ApiClient();
      await afterLogout.restore();
      expect(afterLogout.remember, false);
    },
  );
}
