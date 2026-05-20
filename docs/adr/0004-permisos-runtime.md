# ADR-0004 — Manejo de permisos BLE en runtime con `permission_handler`

- **Estado:** aceptado
- **Fecha:** 2026-05-19
- **Autor:** equipo UTP-Guide
- **Supersede:** la implementación inicial (sesión 2026-05-17) que dejaba fallar el escaneo silenciosamente cuando los permisos no estaban concedidos

## Contexto

Android 12 (API 31, diciembre 2021) introdujo permisos nuevos para Bluetooth:

- `BLUETOOTH_SCAN` — para descubrir dispositivos
- `BLUETOOTH_CONNECT` — para emparejarse / conectar
- `BLUETOOTH_ADVERTISE` — para emitir anuncios

Estos permisos son **dangerous** (categoría de Android), lo que significa que requieren **solicitud explícita en runtime**, no basta con declararlos en `AndroidManifest.xml`. Si el usuario no los concede, las llamadas a la API BLE devuelven errores silenciosos o lanzan `SecurityException`.

En versiones anteriores (API ≤ 30), Bluetooth requería `ACCESS_FINE_LOCATION` (también dangerous) además de `BLUETOOTH` y `BLUETOOTH_ADMIN` (normal).

La implementación inicial del proyecto declaraba los permisos en `AndroidManifest.xml` pero **no los solicitaba en runtime**. Resultado: en Android 12+ el escaneo BLE no arranca y el usuario no recibe feedback de por qué.

## Opciones consideradas

### Opción A — Manejo manual con `MethodChannel`

Implementar los `MethodChannel` directamente al código nativo Android (Kotlin) e iOS (Swift) para solicitar permisos.

- **Pros:** sin dependencia adicional
- **Contras:** ~150 líneas de código nativo en cada plataforma, requiere mantener ambas implementaciones sincronizadas, manejo manual de los enum results de cada API

### Opción B — Paquete `permission_handler` (Baseflow)

Paquete mantenido por Baseflow con **2M+ descargas mensuales**, soporte oficial para Android 12+, iOS, Windows, macOS, y manejo unificado de todos los permisos del sistema.

- **Pros:** API unificada, mantenido activamente, documentación extensa, casos especiales (permisos perpetuamente denegados, abrir settings) bien resueltos
- **Contras:** dependencia adicional en `pubspec.yaml`

### Opción C — flutter_blue_plus interno

Las versiones recientes de `flutter_blue_plus` (1.30+) intentan manejar algunos permisos automáticamente.

- **Pros:** sin dependencia adicional
- **Contras:** comportamiento inconsistente entre versiones del plugin, no maneja casos especiales (denied forever, request rationale), no expone API limpia para que la UI muestre estados intermedios

## Decisión

Usar **opción B: `permission_handler: ^11.3.0`**.

## Justificación

1. **Riesgo de divergencia:** el código nativo (opción A) divergiría entre Android e iOS con el tiempo. `permission_handler` ya resolvió las inconsistencias.

2. **Cobertura de casos de borde:** denied forever, permission rationale, navegación a settings, etc. son operaciones repetitivas y bien resueltas por el paquete.

3. **Tamaño del proyecto:** UTP-Guide está creciendo. En Fase 4 vamos a necesitar permisos de cámara (AR), micrófono (futuro), notificaciones. Tener un solo paquete que maneje todos los permisos es más mantenible que múltiples MethodChannel.

4. **Mantenimiento:** Baseflow mantiene el paquete activamente. Su puntuación en [pub.dev](https://pub.dev/packages/permission_handler) es alta (130+), última actualización reciente.

## Implementación

`BleService.iniciarEscaneo()` ahora ejecuta una secuencia previa:

1. Verificar permisos requeridos (depende de Android version)
2. Si falta alguno, solicitarlo
3. Si el usuario lo deniega, emitir `BleEstado.permisosNegados` y abortar
4. Verificar que el adaptador Bluetooth esté ON
5. Si está OFF, emitir `BleEstado.bluetoothApagado` y abortar
6. Iniciar el ciclo de escaneo

`BleService.estado` es un nuevo `Stream<BleEstado>` que la UI puede observar para mostrar el mensaje apropiado.

```dart
enum BleEstado {
  inactivo,           // Servicio detenido
  solicitandoPermisos,
  permisosNegados,    // Usuario negó algún permiso
  bluetoothApagado,   // BT del dispositivo está OFF
  escaneando,         // Todo OK, escaneando
  error,              // Error inesperado
}
```

`MapaScreen` se suscribe al stream `BleService.estado` y muestra:

- `permisosNegados` → diálogo "Activa los permisos de Bluetooth en Ajustes"
- `bluetoothApagado` → diálogo "Activa Bluetooth para ver tu posición"
- `escaneando` → chip BLE normal

## Consecuencias

### Positivas

- Permisos solicitados correctamente en Android 12+
- Feedback al usuario cuando algo falla
- Estado de BLE observable desde la UI sin acoplamiento al stack de Flutter Blue Plus
- Base sólida para agregar permisos de cámara y micrófono en Fase 3+

### Negativas

- Una dependencia más en `pubspec.yaml`
- Aumento del tamaño del APK (~200 KB con `permission_handler`)

### Riesgos

- Si `permission_handler` introduce un bug en una versión futura, podría afectar el flujo de inicialización. Mitigación: pin a `^11.3.0` y revisar changelog antes de actualizar.

## Referencias

- `permission_handler` en pub.dev: https://pub.dev/packages/permission_handler
- Android 12 BLE permissions: https://developer.android.com/develop/connectivity/bluetooth/bt-permissions
- Apple Core Bluetooth Best Practices: https://developer.apple.com/documentation/corebluetooth
