package pe.familiaprado.app;

import java.util.*;
import java.time.Instant;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/** Called inside a transaction. All writes serialize on the single rotation state row. */
public final class AppointmentRotation {
    private final JdbcTemplate db;
    AppointmentRotation(JdbcTemplate db){this.db=db;}
    record State(int position,long revision) {}
    public record Event(String kind,UUID appointmentId,UUID suggestedMemberId,UUID actualMemberId,
                 boolean advanced,String reason,Instant occurredAt) {}
    public record View(List<AppointmentRotationRules.Member> order,UUID nextMemberId,UUID regularNextMemberId,long revision,List<Event> history) {}
    State state(boolean lock){return db.queryForObject(
        "SELECT next_position,revision FROM appointment_rotation_state WHERE id=1"+(lock?" FOR UPDATE":""),
        (r,n)->new State(r.getInt(1),r.getLong(2)));}
    List<AppointmentRotationRules.Member> order(){return db.query("""
        SELECT m.id,m.display_name,o.position,m.active FROM appointment_rotation_order o
        JOIN family_members m ON m.id=o.member_id ORDER BY o.position
        """,(r,n)->new AppointmentRotationRules.Member(r.getObject(1,UUID.class),r.getString(2),r.getInt(3),r.getBoolean(4)));}
    View view(){
        State s=state(true); var order=order(); var next=selection(s,order).member();
        var history=db.query("""
            SELECT kind,appointment_id,suggested_member_id,actual_member_id,advanced,reason,occurred_at
            FROM appointment_rotation_events ORDER BY occurred_at DESC,id DESC LIMIT 50
            """,(r,n)->new Event(r.getString(1),r.getObject(2,UUID.class),r.getObject(3,UUID.class),r.getObject(4,UUID.class),r.getBoolean(5),r.getString(6),r.getTimestamp(7).toInstant()));
        var regular=AppointmentRotationRules.next(order,s.position());
        return new View(order,next==null?null:next.id(),regular==null?null:regular.id(),s.revision(),history);
    }
    private void event(String kind,UUID appointment,UUID suggested,UUID actual,boolean advanced,String reason){
        db.update("""
            INSERT INTO appointment_rotation_events(id,appointment_id,kind,suggested_member_id,actual_member_id,actor_user_id,advanced,reason)
            VALUES(?,?,?,?,?,?,?,?)
            """,UUID.randomUUID(),appointment,kind,suggested,actual,Session.current().userId(),advanced,reason);
    }
    private void move(int position){db.update("UPDATE appointment_rotation_state SET next_position=?,revision=revision+1 WHERE id=1",position);}
    record Selection(AppointmentRotationRules.Member member, Long recoveredId) {}
    private Selection selection(State s,List<AppointmentRotationRules.Member> members) {
        var recovered=db.query("""
            SELECT r.id,r.member_id FROM appointment_turn_reservations r
            JOIN family_members m ON m.id=r.member_id AND m.active
            WHERE r.status='RELEASED' ORDER BY r.released_at,r.id LIMIT 1
            """,(rs,n)->Map.entry(rs.getLong(1),rs.getObject(2,UUID.class)));
        if(!recovered.isEmpty()) {
            var first=recovered.getFirst();
            var member=members.stream().filter(m->m.id().equals(first.getValue())).findFirst().orElseThrow();
            return new Selection(member,first.getKey());
        }
        return new Selection(AppointmentRotationRules.next(members,s.position()),null);
    }
    /** Called in the same transaction as the appointment insert or reassignment. */
    void reserve(UUID appointment,UUID assigned) { reserve(appointment,assigned,null); }
    void reserve(UUID appointment,UUID assigned,Long expectedRevision) {
        State s=state(true); var choice=selection(s,order());
        if(expectedRevision!=null) {
            checkRevision(s,expectedRevision);
            if(!AppointmentRotationRules.advances(choice.member(),assigned))
                throw new ResponseStatusException(HttpStatus.CONFLICT,"El responsable sugerido cambió. Vuelve a abrir el formulario");
        }
        if(!AppointmentRotationRules.advances(choice.member(),assigned)) return;
        if(Boolean.TRUE.equals(db.queryForObject("SELECT EXISTS(SELECT 1 FROM appointment_turn_reservations WHERE appointment_id=? AND status='RESERVED')",Boolean.class,appointment))) return;
        if(choice.recoveredId()!=null) {
            db.update("UPDATE appointment_turn_reservations SET status='REUSED' WHERE id=?",choice.recoveredId());
            move(s.position()); // recovered turn does not move the regular cursor
        } else move(AppointmentRotationRules.following(choice.member().position()));
        db.update("INSERT INTO appointment_turn_reservations(appointment_id,member_id,status) VALUES(?,?,'RESERVED')",appointment,assigned);
    }
    void release(UUID appointment) {
        State s=state(true);
        int changed=db.update("UPDATE appointment_turn_reservations SET status='RELEASED',released_at=clock_timestamp() WHERE appointment_id=? AND status='RESERVED'",appointment);
        if(changed>0) move(s.position());
    }
    void attendance(UUID appointment,UUID actual){
        State s=state(true); var members=order();
        if(actual==null || members.stream().noneMatch(m->m.id().equals(actual)))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Selecciona quién acompañó realmente");
        var reservations=db.query("SELECT member_id FROM appointment_turn_reservations WHERE appointment_id=? AND status='RESERVED'",(r,n)->r.getObject(1,UUID.class),appointment);
        UUID reserved=reservations.isEmpty()?null:reservations.getFirst();
        if(reserved!=null) {
            if(reserved.equals(actual)) db.update("UPDATE appointment_turn_reservations SET status='FULFILLED' WHERE appointment_id=? AND status='RESERVED'",appointment);
            else release(appointment);
        }
        // Existing pre-V9 appointments and replacements do not advance the cursor.
        event("ATTENDED",appointment,reserved,actual,false,null);
    }
    private void checkRevision(State s,long revision){if(s.revision()!=revision)
        throw new ResponseStatusException(HttpStatus.CONFLICT,"El turno cambió. Actualiza la pantalla o vuelve a abrir el formulario");}
    void configure(List<UUID> ids,UUID next,long revision){
        State s=state(true); checkRevision(s,revision); var current=order();
        var expected=new HashSet<UUID>(); for(var m:current) expected.add(m.id());
        if(ids==null || ids.size()!=expected.size() || !expected.equals(new HashSet<>(ids)) ||
            next==null || current.stream().noneMatch(m->m.id().equals(next)&&m.active()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Elige un orden completo y un siguiente familiar activo");
        var old=selection(s,current).member();
        for(int i=0;i<ids.size();i++) db.update("UPDATE appointment_rotation_order SET position=? WHERE member_id=?",i+1,ids.get(i));
        move(ids.indexOf(next)+1);
        event("CONFIGURED",null,old==null?null:old.id(),null,false,"Orden o siguiente turno configurado");
    }
    void skip(long revision,String reason){
        State s=state(true); checkRevision(s,revision);
        var choice=selection(s,order());
        var next=choice.member();
        if(next==null || reason==null || reason.isBlank() || reason.strip().length()>300)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Indica un motivo de hasta 300 caracteres y un turno activo");
        event("SKIPPED",null,next.id(),null,true,reason.strip());
        if(choice.recoveredId()!=null) {
            db.update("UPDATE appointment_turn_reservations SET status='WAIVED' WHERE id=?",choice.recoveredId());
            move(s.position());
        } else move(AppointmentRotationRules.following(next.position()));
    }
}
