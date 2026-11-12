double remoteNumber(dynamic value) =>
    double.tryParse(value?.toString() ?? "") ?? double.nan;

enum PaymentArrangement { fullyPaid, partiallyPaid, payOnDelivery, net30 }

extension PaymentArrangementX on PaymentArrangement {
  /// Value used by the backend.
  String get code => switch (this) {
    PaymentArrangement.fullyPaid => 'FULLY_PAID',
    PaymentArrangement.partiallyPaid => 'PARTIALLY_PAID',
    PaymentArrangement.net30 => 'NET_30',
    PaymentArrangement.payOnDelivery => 'PAY_ON_DELIVERY',
  };
  String get label => switch (this) {
    PaymentArrangement.fullyPaid => 'Fully paid',
    PaymentArrangement.partiallyPaid => 'Partially paid',
    PaymentArrangement.net30 => 'Net 30',
    PaymentArrangement.payOnDelivery => 'Pay on delivery',
  };
}

enum StopStatus { pending, inTransit, arrived, delivered, failed, cancelled }

enum TripStatus { loading, inProgress, returning, completed, cancelled }

class Item {
  final String name;
  final int qty;
  final String variant;
  final String sku;
  final String unit;
  final String? imageUrl;
  final String productName;
  Item(
    this.name,
    this.qty, {
    this.variant = '',
    this.sku = '',
    this.unit = '',
    this.imageUrl,
    String? productName,
  }) : productName = productName ?? name;

