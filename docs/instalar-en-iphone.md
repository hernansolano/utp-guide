# Instalar la app en un iPhone sin Mac

Para compilar una app de iOS hace falta macOS + Xcode; desde Windows no se puede.
La salida sin comprar una Mac es separar los dos pasos:

1. **Compilar en la nube** (un runner macOS de GitHub Actions) un `.ipa` **sin firmar**.
2. **Firmarlo e instalarlo desde Windows** con [Sideloadly](https://sideloadly.io/), usando
   tu Apple ID gratuito.

| | Apple ID gratis (esta guía) | Apple Developer Program (99 USD/año) |
|---|---|---|
| Duración de la app instalada | 7 días, después hay que reinstalar | 1 año |
| Apps a la vez | pocas (≈3) | sin límite práctico |
| TestFlight / compartir con otros | no | sí |

Para probar balizas en el pasillo, el Apple ID gratuito alcanza.

## 0. Requisitos (una sola vez)

- El código **commiteado y pusheado** a GitHub: el runner compila lo que hay en la rama, no
  tu copia local.
- En Windows: **iTunes descargado de apple.com** (no el de Microsoft Store) para que Windows
  reconozca el iPhone por USB, y **Sideloadly**.
- En el iPhone (iOS 16 o más nuevo): activar **Modo de desarrollador** en
  Ajustes → Privacidad y seguridad → Modo de desarrollador (aparece después del primer intento
  de instalar una app firmada por ti; reinicia el teléfono para activarlo).

## 1. Compilar el `.ipa` en GitHub Actions

1. En GitHub, entra al repo → pestaña **Actions** → workflow **"iOS IPA sin firmar"**.
2. **Run workflow**, elige la rama (p. ej. `testing`) y espera (≈10–20 min).
3. Al terminar, descarga el artifact **`utp-guide-ios`** (un zip con `utp-guide-ios.ipa`).

> Costo: el repo es privado, así que los minutos de macOS cuentan x10 contra la cuota
> gratuita de 2.000 min/mes (≈200 min de macOS). Alcanza para unos 10 builds al mes; si el
> repo fuera público, no consumiría cuota.

El workflow está en `.github/workflows/ios-ipa.yml`. El CI normal (`ci.yml`, analyze + test)
corre en Linux y no gasta minutos de macOS.

## 2. Instalar con Sideloadly

1. Conecta el iPhone por USB, desbloquéalo y toca **Confiar** en esta computadora.
2. Abre Sideloadly, arrastra `utp-guide-ios.ipa`, escribe tu Apple ID y dale **Start**.
   (Conviene usar un Apple ID secundario si no quieres usar el personal.)
3. En el iPhone: Ajustes → General → VPN y gestión de dispositivos → confía en tu Apple ID.
4. Abre la app. La primera vez pedirá **Ubicación** y **Bluetooth**: acepta ambos (en iOS los
   iBeacons se leen con Core Location, ver [positioning-ble.md](positioning-ble.md)).

A los 7 días la app deja de abrir: repite el paso 2 (no hace falta recompilar si no cambió el
código).

## 3. Probar con las balizas

1. Configura cada baliza con la app de Minew: UUID del proyecto, **Major = 4**, Minor 1, 2, 3…
   (ver `docs/setup-beacons.md`). La app ignora las balizas con otro Major.
2. Antes de compilar, deja activo un entorno **que tenga balizas ubicadas**. `piso4_oficial`
   todavía no tiene ninguna, así que el punto azul no va a aparecer ahí. Para el pasillo:

   ```bash
   bash tools/entorno.sh pasillo_exp2_3b_esq
   ```

   Commitea ese cambio (o hazlo en una rama aparte) y lanza el workflow.
3. En la app, la pantalla de **Calibración** muestra el RSSI de cada baliza con el UUID del
   proyecto, aunque no esté registrada en `beacon_config.json`: sirve para confirmar que el
   iPhone las ve antes de mirar el mapa. (La lista de advertisements crudos solo aparece en
   builds debug; el `.ipa` de esta guía es release.)

## Si el build falla

- El repo no trae `ios/Podfile`; Flutter lo genera en el primer build en macOS. Si falla el
  `pod install`, revisa el log del paso "Build (sin firma)".
- El error `Module 'flutter_blue_plus_darwin' not found` que salió en junio en una Mac era de
  pods sin instalar, no del código.

## Alternativas

- **Codemagic** (CI con macOS, plan gratuito con minutos mensuales): sirve igual para compilar,
  pero para firmar e instalar sin Sideloadly pide la cuenta paga de Apple.
- **Una Mac prestada** (o la de un laboratorio): `flutter run` con el iPhone por USB y Signing
  con tu Apple ID en Xcode. Es lo más cómodo para depurar (logs en vivo).
- **Un Android prestado:** `flutter run` funciona directo desde Windows. Además, el camino de
  Android (`flutter_blue_plus`) tiene pendientes que solo se verifican en un teléfono Android
  (ver [roadmap.md](roadmap.md)).
