enum TipoObstaculo {
  ninguno,
  escalera,
  rampa,
  puertaPesada;

  static TipoObstaculo fromJson(String value) {
    switch (value.toUpperCase()) {
      case 'NINGUNO':
        return TipoObstaculo.ninguno;
      case 'ESCALERA':
        return TipoObstaculo.escalera;
      case 'RAMPA':
        return TipoObstaculo.rampa;
      case 'PUERTA_PESADA':
        return TipoObstaculo.puertaPesada;
      default:
        throw ArgumentError('TipoObstaculo desconocido: $value');
    }
  }

  String toJson() {
    switch (this) {
      case TipoObstaculo.ninguno:
        return 'NINGUNO';
      case TipoObstaculo.escalera:
        return 'ESCALERA';
      case TipoObstaculo.rampa:
        return 'RAMPA';
      case TipoObstaculo.puertaPesada:
        return 'PUERTA_PESADA';
    }
  }
}
