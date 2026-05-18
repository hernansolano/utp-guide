# UTP-Guide

**Navegación interior inclusiva para el campus de la Universidad Tecnológica de Panamá.**

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey)
![Status](https://img.shields.io/badge/Estado-En%20desarrollo-yellow)

---

## Descripción

UTP-Guide es una aplicación móvil de navegación interior diseñada para el edificio de la Facultad de Ingeniería de Sistemas Computacionales (FISC). Ayuda a estudiantes de nuevo ingreso, visitantes de intercambio internacional y personas con discapacidad motora a encontrar salones, oficinas y servicios dentro del edificio sin depender de señalización física. La aplicación genera rutas personalizadas según el perfil de movilidad del usuario, incluyendo trayectos sin escaleras para quienes lo necesitan. Este proyecto es parte del programa **SUCCESS** financiado por **Erasmus+** de la Unión Europea.

---

## Demo

> Screenshots disponibles próximamente.
>
> <!-- Agregar capturas de pantalla aquí -->

---

## Características

### Fase 1 — Disponible
- Mapa 2D estático del tercer piso de FISC
- Ruteo con algoritmo A* (mínima distancia)
- Filtro de destinos por tipo: salones, oficinas, servicios, ascensores
- Perfil estándar y perfil accesible (sin escaleras)

### Fase 2 — En desarrollo
- Posicionamiento en tiempo real mediante balizas BLE (Bluetooth Low Energy)
- Punto azul de ubicación del usuario sobre el mapa
- Actualización de ruta dinámica

### Fase 3 — Planificada
- Guía visual en Realidad Aumentada (AR)
- Cambio automático mapa 2D ↔ AR según la inclinación del teléfono
- Marcadores ArUco para inicialización del sistema de coordenadas

---

## Requisitos

- Flutter 3.x (con Dart 3.x)
- Android 6.0 o superior (API 23+) · iOS 13 o superior
- Bluetooth activado en el dispositivo (requerido a partir de Fase 2)

---

## Instalación

```bash
git clone https://github.com/hernansolano/ariadna-utp.git
cd ariadna-utp
flutter pub get
flutter run
```

> Asegúrate de tener un dispositivo físico o emulador conectado antes de correr `flutter run`.

---

## Estructura del proyecto

```
lib/
├── data/
│   ├── grafo.json              # Nodos, aristas y pesos del piso
│   ├── beacon_config.json      # Coordenadas de cada baliza BLE
│   └── repositories/           # Carga y validación de datos locales
├── models/                     # Entidades del dominio (Nodo, Arista, Position…)
├── services/
│   ├── routing_service.dart    # Algoritmo A* y lógica de perfiles
│   ├── ble_service.dart        # Escaneo y stream de balizas BLE
│   └── positioning_service.dart # Trilateración y snap-to-graph
└── ui/
    ├── screens/                # Pantallas: Inicio, Mapa, Búsqueda, Ajustes
    ├── widgets/                # Componentes reutilizables
    └── theme/                  # Design tokens: colores, tipografía, espaciado
```

---

## Tecnologías utilizadas

| Tecnología | Uso |
|-----------|-----|
| Flutter / Dart | Framework principal multiplataforma |
| flutter_blue_plus | Escaneo de balizas BLE (Fase 2) |
| ar_flutter_plugin | Capa de Realidad Aumentada (Fase 3) |
| flutter_svg | Renderizado del mapa vectorial 2D |
| go_router | Navegación entre pantallas |
| sensors_plus | Acelerómetro para cambio mapa ↔ AR |
| Algoritmo A* | Cálculo de rutas óptimas sobre grafo de piso |

---

## Equipo

Desarrollado por estudiantes de la **Facultad de Ingeniería de Sistemas Computacionales (FISC)** de la Universidad Tecnológica de Panamá, en el marco del programa **SUCCESS** financiado por **Erasmus+** de la Unión Europea.

<!-- Agregar nombres del equipo aquí -->

---

## Licencia

Distribuido bajo la licencia MIT. Ver [`LICENSE`](LICENSE) para más detalles.
