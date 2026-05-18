class GrafoInvalidoException implements Exception {
  final String message;
  const GrafoInvalidoException(this.message);
  @override
  String toString() => 'GrafoInvalidoException: $message';
}

class GrafoParseException implements Exception {
  final String message;
  const GrafoParseException(this.message);
  @override
  String toString() => 'GrafoParseException: $message';
}

class NodeNotFoundException implements Exception {
  final String id;
  const NodeNotFoundException(this.id);
  @override
  String toString() => 'NodeNotFoundException: nodo "$id" no existe en el grafo';
}

class RouteNotFoundException implements Exception {
  final String message;
  const RouteNotFoundException(this.message);
  @override
  String toString() => 'RouteNotFoundException: $message';
}

class NoAccessibleRouteException implements Exception {
  @override
  String toString() =>
      'NoAccessibleRouteException: No existe ruta accesible entre estos puntos. '
      '¿Deseas ver la ruta estándar?';
}

class BeaconNotFoundException implements Exception {
  final int minor;
  const BeaconNotFoundException(this.minor);
  @override
  String toString() => 'BeaconNotFoundException: minor $minor no registrado';
}
