# ADR-0009 — Política de pinning de dependencias

- **Estado:** aceptado
- **Fecha:** 2026-05-20
- **Autor:** equipo UTP-Guide

## Contexto

Cada dependencia en `pubspec.yaml` es una superficie de ataque potencial vía supply-chain. Casos documentados de paquetes comprometidos en los últimos años:

- `event-stream` (npm, 2018) — un mantenedor secundario inyectó malware que robaba wallets
- `ua-parser-js` (npm, 2021) — token del mantenedor comprometido, versión maliciosa publicada
- `colors.js` y `faker.js` (npm, 2022) — protest-driven sabotage
- `xz-utils` (Linux, 2024) — backdoor de larga ejecución oculto en build artifacts
- Múltiples paquetes en PyPI, RubyGems y pub.dev cada año

La sintaxis convencional de Dart `^1.2.3` permite actualizaciones automáticas a cualquier versión `1.x.x` posterior siempre que `flutter pub get` corra. Esto es conveniente para tomar parches menores, pero también es el vector exacto de un supply-chain attack: el atacante publica una versión maliciosa dentro del rango compatible y la app de cualquier desarrollador la consume en su próximo build.

## Decisión

Aplicar **dos niveles de estricticidad** según el rol de la dependencia:

### Nivel 1 — Dependencias críticas: pin exacto

Para paquetes con código nativo, permisos de sistema, o acceso a datos sensibles, usar **versión exacta sin caret**:

```yaml
flutter_tts: 4.2.5         # pinned exact
permission_handler: ^11.3.0  # ← se debería migrar a exacto
flutter_blue_plus: ^1.31.0   # ← se debería migrar a exacto
```

Estos paquetes ejecutan código nativo (Kotlin/Swift/C++) y/o solicitan permisos del sistema operativo. Un upgrade no revisado puede introducir cambios de comportamiento difíciles de detectar en testing.

**Proceso para subir de versión:**

1. Revisar el `CHANGELOG.md` del paquete entre la versión actual y la nueva
2. Verificar que no haya cambios sospechosos en los commits (cambios de mantenedor, código ofuscado, nuevas dependencias)
3. Re-correr la auditoría inicial (pub.dev, GitHub, CVEs)
4. Actualizar el pin en `pubspec.yaml`
5. `flutter pub get` y `flutter analyze`
6. Test manual del feature afectado
7. Commit con mensaje `[security] revisar y subir <paquete> a vX.Y.Z`

### Nivel 2 — Dependencias estándar: caret

Para utilidades sin código nativo y sin permisos (ej: `google_fonts`, `go_router`), seguir usando caret:

```yaml
go_router: ^13.0.0
google_fonts: ^6.2.1
```

El upside de tomar parches menores automáticamente supera el riesgo. Aún así, revisar el changelog antes de cada `pub upgrade` consciente.

## Auditoría obligatoria antes de agregar cualquier dependencia nueva

Documentar el resultado en el mensaje del commit o en un ADR si la decisión es no trivial:

| Verificación | Fuente |
|---|---|
| Publisher verificado en pub.dev | pub.dev página del paquete |
| Likes, downloads, pub points | pub.dev |
| Repositorio GitHub público y activo | GitHub stars/forks/commits |
| Sin security advisories abiertos | GitHub `/security/advisories` |
| Sin CVEs registrados | OpenCVE, NVD, Snyk |
| Licencia compatible (MIT, BSD, Apache 2.0) | pub.dev y archivo LICENSE |
| Dependencias transitivas auditables | pub.dev árbol de deps |
| El paquete hace solo lo que dice (no acceso a red sorpresa) | Código fuente |

Para paquetes de gobiernos extranjeros, empresas no verificadas, o publishers nuevos, requerir aprobación explícita en revisión por pares antes de adoptar.

## Consecuencias

### Positivas

- **Builds reproducibles** — el mismo `pubspec.yaml` siempre instala los mismos bytes
- **Ventana de exposición limitada** — un compromiso recién publicado no entra a la app automáticamente
- **Trazabilidad** — cada upgrade es un commit explícito con su justificación
- **Cultura de auditoría** — agregar una dependencia es un acto consciente, no un side effect de tomar una utility de Stack Overflow

### Negativas

- **Más fricción para tomar parches menores** — si sale un fix de seguridad menor, hay que actualizar manualmente
- **Riesgo de quedar atrás** — si nadie revisa updates por meses, podemos estar usando versiones con bugs conocidos

### Mitigaciones

- Definir una rutina mensual de revisión: `flutter pub outdated` + revisar changelogs de paquetes con upgrade disponible
- Suscribirse a las páginas de pub.dev de las dependencias críticas (envían notificación de nueva versión por email si tienes cuenta)
- En CI futura, agregar un step que falle el build si alguna dependencia tiene CVE conocido (ej: usando `dart pub deps --json` + un escáner externo)

## Auditorías ya realizadas

- `flutter_tts: 4.2.5` — auditada el 2026-05-20. Publisher verified (eyedeadevelopment.com), 215k+ downloads, 0 CVEs, código sin llamadas de red. Pin aplicado.

Cuando se audite la actualización de un paquete críticamente pineado, agregar una línea aquí con la fecha y el nuevo veredicto.

## Referencias

- [Supply-chain Levels for Software Artifacts (SLSA)](https://slsa.dev/)
- "Inside the unnerving CCleaner supply chain attack" — Wired, 2017
- "The xz utils backdoor" — análisis técnico del incidente
