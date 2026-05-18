import 'package:flutter/material.dart';
import '../../models/nodo.dart';
import '../../models/tipo_nodo.dart';
import '../theme/app_theme.dart';

class DestinoPicker extends StatefulWidget {
  final List<Nodo> todosLosNodos;
  final Function(Nodo) onDestinoSeleccionado;

  const DestinoPicker({
    super.key,
    required this.todosLosNodos,
    required this.onDestinoSeleccionado,
  });

  @override
  State<DestinoPicker> createState() => _DestinoPickerState();
}

class _DestinoPickerState extends State<DestinoPicker> {
  TipoNodo? _tipoSeleccionado;
  String _busqueda = '';
  final _controller = TextEditingController();

  static const _filtros = [
    (label: 'Todos', tipo: null as TipoNodo?),
    (label: 'Salones', tipo: TipoNodo.salon as TipoNodo?),
    (label: 'Servicios', tipo: TipoNodo.bano as TipoNodo?),
    (label: 'Oficinas', tipo: TipoNodo.oficina as TipoNodo?),
    (label: 'Bebederos', tipo: TipoNodo.bebedero as TipoNodo?),
    (label: 'Comedores', tipo: TipoNodo.comedor as TipoNodo?),
    (label: 'Ascensores', tipo: TipoNodo.ascensor as TipoNodo?),
  ];

  List<Nodo> get _nodosFiltrados {
    var lista = widget.todosLosNodos.where((n) {
      final matchTipo =
          _tipoSeleccionado == null || n.tipo == _tipoSeleccionado;
      final matchTexto = _busqueda.isEmpty ||
          n.nombre.toLowerCase().contains(_busqueda.toLowerCase());
      return matchTipo && matchTexto;
    }).toList();

    // Primero los del tipo seleccionado, luego el resto
    if (_tipoSeleccionado != null) {
      lista.sort((a, b) {
        final aTipo = a.tipo == _tipoSeleccionado ? 0 : 1;
        final bTipo = b.tipo == _tipoSeleccionado ? 0 : 1;
        return aTipo.compareTo(bTipo);
      });
    }
    return lista;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: 'Buscar destino...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          ),
          onChanged: (v) => setState(() => _busqueda = v),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _filtros.map((f) {
              final selected = _tipoSeleccionado == f.tipo;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(f.label),
                  selected: selected,
                  selectedColor: context.colors.brand,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                  ),
                  onSelected: (_) =>
                      setState(() => _tipoSeleccionado = f.tipo),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        ..._nodosFiltrados.map((n) => ListTile(
              dense: true,
              title: Text(n.nombre),
              subtitle: Text(_labelTipo(n.tipo)),
              trailing: n.accesible
                  ? Icon(Icons.accessible,
                      color: context.colors.accessible, size: 18)
                  : null,
              onTap: () => widget.onDestinoSeleccionado(n),
            )),
      ],
    );
  }

  String _labelTipo(TipoNodo tipo) {
    switch (tipo) {
      case TipoNodo.salon:
        return 'Salón';
      case TipoNodo.bano:
        return 'Servicios';
      case TipoNodo.oficina:
        return 'Oficina';
      case TipoNodo.ascensor:
        return 'Ascensor';
      case TipoNodo.escalera:
        return 'Escalera';
      case TipoNodo.bebedero:
        return 'Bebedero';
      case TipoNodo.comedor:
        return 'Comedor';
      case TipoNodo.interseccion:
        return 'Intersección';
      case TipoNodo.entrada:
        return 'Entrada';
      case TipoNodo.marcadorAr:
        return 'Marcador AR';
    }
  }
}
