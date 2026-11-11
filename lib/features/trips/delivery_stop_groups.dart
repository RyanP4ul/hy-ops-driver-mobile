import '../../data/models.dart';

/// Groups only explicit order-group IDs, retaining first appearance in the trip.
List<List<Stop>> deliveryStopGroups(List<Stop> stops) {
  final groups = <List<Stop>>[];
  final byGroup = <String, List<Stop>>{};
  for (final stop in stops) {
    if (!stop.isGroupedOrder) {
      groups.add([stop]);
      continue;
    }
    final existing = byGroup[stop.orderGroupId];
    if (existing != null) {
      existing.add(stop);
    } else {
      final group = [stop];
      byGroup[stop.orderGroupId] = group;
      groups.add(group);
    }
  }
  return groups;
}
