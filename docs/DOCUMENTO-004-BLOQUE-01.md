# DOCUMENTO 004 — Familia Prado / Bloque 01

**Fecha:** 16/11/2026 (Perú)  
**Decisión técnica:** Flutter Android/iOS + Spring Boot 4.1.2 + PostgreSQL 17.  
**Prioridad:** funcionalidad, simplicidad de uso y validación, no pulido estético.  
**Alcance:** primer corte vertical completo de código, pendiente de compilar en el entorno del desarrollador.

## Reglas modeladas

- Los ocho familiares están definidos provisionalmente: Ángel, Carlos, Jorge, Olga, Enrique, Isabel, Carmen y Lucho. La secuencia real **no está confirmada**; ningún registro de comida se acepta hasta que un administrador configure el orden y lunes de referencia.
- Un turno empieza el lunes y termina el domingo. La rotación se repite cada 8 semanas, con 21 comidas por semana.
- Una solicitud de intercambio debe afectar dos semanas futuras y ser aceptada por la otra parte. Un intercambio aceptado se registra como dos excepciones de la rotación sin alterar la secuencia base.
- La caja no suma aportes enviados sin revisión. Los gastos aprobados no pueden superar el saldo verificado, bajo un bloqueo transaccional.
- Las citas médicas se asignan independientemente de los turnos de cocina. La hora de las citas se entiende según hora de Lima, Perú.
- Las cuentas son individuales. Cada persona solo puede registrar sus comidas o aportes; administración puede registrar en nombre de terceros y revisar los movimientos.

## Endpoints del bloque

| Método | Ruta | Función |
|---|---|---|
| POST | `/api/auth/login` | Obtener sesión |
| GET | `/api/auth/me` | Usuario actual |
| POST | `/api/auth/logout` | Revocar sesión |
| POST | `/api/auth/change-password` | Cambiar contraseña y cerrar sesiones |
| POST | `/api/admin/accounts` | Administrador crea cuenta de un familiar |
| GET | `/api/members` | Lista de hijos |
| GET | `/api/rotation` | Estado de confirmación de turnos |
| PUT | `/api/admin/rotation` | Confirmar lunes y orden |
| GET | `/api/turns?from=AAAA-MM-DD&weeks=8` | Rotación semanal |
| GET | `/api/turns/{monday}/meals` | Comidas marcadas |
| PUT | `/api/turns/{monday}/meals` | Registrar una comida |
| GET | `/api/swaps` | Solicitudes de intercambio |
| POST | `/api/swaps` | Pedir intercambio |
| POST | `/api/swaps/{id}/decision` | Aceptar/rechazar |
| GET | `/api/fund/summary` | Saldo disponible |
| GET/POST | `/api/fund/collections` | Consultar/crear colecta |
| GET/POST | `/api/fund/collections/{id}/contributions` | Consultar/registrar aportes |
| POST | `/api/fund/contributions/{id}/review` | Revisar aporte |
| GET/POST | `/api/fund/expenses` | Consultar/solicitar gasto |
| POST | `/api/fund/expenses/{id}/review` | Aprobar/rechazar gasto |
| GET/POST | `/api/appointments` | Consultar/crear citas |
| PATCH | `/api/appointments/{id}/status` | Confirmar, completar o cancelar |

## Ejemplos de payloads

Confirmar calendario una vez que el orden real haya sido comprobado:
```json
{"anchorMonday":"2026-11-16","memberIdsInOrder":["UUID-1","UUID-2","UUID-3","UUID-4","UUID-5","UUID-6","UUID-7","UUID-8"],"memberStarting":"UUID-1"}
```

Registrar comida del lunes:
```json
{"date":"2026-11-16","meal":"BREAKFAST","completed":true}
```

Registrar aporte de S/40 a una colecta de S/100:
```json
{"memberId":"UUID-DEL-FAMILIAR","amount":40.00,"paymentMethod":"YAPE","paymentReference":"Número opcional del pago"}
```

Cita médica (hora UTC, que corresponde a las 09:00 del 20/11 en Perú):
```json
{"appointmentAt":"2026-11-20T14:00:00Z","hospital":"Hospital Vitarte","specialty":"Nefrología","responsibleMemberId":"UUID-DEL-FAMILIAR","preparation":"Confirmar requisitos indicados por el médico"}
```

## Seguridad y límites

- Acceso privado mediante sesiones opacas, sin enviar contraseñas en URLs.
- Los formularios médicos disponibles aquí **no registran tratamientos ni dosis**; ese módulo requiere una definición de permisos y validación médica específica.
- Las boletas solo tienen referencia de texto; la carga de archivos está pendiente.
- Sin chat interno, push, auditoría por eventos ni monitoreo de producción en este bloque.
- Los registros se guardan en PostgreSQL; Flutter no es la fuente de verdad.
- No utilizar el servidor HTTP para comunicación por internet o datos reales: desplegar TLS y controles de seguridad primero.

## Criterios de aceptación para el equipo

1. `docker compose up -d` y `mvn test` ejecutan sin fallos.
2. Un administrador puede iniciar sesión, crear cuentas y confirmar el calendario después de acordar el orden real.
3. Un hijo solo marca las comidas correspondientes a su semana.
4. Dos hijos pueden solicitar/aceptar un intercambio futuro; no se permite realizarlo después de empezar una semana.
5. Una colecta de S/100 acepta dos aportes de S/40 y S/60; bloquea un tercero.
6. Aportaciones no verificadas no cambian el saldo disponible.
7. Un gasto superior al saldo no puede aprobarse.
8. Una cita asignada aparece con la misma hora peruana en Android e iPhone, incluso con dispositivo configurado en España.
9. Todo cambio realizado desde una cuenta puede leerse desde otra al actualizar.
10. Compilar Android APK, iOS en macOS, probar en dispositivo físico y revisar accesibilidad antes del piloto.
