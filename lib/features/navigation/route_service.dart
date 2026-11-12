import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config.dart';

class RouteSummary {
  final List<LatLng> points;
  final double? distanceMeters;
  final double? durationSeconds;

  const RouteSummary({
    required this.points,
    this.distanceMeters,
    this.durationSeconds,
  });
}

abstract class RouteService {
  Future<List<LatLng>> route(LatLng from, LatLng to);

  Future<RouteSummary> routeSummary(LatLng from, LatLng to) async =>
      RouteSummary(points: await route(from, to));
}

class RoadRouteService extends RouteService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  @override
  Future<List<LatLng>> route(LatLng from, LatLng to) async =>
      (await routeSummary(from, to)).points;

  @override
  Future<RouteSummary> routeSummary(LatLng from, LatLng to) async {
    final origin = Uri.parse(Config.routingUrl);
    if (!origin.hasAuthority || origin.scheme != 'https') {
      throw StateError('Configure an HTTPS routing service.');
    }
    final response = await _dio.get<dynamic>(
      '${origin.toString().replaceFirst(RegExp(r'/$'), '')}/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      queryParameters: {'overview': 'full', 'geometries': 'geojson'},
    );
    final data = response.data as Map;
    if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
      throw StateError('No road route is available.');
    }
    final first = (data['routes'] as List).first as Map;
    final points = ((first['geometry']['coordinates'] as List))
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();
    final distance = (first['distance'] as num?)?.toDouble();
    final duration = (first['duration'] as num?)?.toDouble();
    return RouteSummary(
      points: points,
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }
}
