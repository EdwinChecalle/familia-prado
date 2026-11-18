# Familia Prado — Bloque 03 (v0.3.0) · Entrega incremental

**Base exigida:** repo `C:\gitHub\familia-prado` con Bloques 01 y 02 validados, migración V2 y `spring-boot-starter-flyway` ya agregado. No es una demo HTML ni una APK compilada. **No cargar información médica real hasta completar la validación y el despliegue privado con HTTPS.**

## Lo desarrollado

- **Área «Cuidado de Papá Isidro»**: acceso desde Inicio o barra superior, tres pestañas móviles (Medicamentos, Salud, Documentos) y pestaña Accesos para admin.
- **Permisos explícitos**: administrador ve todos los registros, y habilita/deshabilita el acceso de familiares individualmente. Las APIs comprueban el permiso en cada consulta y escritura; no basta con ocultar botones en Flutter.
- **Indicaciones médicas**: administrador transcribe nombre, texto literal de indicación, profesional, horarios HH:mm y vigencia. No hay sugerencias de dosis ni cambios automáticos.
- **Constancia manual**: familiar autorizado registra «Se administró» o «No se administró» para una fecha/horario indicado. **Sin registro significa desconocido**. No permite registrar dos veces el mismo horario ni registrar en el futuro. Correcciones mediante administrador con motivo guardado en historial.
- **Salud**: glucosa (mg/dL), presión (mmHg), temperatura (°C) y notas, con fecha/hora y registrador, sin diagnósticos ni interpretación numérica.
- **Documentos privados**: carga PDF/JPG/PNG ≤5 MB solo admin, archivo no disponible mediante enlaces públicos, descarga autenticada y apertura en visor externo con advertencia de privacidad.
- **Recordatorios locales opcionales**: Android/iOS puede programar con la app abierta recordatorios futuros de turnos y citas para mostrarlos incluso con la app cerrada. Hay interruptor explícito en «Mis avisos» y permiso del sistema. Los mensajes de sistema **no contienen especialidad médica, medicamentos ni diagnósticos**. El horario es Perú (`America/Lima`).

### Limitación importante de avisos

Los recordatorios locales **solo cubren eventos ya obtenidos y programados previamente**. Si alguien crea una cita o colecta mientras la app está completamente cerrada, la app no puede enterarse y programar un nuevo aviso. **Para notificaciones remotas nuevas con la app cerrada faltan Firebase Cloud Messaging + APNs en iPhone, credenciales y pruebas en dispositivos reales**. No se afirma que esa función esté operativa. La programación local inexacta de Android puede retrasarse por restricciones de batería.

## Instalar sin sobrescribir la base de datos

1. **Haz commit** de los cambios ya validados de Bloque 02. El script se detendrá si hay cambios rastreados sin commit.
2. Descomprime el ZIP a una carpeta cualquiera. Desde PowerShell en esa carpeta:

```powershell
.\aplicar-bloque03.ps1 -ProjectRoot 'C:\gitHub\familia-prado'
```

El script respalda archivos reemplazados **fuera del repositorio** y completa `compileSdk = 37`, desugaring Java 17 y los receptores de notificaciones Android en archivos que ya generó Flutter. Si tu proyecto tiene una versión AGP incompatible con el plugin de notificaciones, revisa los mensajes de compilación y **no actualices Gradle/AGP a ciegas**.

3. Crea manualmente una carpeta **fuera de Git y de las carpetas públicas**, por ejemplo `C:\FamiliaPradoPrivado`. En `C:\gitHub\familia-prado\.env`, agrega:

```dotenv
CARE_DOCUMENT_DIR=C:\FamiliaPradoPrivado
```

La aplicación no guardará documentos si esta variable no está definida. No subas `.env`, capturas de datos clínicos ni archivos médicos a Git. Restringe permisos NTFS de esa carpeta; considera cifrado de disco y respaldo privado. **Los archivos no cuentan aún con cifrado de aplicación ni un modelo de conservación/borrado aprobado**, por eso no usar información real durante estas pruebas.

4. Mantén Docker/PostgreSQL encendidos. Reinicia backend para ejecutar Flyway V3:

```powershell
cd C:\gitHub\familia-prado
.\scripts\run-backend.ps1
```

5. En otra consola:

