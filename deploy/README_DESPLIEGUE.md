# Familia Prado v0.3.6 — Despliegue de coste cero (sujeto a cuotas)

## Alcance y limitaciones

Esta guía **prepara** el despliegue; **no** significa que exista ya un servidor público.
La ruta recomendada para el piloto es **Oracle Cloud Always Free (VM Linux ARM64) + Neon Free PostgreSQL + FCM**. Para una demostración no dependiente de recordatorios, se incluye un blueprint **Render Free**. Render duerme después de 15 minutos de inactividad; ni ese entorno ni Oracle Always Free ofrecen garantía de entrega a tiempo de avisos médicos.

**No habilitar documentos médicos** inicialmente (`CARE_DOCUMENTS_ENABLED=false`). Los datos de pruebas locales no deben transferirse automáticamente al piloto. Hasta completar las pruebas de seguridad, respaldos y restauración, usar información ficticia. El balance de Caja no sustituye una conciliación contable formal.

## 1. Preparación antes de nube

1. Haz un commit revisado (excluye `.env`, archivos Firebase Admin, tokens, APK con claves y archivos médicos).
2. Ejecuta `flutter analyze`, `flutter test`, y las pruebas Maven en `backend`.
3. Compila y prueba dos dispositivos Android con los 3 reportes PNG y calendario mensual.
4. Guarda un respaldo cifrado de la BD local. No uses la BD local ni sus contraseñas en staging.

## 2. Neon Free: base separada de la local

1. Crear un proyecto `familia-prado-staging` en Neon (plan Free, sujeto a límite de almacenamiento y cómputo).
2. Usar credenciales nuevas. Obtener el host, base, nombre de usuario y contraseña de Neon, **no compartirlos por chat**.
3. Configurar `DB_URL=jdbc:postgresql://HOST/BASE?sslmode=verify-full` (prueba conexión TLS de tu Java y ajusta certificados si es necesario), `DB_USER`, `DB_PASSWORD`.
4. Flyway ejecutará V1–V5 en una **base vacía**. Confirmar en `flyway_schema_history` y `/actuator/health`.
5. Mantén conexiones reducidas (perfil staging `hikari.maximum-pool-size=3`) y verifica los límites de Neon.

## 3. Oracle Cloud Always Free

1. Crear una instancia Linux Ubuntu con recursos Always Free **si hay capacidad disponible**. Elegir región compatible y confirmar cuotas, requisitos de cuenta y condiciones.
2. Endurecer SSH (llaves, nunca contraseñas), actualizar SO, configurar firewall de OCI y UFW: publicar solo 80/443 y SSH restringido a tu IP. No exponer 8080 ni PostgreSQL.
3. Instalar Docker Engine y el plugin Compose. Enviar por SSH el código de `backend/` y `deploy/oracle/`, sin datos locales, secretos ni `target/`.
4. Crear `deploy/oracle/.env` desde `.env.example`, con URL JDBC de Neon y credenciales reales.
5. Crear `deploy/oracle/secrets/firebase-admin.json` (permisos restrictivos `chmod 600`) usando la **cuenta de servicio de Firebase** y únicamente en el servidor. Nunca incluirla en el repositorio ni en el APK.
6. Conseguir un nombre DNS cuya resolución apunte a la IP pública de la VM y sustituir `PRADO_DOMAIN` en `.env` (se puede usar subdominio propio o un proveedor DNS gratuito, sujeto a sus reglas). Caddy obtiene certificados TLS cuando el DNS y los puertos están configurados.
7. En `deploy/oracle/`: `docker compose up -d --build` y `docker compose logs -f api`. Probar `https://TU_DOMINIO/actuator/health`.
8. Confirmar FCM desde un Android real. FCM puede seguir enviando si el servidor está disponible, pero no garantiza latencia o disponibilidad 24/7.

**Atención:** Oracle puede recuperar instancias ociosas; el registro de Always Free puede requerir tarjeta de verificación y puede no haber capacidad. No actives recursos de pago ni hagas upgrade automático. Supervisa límites y alertas.

## 4. Render Free (solo demostraciones)

Utiliza `deploy/render/render.yaml` como guía. El backend Free puede dormir tras 15 minutos sin tráfico, tardar en despertar y perder el disco local en cada reinicio. **No utilices Render Free para recordar citas sin alternativas humanas**. La BD Neon va separada. Evita almacenar PDF privados en ese disco temporal.

## 5. APK Android piloto

Configura FlutterFire para la variante Android: verifica el identificador de aplicación y archivo `firebase_options.dart` generado. **Importante:** el servicio Firebase Android solo reconoce el `applicationId` registrado; una variante con otro identificador requiere nueva app Firebase.

En Windows, una vez confirmado el HTTPS público:

```powershell
cd C:\gitHub\familia-prado\mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://TU_DOMINIO
```

Firma la APK con tu propia configuración **release** de Android; nunca distribuyas una APK debug como producto final. La instalación privada de APK implica habilitar instalaciones desde esa fuente y explicar a los familiares cómo instalar actualizaciones. iPhone requiere macOS/Xcode y estrategia de distribución separada.

## 6. Respaldos y recuperación

Neon Free tiene ventana corta de recuperación (sujeta a cambios y cuotas). La restauración de un servicio remoto no reemplaza un respaldo propio. Hacer exportaciones `pg_dump` cifradas a almacenamiento privado **fuera de la VM** y ensayar `pg_restore` contra una base de prueba. No dejar respaldos sin cifrar en un directorio público ni en GitHub.

Antes de registrar aportes reales, probar: crear movimientos ficticios → respaldo → restauración aislada → conciliar balances → comprobar permisos → borrar el entorno de prueba. Antes de usar datos clínicos reales, exigir auditoría de permisos y almacenamiento duradero.

## 7. Criterios para anunciar el piloto familiar

- Dos móviles físicos alcanzan HTTPS y reciben FCM con la app cerrada.
- Reportes PNG: Caja reconcilia, Citas oculta datos clínicos, Comidas respeta intercambios.
- En nueva colecta no se registra como dinero disponible un aporte pendiente.
- El plan de recuperación de cuentas, respaldos y restauración está probado.
- Los servicios no han generado cargos y se conocen las limitaciones de los niveles gratuitos.
- Se comunica a la familia que el piloto es gratuito **sin garantía de disponibilidad** y los recordatorios no sustituyen una llamada cuando una cita es importante.

Fuentes: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm ; https://neon.com/blog/neon-free-plan-1-gb-per-project ; https://firebase.google.com/pricing ; https://render.com/docs/free
