/// Flags de configuración a nivel de app (compile-time).
library;

/// Realidad Aumentada. **Desactivada**: la AR no se usa en el piloto (era
/// solo un placeholder con minimapa, sin AR real). Se deja el código en su
/// sitio pero apagado tras este flag — poner en `true` lo reactiva (FAB de
/// cámara en el mapa, cambio por inclinación del acelerómetro, toggle de
/// "AR automático" en Ajustes).
const bool kArHabilitado = false;

/// Beacon simulado / modo simulación. **Desactivado** (soft-delete): el
/// simulador BLE ya no aporta (las pruebas se hacen con balizas/emisores
/// reales). Se deja el código en su sitio pero **desconectado** tras este flag.
/// Con `false`: la fuente BLE es directamente la real, el simulador no se
/// construye ni corre, y el toggle "Modo simulación" no aparece en Ajustes.
/// Poner en `true` reconecta el multiplexer real/simulado (ver ADR-0008).
const bool kSimuladorHabilitado = false;