```powershell
cd C:\gitHub\familia-prado\mobile
flutter pub get
flutter analyze
flutter test
flutter run -d emulator-5556 --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Cambia el emulador por el ID real de `flutter devices`. Para instalar la misma versión en ambos, compila `flutter build apk --debug` e instala con `adb -s <id> install -r .\build\app\outputs\flutter-apk\app-debug.apk`.

**Nota de Android**: `flutter_local_notifications` 23 pide SDK de compilación **37**, desugaring y configuración del Android Gradle Plugin moderno. La primera compilación debe validarse en tu entorno Flutter 3.50; no afirmar que se verificó desde este entorno.

## Plan de validación en dos emuladores, solo datos ficticios

1. Inicia como administrador: Inicio → «Cuidado de Papá Isidro» → pestaña Accesos.
2. Comprueba que Carlos NO puede consultar `/api/care/medications` antes de recibir autorización; debe recibir HTTP 403 también si llama a la API directamente.
3. Otorga acceso a Carlos; comprueba que ahora puede leer el módulo. Olga sigue sin acceso.
4. Admin registra **un medicamento ficticio** con texto claramente marcado «PRUEBA — NO USAR» y horario anterior a la hora actual. Carlos lo visualiza.
5. Carlos registra «Se administró» en la hora de prueba: el historial muestra su nombre. No debe cambiarse el horario ni sugerir dosis.
6. Intenta registrar de nuevo la misma hora: debe devolver HTTP 409, sin duplicar registros.
7. Admin corrige un estado con motivo y el registro queda actualizado. Se guarda auditoría en `care_medication_corrections`.
8. Registra una glucosa ficticia y presión ficticia; comprueba valores, fecha y nombre. Sin interpretar resultados.
9. Admin sube un PDF de prueba ≤5MB desde su teléfono: Carlos autorizado puede abrirlo; Olga debe recibir HTTP 403 aunque conozca el UUID.
10. Retira el acceso a Carlos y verifica que ya no puede consultar registros ni descargar documentos desde la API.
11. En Mis avisos activa notificaciones del sistema y permite el acceso Android; revisa notificaciones programadas `adb` o espera recordatorio de **cita ficticia programada a futuro**. El aviso no debe mostrar datos sensibles.
12. Revisa que **Comidas, Caja, Citas y cuentas** sigan funcionando, que V3 exista y que los datos anteriores sobrevivan a reiniciar Spring Boot y Docker.
13. Compila y valida iPhone por separado con Xcode/macOS; aún no se ejecutó esta prueba.

No uses órdenes médicas reales durante la validación técnica. Los registros no sustituyen recetas ni atención profesional. Una ausencia de registro nunca significa automáticamente que una dosis fue omitida o administrada.

## Contratos API añadidos

- `GET /api/care/access/me` → `{allowed, admin}`
- Admin: `GET /api/care/access`, `PUT /api/care/access/{memberId}` `{allowed: true|false}`
- Autorizados: `GET /api/care/medications`, `GET /api/care/medication-records`, `GET /api/care/observations`, `GET /api/care/documents`
- Admin: `POST /api/care/medications`, `PATCH /api/care/medications/{id}/stop`
- Autorizados: `POST /api/care/medications/{id}/records`, `POST /api/care/observations`
- Admin: `PATCH /api/care/medication-records/{id}/correct` con motivo
- Admin: `POST /api/care/documents` multipart (`title`,`category`,`file`)
- Autorizados: `GET /api/care/documents/{id}/download`

## Comprobaciones realizadas fuera de tu Windows

- `CareRules.java` compiló con Java 21.
- Pruebas adicionales de reglas puras realizadas con harness Java 21 (detalles en salida de verificación del paquete).
- No se ejecutó `mvn test`, `flutter analyze`, `flutter test` ni los plugins nativos en este entorno (sin Maven ni Flutter). **Integración, migración Flyway y notificaciones reales deben verificarse en tu equipo**.

## Trabajo técnico siguiente

- Integrar FCM/APNs para **eventos nuevos** cuando la app está cerrada, con token por dispositivo, revocación al cerrar sesión, permiso opcional y notificaciones sin información clínica.
- Pruebas de autorización HTTP, subida/descarga, reinicio y compilación iOS.
- Cifrado de documentos en reposo o almacenamiento cifrado gestionado; política de conservación, eliminación y respaldo; validación de seguridad antes de producción.
