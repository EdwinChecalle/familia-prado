package pe.familiaprado.app;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

@Service
public class PushQueue {
    private final JdbcTemplate db;
    private final ApplicationEventPublisher events;
    public PushQueue(JdbcTemplate db,ApplicationEventPublisher events) { this.db=db;this.events=events; }
    public record Created(UUID eventId) {}

    public void enqueue(UUID user,String type,UUID event,String trigger,
                        Instant due,Instant expiry) {
        if (user == null || due == null || expiry == null || !expiry.isAfter(due)) return;
        db.update("""
            INSERT INTO push_outbox(id,recipient_user_id,event_type,event_id,
                trigger_key,due_at,expire_at)
            VALUES(?,?,?,?,?,?,?) ON CONFLICT DO NOTHING
            """,UUID.randomUUID(),user,type,event,trigger,
            java.sql.Timestamp.from(due),java.sql.Timestamp.from(expiry));
    }

    public void appointmentCreated(UUID appointmentId,UUID member,Instant at) {
        Instant now=Instant.now();
        // El aviso general no incluye datos médicos o el nombre del responsable.
        // La persona asignada conserva el aviso por voz y los recordatorios existentes.
        record Recipient(UUID user,UUID member) {}
        var recipients=db.query("""
            SELECT u.id,u.member_id FROM app_users u
            JOIN family_members m ON m.id=u.member_id WHERE m.active=true
            """,(rs,i)->new Recipient(rs.getObject(1,UUID.class),rs.getObject(2,UUID.class)));
        var times=PushScheduleRules.forNewAppointment(at,now);
        for (var recipient:recipients) {
            if (member!=null && member.equals(recipient.member()) && !times.isEmpty()) {
                for (var when:times) enqueue(recipient.user(),"APPOINTMENT",appointmentId,when.key(),
                    when.at(),when.expiresAt());
            } else {
                enqueue(recipient.user(),"APPOINTMENT_INFO",appointmentId,"NEW",now,now.plus(12,ChronoUnit.HOURS));
            }
        }
        events.publishEvent(new Created(appointmentId));
    }

    public void cancelAppointmentPending(UUID id) {
        db.update("""
            UPDATE push_outbox SET status='CANCELLED'
            WHERE event_type IN ('APPOINTMENT','APPOINTMENT_INFO') AND event_id=? AND status IN ('PENDING','SENDING')
            """,id);
    }
    public void appointmentEdited(UUID id,UUID member,Instant at,int revision) {
        cancelAppointmentPending(id);
        Instant now=Instant.now();
        record Recipient(UUID user,UUID member) {}
        var recipients=db.query("""
            SELECT u.id,u.member_id FROM app_users u
            JOIN family_members m ON m.id=u.member_id WHERE m.active=true
            """,(rs,i)->new Recipient(rs.getObject(1,UUID.class),rs.getObject(2,UUID.class)));
        var schedule=PushScheduleRules.forNewAppointment(at,now);
        for(var recipient:recipients){
            if(member!=null && member.equals(recipient.member()) && !schedule.isEmpty()){
                for(var when:schedule) enqueue(recipient.user(),"APPOINTMENT",id,when.key()+":"+revision,when.at(),when.expiresAt());
            } else enqueue(recipient.user(),"APPOINTMENT_INFO",id,"NEW:"+revision,now,now.plus(12,ChronoUnit.HOURS));
        }
        events.publishEvent(new Created(id));
    }
    public void appointmentStatusChanged(UUID id,UUID member,String status) {
        if ("COMPLETED".equals(status) || "CANCELLED".equals(status)) cancelAppointmentPending(id);
        if ("CANCELLED".equals(status)) {
            var users=db.query("SELECT u.id FROM app_users u JOIN family_members m ON m.id=u.member_id WHERE m.active=true",
                (rs,i)->rs.getObject(1,UUID.class));
            Instant now=Instant.now();
            for(var user:users) enqueue(user,"CANCELLED",id,"NOW",now,now.plus(12,ChronoUnit.HOURS));
            events.publishEvent(new Created(id));
        }
    }
    public void collectionCreated(UUID collectionId) {
        var users=db.query("SELECT u.id FROM app_users u JOIN family_members m ON m.id=u.member_id WHERE m.active=true",
            (rs,i)->rs.getObject(1,UUID.class));
        Instant now=Instant.now();
        for(var user:users) enqueue(user,"COLLECTION",collectionId,"NEW",
            now,now.plus(12,ChronoUnit.HOURS));
        events.publishEvent(new Created(collectionId));
    }
}
