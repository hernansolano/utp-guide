/// Flags de configuración a nivel de app (compile-time).
library;

/// Realidad Aumentada. **Desactivada**: la AR no se usa en el piloto (era
/// solo un placeholder con minimapa, sin AR real). Se deja el código en su
/// sitio pero apagado tras este flag — poner en `true` lo reactiva (FAB de
/// cámara en el mapa, cambio por inclinación del acelerómetro, toggle de
/// "AR automático" en Ajustes).
const bool kArHabilitado = false;
