import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config.dart';

abstract class RouteService {
  Future<List<LatLng>> route(LatLng from, LatLng to);
}

class RoadRouteService implements RouteService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  @override
  Future<List<LatLng>> route(LatLng from, LatLng to) async {
    final origin = Uri.parse(Config.routingUrl);
    if (!origin.hasAuthority || origin.scheme != 'https')
      throw StateError('Configure an HTTPS routing service.');
    final response = await _dio.get<dynamic>(
      '${origin.toString().replaceFirst(RegExp(r'/$'), '')}/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      queryParameters: {'overview': 'full', 'geometries': 'geojson'},
    );
    final data = response.data as Map;
    if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty)
      throw StateError('No road route is available.');
    return ((data['routes'] as List).first['geometry']['coordinates'] as List)
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();
  }
}
