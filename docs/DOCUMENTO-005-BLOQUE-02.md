# Familia Prado — Bloque 02 (v0.2.0) · Entrega incremental

**Base requerida:** el mismo repositorio `C:\gitHub\familia-prado` que ya tiene Bloque 01 v0.1.1 validado, con migración Flyway funcional, contador de comidas corregido y commit realizado.

Esta entrega es **código fuente incremental**, NO una demo HTML ni una aplicación compilada. Se distribuyen solo los archivos nuevos o modificados para conservar todo lo demás (carpetas Android generadas en Windows, `.env`, volumen PostgreSQL, usuarios, citas y saldos).

## Cambios implementados

1. **Identidad en todas las pantallas:** nombre y cuenta del familiar / Administrador a partir de `/api/profile`, sin adivinar el usuario ni guardar nombres duplicados en Flutter.
2. **Inicio navegable:** tarjetas Comidas, Caja y Citas llevan al módulo correspondiente; Mis avisos abre una bandeja.
3. **Auditoría de gastos:** `GET /api/fund/expenses` incluye `registeredBy` y `reviewedBy`, derivados de claves foráneas `requested_by`/`reviewed_by` que **ya existían en V1**. La identidad de quien lo registra no es necesariamente quien hizo la compra: ese dato no se inventa.
4. **Actualización automática en primer plano:** `/api/events` usa Server-Sent Events (SSE), con autenticación Bearer, *solo publica nombres de módulos cambiados* (sin montos ni datos médicos); la aplicación actualiza pantallas mediante sus endpoints REST existentes. Reconexión y refresco al volver de segundo plano. WebSockets no son necesarios para esta difusión unidireccional.
5. **Calendario continuo:** «Anterior/Siguiente» consulta períodos de 16 semanas sin límite fijo; incluye ciclos pasados y futuros, respeta cambios aprobados.
6. **Avisos personalizados de Papá Isidro:** `/api/alerts` genera avisos según rol y responsabilidades efectivas (semana en curso o siguiente; cita del familiar en las próximas 24 horas y recordatorio cercano de 3 horas; colecta abierta con monto pendiente; revisiones pendientes del Administrador). `/api/alerts/{id}/read` guarda confirmación por usuario en nueva tabla `user_alert_reads`.
7. **Audio opcional y discreto:** Flutter TTS lee mensajes breves, sin diagnósticos ni nombres de medicamentos. Audio **apagado por defecto**, opción de activarlo por cuenta y botón «Escuchar aviso»; no se reproduce un mismo aviso automáticamente más de una vez por cuenta/dispositivo. Se usa la voz del sistema, no se almacenan MP3.

## Limitación importante de las notificaciones

**Las actualizaciones y avisos de este bloque operan con la app abierta (primer plano).** El servidor identifica avisos por fechas y Flutter los consulta al abrir, al recibir eventos o cada 5 minutos mientras está activo. **No llegan notificaciones push con la app cerrada**: eso requerirá habilitar Firebase Cloud Messaging para Android y APNs para iOS, registro de dispositivos, permisos explícitos, plantillas discretas, gestión de zona horaria y pruebas reales. **No declarar ese comportamiento como aprobado todavía.**

## Instalar sin perder historial

1. Confirma que la rama actual de `C:\gitHub\familia-prado` no tenga cambios sin commit (ya confirmaste el commit del Bloque 01).
2. Descomprime este ZIP en cualquier carpeta, por ejemplo `C:\gitHub\instaladores\FamiliaPrado_B02`.
3. Ejecuta PowerShell en esa carpeta:

```powershell
.\aplicar-bloque02.ps1 -ProjectRoot 'C:\gitHub\familia-prado'
```

El instalador **detiene la operación si hay cambios rastreados sin commit**, hace una copia de seguridad de los archivos reemplazados FUERA del repositorio y **no toca `.env`, `compose.yaml`, datos de Docker o carpeta `android` generada**. También puede añadir los metadatos de descubrimiento de voz en AndroidManifest principal si el archivo existe. El script no ejecuta `git commit` automáticamente.

