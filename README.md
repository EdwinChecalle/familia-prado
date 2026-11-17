# Familia Prado — aplicación móvil y API (Bloque 01)

**Proyecto fuente real**: Flutter (Android+iPhone), Spring Boot (API REST) y PostgreSQL (persistencia compartida). No contiene HTML ni datos simulados en memoria como fuente de verdad.

**Estado**: primera implementación de código, sin APK ni IPA precompilados. Los SDK Flutter y Maven no estaban instalados en el entorno de generación; **no se pudo verificar una compilación completa ni la integración con PostgreSQL**. Sí se ejecutaron 165 comprobaciones de dominio Java puro. Las pruebas de integración, emulador y dispositivo son necesarias antes de uso familiar.

## Requisitos

- Windows 11: Java 21, Maven 3.9+, Docker Desktop, Flutter SDK 3.50+, Android Studio con SDK/emulador.
- iOS: Mac con Xcode, CocoaPods y Flutter; **Windows no puede producir ni firmar una aplicación iOS**. Un familiar con iPhone puede usar la aplicación una vez compilada/distribuida apropiadamente desde macOS.
- La aplicación y el servidor necesitan estar conectados a internet o a la misma red de pruebas. El servidor en el PC no estará disponible fuera de casa sin despliegue, HTTPS y configuración de red.

## Ejecutar backend y PostgreSQL en Windows

1. Abre una terminal PowerShell en la carpeta raíz.
2. `Copy-Item .env.example .env`; edita `.env` y **reemplaza todas las contraseñas de ejemplo**. No subas `.env` a Git.
3. `docker compose up -d` para iniciar PostgreSQL, usando puerto local `5433`.
4. `./scripts/run-backend.ps1` para iniciar Spring Boot en `http://localhost:8080`.
5. Verifica la API: `Invoke-RestMethod http://localhost:8080/api/ping` devuelve `status: ok`.
6. Corre pruebas: `mvn -f backend/pom.xml test`.

El primer inicio crea una única cuenta ADMIN usando las variables de `.env` y los ocho nombres de referencia. **No crea cuentas de los hijos automáticamente**: el administrador debe asignar una cuenta y credenciales distintas a cada familiar desde la sección Familia de Flutter, y comunicar dichas credenciales en privado.

## Ejecutar Flutter Android

1. Comprueba `flutter doctor`; acepta las licencias de Android según las indicaciones del SDK.
2. Inicia un emulador Android desde Android Studio y mantén el backend encendido.
3. Ejecuta `./scripts/run-mobile-android.ps1` desde la raíz (o manualmente desde `mobile/`):
   ```powershell
   flutter create --project-name familia_prado --platforms=android .
   flutter pub get
   flutter test
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
   ```
4. Ingresa con el correo y contraseña de administrador definidos en `.env`.
5. En **Semanas de comida**, revisa y confirma el orden real de los ocho hijos. Hasta entonces las semanas son provisionales y no permiten marcar comidas.

Para probar un Android físico conectado a la misma red, sustituye `10.0.2.2` por la IP LAN de la computadora. Habilita acceso al puerto 8080 en el firewall solo dentro de esa red de pruebas. **Nunca envíes información médica ni financiera real a un backend HTTP en la red**.

## Preparación para iOS (en macOS)

Desde `mobile/`:
```bash
flutter create --project-name familia_prado --platforms=ios .
flutter pub get
flutter test
```
Para una conexión local con el servidor en la red, ejecuta `python3 ../scripts/prepare-ios-local-network.py` y `flutter run --dart-define=API_BASE_URL=http://IP_DEL_SERVIDOR:8080`. La excepción permite conexiones a red local solo en desarrollo. Antes de distribuir, utiliza HTTPS, revisa ATS y configura firma/distribución con Xcode/TestFlight.

## Qué funciona en el código de este bloque

1. Cuenta administrador inicial, creación de cuentas individuales, inicio y cierre de sesión, cambio de contraseña, tokens opacos almacenados como hash SHA-256 en PostgreSQL y BCrypt para contraseñas.
2. Ocho familiares, rotación automática de ocho semanas, confirmación inicial, registro de las tres comidas por cada día y cambios de semana sujetos a aceptación.
3. Caja: colectas por familiar, pagos parciales por Yape/Plin/transferencia/efectivo, verificación administrativa, gastos solicitados, aprobación o rechazo y saldo calculado solamente con movimientos verificados/aprobados.
4. Citas: alta por administrador, responsable, hospital, especialidad, preparación y estados de asistencia. Horas de citas interpretadas siempre según horario de Perú.
5. Flutter: Inicio, Comidas, Caja, Citas, Familia con datos cargados desde la API, sesión protegida en almacenamiento seguro y mensajes en lenguaje claro.

## Pendiente antes de uso real

- Compilar y pasar pruebas completas (Maven, Flutter, PostgreSQL, Android e iOS).
- Añadir rate limiting de inicio de sesión, recuperación segura de contraseñas y auditoría completa por evento.
- Incorporar adjuntos verificables de boletas/recetas y control detallado de acceso a datos de salud.
- Añadir controles de idempotencia para evitar duplicar envíos cuando la conexión falle.
- Añadir notificaciones push, copias de seguridad cifradas y recuperación de desastres.
- Despliegue del servidor con HTTPS, firewall, backups y políticas de privacidad.
- Confirmar las reglas definitivas de la caja, compensaciones y la secuencia real de turnos.

**Prohibido usar el bloque como herramienta de atención médica o contabilidad real antes de estas validaciones.**

## Estructura

```text
backend/                Spring Boot + Flyway SQL + API
mobile/lib/              Flutter, API client y pantallas
mobile/test/             Pruebas Dart de fechas
mobile/android/app/src/debug/AndroidManifest.xml  HTTP local solo en Android debug
compose.yaml             PostgreSQL local
scripts/                 Comandos de desarrollo
 docs/                   Contrato de endpoints y decisiones
```
