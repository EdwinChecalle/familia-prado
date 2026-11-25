package pe.familiaprado.app;

import jakarta.annotation.PreDestroy;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.transaction.event.TransactionPhase;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

@Service
public class PushDispatcher {
    private static final Logger log=LoggerFactory.getLogger(PushDispatcher.class);
    private final JdbcTemplate db;
    private final PushTransport transport;
    // Un hilo, cola acotada: no bloquear la petición HTTP ni consumir memoria sin límite.
    // Si se llena la cola, el proceso periódico conserva y recupera los trabajos en PostgreSQL.
    private final ThreadPoolExecutor immediate=new ThreadPoolExecutor(1,1,0L,TimeUnit.MILLISECONDS,
        new ArrayBlockingQueue<>(32),new ThreadPoolExecutor.DiscardPolicy());
    public PushDispatcher(JdbcTemplate db,PushTransport transport) {
        this.db=db;this.transport=transport;
    }
    private record Job(UUID id,UUID userId,String type,UUID eventId,String trigger) {}
    private record Device(String token,String platform,boolean spoken) {}

    @TransactionalEventListener(phase=TransactionPhase.AFTER_COMMIT,fallbackExecution=true)
    public void onCreated(PushQueue.Created event) {
        if (!transport.isEnabled()) return;
        immediate.execute(()->{
            try {
                var ids=db.query("""
                    SELECT id FROM push_outbox WHERE event_id=? AND (trigger_key='NEW' OR trigger_key LIKE 'NEW:%' OR trigger_key='NOW')
                    AND status='PENDING' AND available_at<=NOW() AND due_at<=NOW() AND expire_at>NOW()
                    ORDER BY created_at,id
                    """,(r,i)->r.getObject(1,UUID.class),event.eventId());
                for (var id:ids) {
                    try { deliverOne(id); }
                    catch(Exception ex) { log.warn("Falló entrega inmediata de id {}",id); }
                }
            } catch(Exception ex) { log.warn("Envío inmediato pendiente; se reintentará por la cola periódica"); }
        });
    }
    @PreDestroy public void stopImmediate() { immediate.shutdownNow(); }

    @Scheduled(fixedDelayString="${PRADO_PUSH_SCAN_MS:30000}")
    public void deliverDue() {
        if (!transport.isEnabled()) return;
        db.update("UPDATE push_outbox SET status='EXPIRED' WHERE status='PENDING' AND expire_at<=NOW()");
        // Recuperar envíos abandonados tras reiniciar el proceso.
        db.update("UPDATE push_outbox SET status='PENDING' WHERE status='SENDING' " +
            "AND available_at<NOW()-INTERVAL '5 minutes'");
        var ids=db.query("""
            SELECT id FROM push_outbox WHERE status='PENDING'
                AND available_at<=NOW() AND due_at<=NOW() AND expire_at>NOW()
            ORDER BY due_at LIMIT 30
            """,(r,i)->r.getObject(1,UUID.class));
        for(var id:ids) {
            try { deliverOne(id); }
            catch(Exception e) { log.warn("Falló entrega push de id {}",id,e); }
        }
    }
    private void deliverOne(UUID id) throws Exception {
        // UPDATE condicional: otro proceso no puede tomar el mismo trabajo.
        int taken=db.update("""
            UPDATE push_outbox SET status='SENDING', attempts=attempts+1,
                available_at=NOW()
            WHERE id=? AND status='PENDING' AND available_at<=NOW() AND due_at<=NOW() AND expire_at>NOW()
            """,id);
        if(taken!=1)return;
        Job job=db.queryForObject("""
            SELECT id,recipient_user_id,event_type,event_id,trigger_key
            FROM push_outbox WHERE id=?
            """,(r,i)->new Job(r.getObject(1,UUID.class),r.getObject(2,UUID.class),
                r.getString(3),r.getObject(4,UUID.class),r.getString(5)),id);
        if(job==null)return;
        // No enviar recordatorios de citas finalizadas/canceladas.
        if("APPOINTMENT".equals(job.type())) {
            Integer valid=db.queryForObject("""
                SELECT COUNT(*) FROM appointments
                WHERE id=? AND deleted_at IS NULL AND status IN ('PLANNED','CONFIRMED')
                  AND appointment_at>NOW()
                """,Integer.class,job.eventId());
            if(valid==null||valid==0) {
                db.update("UPDATE push_outbox SET status='CANCELLED' WHERE id=?",id);
                return;
            }
        }
        if ("APPOINTMENT_INFO".equals(job.type())) {
            Integer valid=db.queryForObject("SELECT COUNT(*) FROM appointments WHERE id=? AND deleted_at IS NULL AND status <> 'CANCELLED'",
                Integer.class,job.eventId());
            if (valid==null || valid==0) {
                db.update("UPDATE push_outbox SET status='CANCELLED' WHERE id=?",id);
                return;
            }
        }
        var devices=db.query("""
            SELECT token,platform,spoken_sound FROM push_devices WHERE user_id=?
            """,(r,i)->new Device(r.getString(1),r.getString(2),r.getBoolean(3)),job.userId());
        if(devices.isEmpty()) { retry(id,"Sin dispositivos registrados"); return; }
        String title=switch(job.type()) {
            case "APPOINTMENT" -> job.trigger().equals("NEW") ? "Nueva cita familiar" : job.trigger().startsWith("NEW:") ? "Cita familiar actualizada" : "Recordatorio de cita";
            case "APPOINTMENT_INFO" -> job.trigger().startsWith("NEW:") ? "Cita familiar actualizada" : "Nueva cita familiar";
            case "CANCELLED" -> "Cita familiar cancelada";
            case "COLLECTION" -> "Nueva colecta familiar";
            default -> "Aviso de Familia Prado";
        };
        String body=switch(job.type()) {
            case "APPOINTMENT" -> "Revisa tu responsabilidad para acompañar a Papá Isidro.";
            case "APPOINTMENT_INFO" -> "Revisa Citas para conocer los detalles actualizados.";
            case "CANCELLED" -> "Una cita familiar fue cancelada. Revisa Citas.";
            case "COLLECTION" -> "Hay una nueva colecta. Revisa Caja para ver tu aporte.";
            default -> "Tienes una novedad familiar.";
        };
        String route=switch(job.type()) {
            case "APPOINTMENT","APPOINTMENT_INFO","CANCELLED" -> "citas";
            case "COLLECTION" -> "caja";
            default -> "avisos";
        };
        int sent=0;
        for(var d:devices) {
            try {
                if (!Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM push_outbox WHERE id=? AND status='SENDING')",Boolean.class,id))) return;
                transport.send(d.token(),d.platform(),d.spoken(),job.type(),
                    title,body,job.eventId().toString(),route);
                sent++;
            } catch(Exception e) {
                // Nunca registrar tokens de dispositivo o datos clínicos en logs.
                log.warn("Error de envío FCM para job {} / plataforma {}",job.id(),d.platform());
            }
        }
        if(sent>0) db.update("UPDATE push_outbox SET status='SENT',sent_at=NOW(),last_error=NULL WHERE id=? AND status='SENDING'",id);
        else retry(id,"No se pudo entregar a los dispositivos registrados");
    }
    private void retry(UUID id,String reason) {
        db.update("""
            UPDATE push_outbox SET status=CASE WHEN attempts>=5 THEN 'EXPIRED'
              ELSE 'PENDING' END, last_error=?,
              available_at=NOW()+(LEAST(attempts,5)*INTERVAL '2 minutes')
            WHERE id=? AND status='SENDING'
            """,reason,id);
    }
}