4. En una terminal, reinicia Spring Boot para que Flyway aplique `V2__alert_reads.sql`:

```powershell
cd C:\gitHub\familia-prado
.\scripts\run-backend.ps1
```

No uses `docker compose down -v`. Flyway agrega **solo** la tabla de lecturas y mantiene intactas las tablas y registros anteriores.

5. En otra terminal, actualiza Flutter:

```powershell
cd C:\gitHub\familia-prado\mobile
flutter pub get
flutter analyze
flutter test
flutter run -d emulator-5556 --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Si cambió el identificador, consulta `flutter devices`. El emulador accede a Windows vía `10.0.2.2`. Para evitar versiones mezcladas entre tus dos emuladores:

```powershell
flutter build apk --debug
adb -s emulator-5554 install -r .\build\app\outputs\flutter-apk\app-debug.apk
adb -s emulator-5556 install -r .\build\app\outputs\flutter-apk\app-debug.apk
```

Usa solo los identificadores que muestre `adb devices`.

6. Ejecuta pruebas de API sin alterar datos:

```powershell
cd C:\gitHub\familia-prado
.\scripts\validar-bloque02.ps1
```

## Pruebas manuales obligatorias

- Accede como Carlos: encabezado «Cuenta: Carlos» y «Hola, Carlos». Repite con Olga y Administrador.
- Desde Inicio, toca las tarjetas de Comidas/Caja/Citas: se abre el módulo esperado.
- Con Carlos registra un gasto de prueba: como administrador comprueba «Registrado por: Carlos» en la lista de gastos. Comprueba que los estados y saldos siguen siendo correctos; después usa una operación de prueba identificable.
- Abre Comidas en ambos emuladores: marca una comida en uno y confirma que **el segundo se actualiza automáticamente sin refrescar**, con el servidor abierto y conexión activa.
- Crea una cita de prueba y observa el segundo dispositivo: la lista cambia automáticamente. Repite con Caja.
- Pulsa «Siguiente» en Comidas: consulta ciclos más allá de las semanas 16 y 32; «Anterior» permite revisar anteriores.
- Entra en «Mis avisos»: el familiar responsable ve su próximo turno y, si existen, una cita dentro de 24 horas y una colecta pendiente. Las notificaciones deben ser visibles solo para la cuenta autorizada.
- Pulsa «Escuchar aviso»: verifica audio en español. El interruptor automático debe empezar **apagado** para cada cuenta.
- Con la app cerrada no esperes avisos push todavía.
- Repite validación de persistencia del Bloque 01 tras iniciar Flyway V2.

## Contratos y privacidad

- `GET /api/profile` → `displayName`, `role`, `isAdmin`.
- `GET /api/fund/expenses` → campos existentes y `registeredBy`, `reviewedBy`.
- `GET /api/events` → SSE con eventos `changed` y `data: turns|fund|appointments|family`; requiere token y solo transporta el nombre del módulo.
- `GET /api/alerts` → avisos calculados para usuario autenticado; `POST /api/alerts/{id}/read` → marca leído solo el aviso disponible para ese usuario.
- TTS y lecturas de avisos en la app no se deben interpretar como instrucciones médicas. Los textos de voz evitan diagnósticos y detalles clínicos.
- En producción el acceso debe realizarse bajo HTTPS. No publiques la API de desarrollo en internet.

## Verificación de compilación

Se verificaron **estructuras y reglas de código fuente** y se compiló `AlertWords.java` usando Java 21 en este entorno. Aquí no están instalados Flutter, Maven o Docker, por lo que **NO se afirma** que haya compilado el proyecto Android completo ni que haya pasado la integración Spring/PostgreSQL. Ejecuta `flutter analyze`, `flutter test` y `mvn test` en tu computadora antes del commit final.

## iPhone

El mismo Dart está preparado para Flutter iOS, pero aún no se generó ni compiló un proyecto Xcode; eso requiere macOS, Xcode y `flutter create --platforms=ios .` desde `mobile` si todavía falta la carpeta `ios/`. El comportamiento del TTS, permisos y conexión en iPhone requiere validación específica.
