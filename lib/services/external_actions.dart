import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches the phone dialer for [phone], returning true if the OS accepted it.
Future<bool> callPhoneNumber(String phone) async {
  final sanitized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (sanitized.isEmpty) return false;
  final uri = Uri(scheme: 'tel', path: sanitized);
  try {
    return await launchUrl(uri);
  } on MissingPluginException {
    return false;
  } catch (_) {
    return false;
  }
}

/// Opens external turn-by-turn navigation (Google Maps / default maps app)
/// to the specified coordinates.
Future<bool> openExternalDirections(double lat, double lng) async {
  if (!lat.isFinite || !lng.isFinite) return false;
  final mapsUri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$lat,$lng',
    'travelmode': 'driving',
  });
  try {
    if (await launchUrl(mapsUri, mode: LaunchMode.externalApplication)) {
      return true;
    }
    return await launchUrl(Uri.parse('geo:$lat,$lng?q=$lat,$lng'));
  } on MissingPluginException {
    return false;
  } catch (_) {
    return false;
  }
}
