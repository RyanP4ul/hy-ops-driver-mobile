import 'models.dart';

class Mock {
  static final driver = Driver('Ivan Paring', 'DRV-0042', '+60 12-555 0142', 'Truck 1', 'WXY 4821');

  static List<Trip> trips() {
    final now = DateTime.now();
    return [
      Trip(
        id: 'TRP-2026-071',
        kind: 'Multi-delivery',
        truck: 'Truck 1',
        warehouse: 'Depot A - North Logistics',
        status: TripStatus.inProgress,
        stops: [
          Stop(
            id: 's1', customer: 'Alpha Clinic', payment: PaymentArrangement.fullyPaid, total: 480, paid: 480, lat: 3.0733, lng: 101.5185,
            address: 'Depot A, 12 Jalan Perdagangan, Shah Alam, Selangor',
            contact: 'Sarah Lim', phone: '+60 12-345 6789', distanceKm: 0, etaMin: 0,
            items: [Item('Surgical Masks', 10), Item('Gloves (box)', 4)],
            status: StopStatus.delivered, doneAt: now.subtract(Duration(hours: 3)),
          ),
          Stop(
            id: 's2', customer: 'North Market Pharmacy', payment: PaymentArrangement.partiallyPaid, total: 920, paid: 400, lat: 3.139, lng: 101.6869,
            address: 'Lot 12, North Market Avenue, Taman Mutiara, Kuala Lumpur',
            contact: 'Daniel Wong', phone: '+60 13-222 9081', distanceKm: 6.2, etaMin: 14,
            items: [Item('Vitamin C', 6), Item('Paracetamol', 12)],
            status: StopStatus.delivered, doneAt: now.subtract(Duration(hours: 2, minutes: 10)),
          ),
          Stop(
            id: 's3', customer: 'Sunrise Wellness', payment: PaymentArrangement.net30, total: 360, paid: 0, lat: 3.1073, lng: 101.6067,
            address: '45 Jalan Sunrise 3, Petaling Jaya, Selangor',
            contact: 'Aisha Rahman', phone: '+60 16-880 1123', distanceKm: 9.8, etaMin: 22,
            items: [Item('Hand Sanitizer', 8)],
            status: StopStatus.delivered, doneAt: now.subtract(Duration(hours: 1)),
          ),
          Stop(
            id: 's4', customer: 'Greenfield Pharmacy', payment: PaymentArrangement.partiallyPaid, total: 215.5, paid: 100, lat: 3.165, lng: 101.615,
            address: '88 Jalan Sentral 8, Bandar Putra, Kuala Lumpur',
            contact: 'Mei Ling Tan', phone: '+60 12-700 4455', distanceKm: 8.6, etaMin: 19,
            items: [Item('Cough Syrup', 1), Item('Thermometer', 2)],
            status: StopStatus.inTransit,
          ),
        ],
      ),
      Trip(
        id: 'TRP-2026-072',
        kind: 'Single delivery',
        truck: 'TRK-21',
        warehouse: 'Depot A - North Logistics',
        status: TripStatus.loading,
        stops: [
          Stop(
            id: 's1', customer: 'Bayview Medical Centre', payment: PaymentArrangement.net30, total: 1850, paid: 0, lat: 3.08, lng: 101.53,
            address: '12 Jalan Perdagangan, Shah Alam, Selangor',
            contact: 'Dr. Raj Kumar', phone: '+60 11-3000 7712', distanceKm: 14.3, etaMin: 31,
            items: [Item('IV Fluids', 20), Item('Syringes (box)', 5), Item('Bandages', 30)],
          ),
        ],
      ),
      Trip(
        id: 'TRP-2026-070',
        kind: 'Single delivery',
        truck: 'Truck 1',
        warehouse: 'Depot A - North Logistics',
        status: TripStatus.completed,
        stops: [
          Stop(
            id: 's1', customer: 'City Care Clinic', payment: PaymentArrangement.fullyPaid, total: 128, paid: 128, lat: 3.1, lng: 101.74,
            address: '7 Jalan Medan 2, Cheras, Kuala Lumpur',
            contact: 'Priya Nair', phone: '+60 12-909 3321', distanceKm: 11.1, etaMin: 26,
            items: [Item('Antiseptic', 2), Item('Cotton Rolls', 2)],
            status: StopStatus.delivered, doneAt: DateTime(now.year, now.month, now.day, 9, 30),
          ),
        ],
      ),
    ];
  }

  static List<HistoryEntry> history() {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    final t71 = trips()[0];
    final t70 = trips()[2];
    HistoryEntry old(String customer, String trip, String outcome, String summary, DateTime when,
            {required String address,
            required String contact,
            required String phone,
            required List<Item> items,
            required PaymentArrangement payment,
            required double total,
            required double paid,
            String? reason}) =>
        HistoryEntry(
          customer: customer, tripId: trip, outcome: outcome, summary: summary,
          success: outcome == 'Delivered', when: when, address: address, contact: contact, phone: phone,
          items: items, payment: payment, total: total, paid: paid, reason: reason,
        );
    return [
      HistoryEntry.fromStop(t70, t70.stops[0], outcome: 'Delivered'),
      HistoryEntry.fromStop(t71, t71.stops[0], outcome: 'Delivered'),
      HistoryEntry.fromStop(t71, t71.stops[1], outcome: 'Delivered'),
      HistoryEntry.fromStop(t71, t71.stops[2], outcome: 'Delivered'),
      old('Harmony Dental', 'TRP-2026-066', 'Failed', 'Customer unavailable', d.subtract(Duration(days: 1, hours: -10)),
          address: '21 Jalan Harmoni 5, Subang Jaya, Selangor', contact: 'Dr. Tan', phone: '+60 12-410 8800',
          items: [Item('Dental Floss', 20)], payment: PaymentArrangement.net30, total: 240, paid: 0,
          reason: 'Customer unavailable'),
      old('Lakeside Pharmacy', 'TRP-2026-065', 'Delivered', 'Delivered 22 products', d.subtract(Duration(days: 2, hours: -11)),
          address: '3 Persiaran Tasik, Cyberjaya, Selangor', contact: 'Nurul Huda', phone: '+60 13-777 2201',
          items: [Item('Antiseptic', 10), Item('Gauze Pads', 12)], payment: PaymentArrangement.partiallyPaid, total: 640, paid: 300),
      old('Metro Health Hub', 'TRP-2026-059', 'Delivered', 'Delivered 9 products', d.subtract(Duration(days: 6, hours: -14)),
          address: '58 Jalan Ampang, Kuala Lumpur', contact: 'Kevin Ooi', phone: '+60 16-300 5512',
          items: [Item('Thermometer', 4), Item('Surgical Masks', 5)], payment: PaymentArrangement.fullyPaid, total: 410, paid: 410),
      old('Orchid Family Clinic', 'TRP-2026-047', 'Delivered', 'Delivered 12 products', d.subtract(Duration(days: 15, hours: -9)),
          address: '9 Jalan Orked, Petaling Jaya, Selangor', contact: 'Dr. Lee', phone: '+60 12-888 4040',
          items: [Item('Vitamin D', 12)], payment: PaymentArrangement.net30, total: 520, paid: 0),
      old('Pearl Medical', 'TRP-2026-041', 'Failed', 'Wrong address', d.subtract(Duration(days: 21, hours: -13)),
          address: '77 Jalan Mutiara, Klang, Selangor', contact: 'Hui Min', phone: '+60 11-2200 9087',
          items: [Item('Surgical Gloves', 6)], payment: PaymentArrangement.fullyPaid, total: 150, paid: 150,
          reason: 'Wrong address'),
    ];
  }
}
