enum TipoNodo {
  salon,
  bano,
  oficina,
  ascensor,
  escalera,
  bebedero,
  comedor,
  interseccion,
  entrada,
  marcadorAr;

  static TipoNodo fromJson(String value) {
    switch (value.toUpperCase()) {
      case 'SALON':
        return TipoNodo.salon;
      case 'BANO':
      case 'BAÑO':
        return TipoNodo.bano;
      case 'OFICINA':
        return TipoNodo.oficina;
      case 'ASCENSOR':
        return TipoNodo.ascensor;
      case 'ESCALERA':
        return TipoNodo.escalera;
      case 'BEBEDERO':
        return TipoNodo.bebedero;
      case 'COMEDOR':
        return TipoNodo.comedor;
      case 'INTERSECCION':
        return TipoNodo.interseccion;
      case 'ENTRADA':
        return TipoNodo.entrada;
      case 'MARCADOR_AR':
        return TipoNodo.marcadorAr;
      default:
        throw ArgumentError('TipoNodo desconocido: $value');
    }
  }

  String toJson() {
    switch (this) {
      case TipoNodo.salon:
        return 'SALON';
      case TipoNodo.bano:
        return 'BANO';
      case TipoNodo.oficina:
        return 'OFICINA';
      case TipoNodo.ascensor:
        return 'ASCENSOR';
      case TipoNodo.escalera:
        return 'ESCALERA';
      case TipoNodo.bebedero:
        return 'BEBEDERO';
      case TipoNodo.comedor:
        return 'COMEDOR';
      case TipoNodo.interseccion:
        return 'INTERSECCION';
      case TipoNodo.entrada:
        return 'ENTRADA';
      case TipoNodo.marcadorAr:
        return 'MARCADOR_AR';
    }
  }
}
