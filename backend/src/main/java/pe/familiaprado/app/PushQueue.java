package pe.familiaprado.app;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class PushQueue {
    private final JdbcTemplate db;
    public PushQueue(JdbcTemplate db) { this.db=db; }

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
        if (member==null) return;
        var users=db.query("SELECT id FROM app_users WHERE member_id=?",
            (rs,i)->rs.getObject(1,UUID.class),member);
        var times=PushScheduleRules.forNewAppointment(at,Instant.now());
        for (var user:users) {
            for (var when:times) {
                enqueue(user,"APPOINTMENT",appointmentId,when.key(),
                    when.at(),when.expiresAt());
            }
        }
    }

    public void appointmentStatusChanged(UUID id,UUID member,String status) {
        if ("COMPLETED".equals(status) || "CANCELLED".equals(status)) {
            db.update("""
                UPDATE push_outbox SET status='CANCELLED'
                WHERE event_type='APPOINTMENT' AND event_id=? AND status='PENDING'
                """,id);
        }
        if ("CANCELLED".equals(status) && member!=null) {
            var users=db.query("SELECT id FROM app_users WHERE member_id=?",
                (rs,i)->rs.getObject(1,UUID.class),member);
            Instant now=Instant.now();
            for(var user:users) enqueue(user,"CANCELLED",id,"NOW",
                now,now.plus(12,ChronoUnit.HOURS));
        }
    }

    public void collectionCreated(UUID collectionId) {
        var users=db.query("SELECT id FROM app_users WHERE member_id IS NOT NULL",
            (rs,i)->rs.getObject(1,UUID.class));
        Instant now=Instant.now();
        for(var user:users) enqueue(user,"COLLECTION",collectionId,"NEW",
            now,now.plus(12,ChronoUnit.HOURS));
    }
}
