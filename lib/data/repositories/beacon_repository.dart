import 'dart:convert';
import 'package:flutter/services.dart';
import '../../models/position.dart';
import '../exceptions.dart';

class BeaconRepository {
  Map<String, dynamic>? _cachedData;

  Future<Map<String, dynamic>> _load() async {
    if (_cachedData != null) return _cachedData!;
    try {
      final raw = await rootBundle.loadString('assets/data/beacon_config.json');
      _cachedData = jsonDecode(raw) as Map<String, dynamic>;
      return _cachedData!;
    } catch (e) {
      throw Exception('Error al parsear beacon_config.json: $e');
    }
  }

  Future<Position> obtenerPosicion(int minor) async {
    final data = await _load();
    final beacons = data['beacons'] as List<dynamic>;
    final match = beacons
        .cast<Map<String, dynamic>>()
        .where((b) => b['minor'] == minor)
        .firstOrNull;
    if (match == null) throw BeaconNotFoundException(minor);
    return Position(
      x: (match['x'] as num).toDouble(),
      y: (match['y'] as num).toDouble(),
      piso: data['major'] as int,
      timestamp: DateTime.now(),
    );
  }

  Future<List<int>> obtenerMinorsRegistrados() async {
    final data = await _load();
    final beacons = data['beacons'] as List<dynamic>;
    return beacons
        .cast<Map<String, dynamic>>()
        .map((b) => b['minor'] as int)
        .toList();
  }
}