  factory Item.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'Item';
    final variant = json['variant'] as String? ?? '';
    return Item(
      variant.isEmpty ? name : '$name - $variant',
      json['qty'] as int,
      productName: name,
      variant: variant,
      sku: json['sku'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class Stop {
  String? pendingSync, syncError;
  bool hasLocalProof = false;
  final String id;
  final String orderId;
  final String orderNumber;
  final String orderGroupId;
  final String orderGroupNumber;
  final String notes;
  final bool hasProof;
  bool get isGroupedOrder => orderGroupId.isNotEmpty;
  final String combinedPaymentNumber;
  final double combinedPaymentAllocation;
  String get orderLabel => orderNumber.isNotEmpty
      ? orderNumber
      : orderId.isNotEmpty
      ? 'Order #$orderId'
      : 'Stop #$id';
  final String customer;
  final String address;
  final String contact;
  final String phone;
  final double lat;
  final double lng;
  final double distanceKm;
  final int etaMin;
  final List<Item> items;
  final PaymentArrangement payment;
  final double total;
  final double paid;
  StopStatus status;
  DateTime? doneAt;
  String? failReason;
  bool canDeliver = false;
  bool canFail = false;
  double serverCollect = double.nan;
  bool get hasCoordinates =>
      lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

  Stop({
    required this.id,
    this.orderId = '',
    this.orderNumber = '',
    this.orderGroupId = '',
    this.orderGroupNumber = '',
    this.notes = '',
    this.hasProof = false,
    this.combinedPaymentNumber = '',
    this.combinedPaymentAllocation = double.nan,
    required this.customer,
    required this.address,
    required this.contact,
    required this.phone,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.etaMin,
    required this.items,
    this.payment = PaymentArrangement.fullyPaid,
    this.total = 0,
    this.paid = 0,
    this.status = StopStatus.pending,
    this.doneAt,
  });

  factory Stop.fromJson(Map<String, dynamic> j) {
    final stop = Stop(
      id: '${j['id']}',
      orderId: j['orderId']?.toString() ?? '',
      orderNumber: j['orderNumber'] as String? ?? '',
      orderGroupId: j['orderGroupId'] as String? ?? '',
      orderGroupNumber: j['orderGroupNumber'] as String? ?? '',
      notes: (j['notes'] as String? ?? '').trim(),
      hasProof: j['hasProof'] == true,
      combinedPaymentNumber: j['combinedPaymentNumber'] as String? ?? '',
      combinedPaymentAllocation: remoteNumber(j['combinedPaymentAllocation']),
      customer: j['customer'] as String? ?? 'Customer',
      address: j['address'] as String? ?? 'Address unavailable',
      contact: j['contact'] as String? ?? '',
      phone: j['phone'] as String? ?? '',
      lat: remoteNumber(j['latitude']),
      lng: remoteNumber(j['longitude']),
      distanceKm: double.nan,
      etaMin: 0,
      items: (j['items'] as List)
          .map((e) => Item.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      payment: PaymentArrangement.values.firstWhere(
        (p) => p.code == j['payment'],
      ),
      total: remoteNumber(j['total']),
      paid: remoteNumber(j['paid']),
      status: StopStatus.values.firstWhere((s) => s.name == j['status']),
      doneAt: DateTime.tryParse(j['doneAt']?.toString() ?? ''),
    );
    stop.canDeliver = j['canDeliver'] == true;
    stop.canFail = j['canFail'] == true;
    stop.serverCollect = remoteNumber(j['collectNow']);
    stop.failReason = j['reason'] as String?;
    stop.pendingSync = j['pendingSync'] as String?;
    stop.syncError = j['syncError'] as String?;
    stop.hasLocalProof = j['hasLocalProof'] == true;
    return stop;
  }

  bool get isDone =>
      status == StopStatus.delivered ||
      status == StopStatus.failed ||
      status == StopStatus.cancelled;
  int get itemCount => items.fold(0, (a, b) => a + b.qty);
  double get balance => total - paid;

  /// Cash the driver must collect at the door.
  double get collectNow => serverCollect;
}

class ReturnPickup {
  final String? pendingSync, syncError;
  final String id, orderNumber, customer, address, phone, reason, status;
  final int version;
  final double lat, lng;
  final List<Item> items;
  ReturnPickup.fromJson(Map<String, dynamic> j)
    : pendingSync = j['pendingSync'] as String?,
      syncError = j['syncError'] as String?,
      id = '${j['id']}',
      orderNumber = '${j['orderNumber']}',
      customer = j['customer'] as String? ?? 'Customer',
      address = j['address'] as String? ?? 'Address unavailable',
      phone = j['phone'] as String? ?? '',
      reason = j['reason'] as String? ?? '',
      status = j['status'] as String,
      version = j['version'] as int,
      lat = remoteNumber((j['coordinates'] as List?)?.elementAtOrNull(1)),
      lng = remoteNumber((j['coordinates'] as List?)?.elementAtOrNull(0)),
      items = (j['items'] as List? ?? [])
          .map((e) => Item(e['name'] as String, e['qty'] as int))
          .toList();
  bool get hasCoordinates =>
      lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;
}

class Trip {
  // Synced planning choices. Skipping never changes a delivery outcome.
  String? preferredStopId;
  final Set<String> deferredStopIds = {};
  final String id;
  final String kind; // Multi-delivery / Single delivery
  final String truck;
  final String warehouse;
  final List<ReturnPickup> pickups;
  final List<Stop> stops;
  TripStatus status;
  String? cancelReason;
  int version = 1;
  DateTime? scheduledAt;
  double warehouseLat = double.nan;
  double warehouseLng = double.nan;
  bool get hasWarehouseCoordinates =>
      warehouseLat.isFinite &&
      warehouseLng.isFinite &&
      warehouseLat.abs() <= 90 &&
      warehouseLng.abs() <= 180;

  Trip({
    required this.id,
    required this.kind,
    required this.truck,
    required this.warehouse,
    this.pickups = const [],
    required this.stops,
    required this.status,
  });

  factory Trip.fromJson(Map<String, dynamic> j) {
    final status = switch (j['status']) {
      'scheduled' => TripStatus.loading,
      'in_transit' => TripStatus.inProgress,
      'returning' => TripStatus.returning,
      'completed' => TripStatus.completed,
      'cancelled' => TripStatus.cancelled,
      _ => throw FormatException('Unsupported trip status'),
    };
    final t = Trip(
      pickups: (j['pickups'] as List? ?? [])
          .map(
            (e) => ReturnPickup.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      id: '${j['id']}',
      kind: j['kind'] as String,
      truck: '${j['vehicle']['type']} - ${j['vehicle']['plate']}',
      warehouse: j['warehouse']?['name'] as String? ?? 'Warehouse unavailable',
      stops: (j['stops'] as List)
          .map((e) => Stop.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      status: status,
    );
    t.version = j['version'] as int;
    t.scheduledAt = DateTime.tryParse(j['scheduledAt'] as String);
    t.warehouseLat = remoteNumber(j['warehouse']?['latitude']);
    t.warehouseLng = remoteNumber(j['warehouse']?['longitude']);
    final plan = j['stopPlan'] as Map?;
    if (status == TripStatus.inProgress && plan != null) {
      final pending = t.stops.where((s) => !s.isDone).map((s) => s.id).toSet();
      t.deferredStopIds.addAll(
        (plan['skippedStopIds'] as List? ?? [])
            .map((id) => '$id')
            .where(pending.contains),
      );
      final next = plan['nextStopId']?.toString();
      if (pending.contains(next) && !t.deferredStopIds.contains(next)) {
        t.preferredStopId = next;
      }
    }
    return t;
  }

  bool canStartAt(DateTime now) {
    final departure = scheduledAt;
    if (status != TripStatus.loading ||
        departure == null ||
        now.isBefore(departure))
      return false;
    final today = now.toUtc().add(const Duration(hours: 8));
    final day = departure.toUtc().add(const Duration(hours: 8));
    return today.year == day.year &&
        today.month == day.month &&
        today.day == day.day;
  }

  int get doneCount => stops
      .where(
        (s) =>
            s.status == StopStatus.delivered || s.status == StopStatus.failed,
      )
      .length;
  double get progress => stops.isEmpty ? 0 : doneCount / stops.length;
  Stop? get currentStop {
    for (final s in stops) {
      if (s.id == preferredStopId &&
          !s.isDone &&
          !deferredStopIds.contains(s.id)) {
        return s;
      }
    }
    for (final s in stops) {
      if (!s.isDone && !deferredStopIds.contains(s.id)) return s;
    }
    return null;
  }

  int get currentIndex {
    final c = currentStop;
    return c == null ? stops.length : stops.indexOf(c);
  }
}

class Driver {
  final String name;
  final String id;
  final String phone;
  final String truck;
  final String plate;
  Driver(this.name, this.id, this.phone, this.truck, this.plate);
  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
    j['name'] as String,
    '${j['id']}',
    j['phone'] as String? ?? '',
    'Assigned per trip',
    'See Trips',
  );
}

class HistoryEntry {
  final String combinedPaymentNumber;
  final double combinedPaymentAllocation;
  final String orderNumber;
  final String customer;
  final String tripId;
  final String outcome; // Delivered / Failed / Cancelled
  final String summary;
  final bool success;
  final DateTime when;
  final String address;
  final String contact;
  final String phone;
  final List<Item> items;
  final PaymentArrangement payment;
  final double total;
  final double paid;
  final String? reason;

  HistoryEntry({
    this.combinedPaymentNumber = '',
    this.combinedPaymentAllocation = double.nan,
    this.orderNumber = '',
    required this.customer,
    required this.tripId,
    required this.outcome,
    required this.summary,
    required this.success,
    required this.when,
    required this.address,
    required this.contact,
    required this.phone,
    required this.items,
    required this.payment,
    required this.total,
    required this.paid,
    this.reason,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) {
    final stop = Stop.fromJson(j);
    final success = stop.status == StopStatus.delivered;
    return HistoryEntry(
      orderNumber: stop.orderLabel,
      combinedPaymentNumber: stop.combinedPaymentNumber,
      combinedPaymentAllocation: stop.combinedPaymentAllocation,
      customer: stop.customer,
      tripId: '${j['tripId']}',
      outcome: success
          ? 'Delivered'
          : stop.status == StopStatus.cancelled
          ? 'Cancelled'
          : 'Failed',
      summary:
          stop.failReason ??
          (success ? 'Delivery confirmed' : 'Outcome recorded'),
      success: success,
      when:
          stop.doneAt ??
          (throw FormatException('History timestamp is missing')),
      address: stop.address,
      contact: stop.contact,
      phone: stop.phone,
      items: stop.items,
      payment: stop.payment,
      total: stop.total,
      paid: stop.paid,
      reason: stop.failReason,
    );
  }

  int get itemCount => items.fold(0, (a, b) => a + b.qty);

  factory HistoryEntry.fromStop(Trip trip, Stop s, {required String outcome}) =>
      HistoryEntry(
        orderNumber: s.orderLabel,
        combinedPaymentNumber: s.combinedPaymentNumber,
        combinedPaymentAllocation: s.combinedPaymentAllocation,
        customer: s.customer,
        tripId: trip.id,
        outcome: outcome,
        summary: switch (outcome) {
          'Delivered' => 'Delivered ${s.itemCount} products',
          'Cancelled' => 'Cancelled: ${s.failReason}',
          _ => s.failReason ?? 'Failed',
        },
        success: outcome == 'Delivered',
        when: s.doneAt ?? DateTime.now(),
        address: s.address,
        contact: s.contact,
        phone: s.phone,
        items: s.items,
        payment: s.payment,
        total: s.total,
        paid: s.paid,
        reason: outcome == 'Delivered' ? null : s.failReason,
      );
}
