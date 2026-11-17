package pe.familiaprado.app;

import java.time.Instant;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/appointments")
public class AppointmentsController {
    private final JdbcTemplate db;
    public AppointmentsController(JdbcTemplate db){ this.db=db; }
    public record Appointment(UUID id,Instant appointmentAt,String hospital,String specialty,
                              UUID responsibleMemberId,String status,String preparation) {}
    @GetMapping public List<Appointment> list(@RequestParam(required=false) Instant after){
        Instant from=after==null?Instant.now().minusSeconds(30L*86400):after;
        return db.query("""
            SELECT id,appointment_at,hospital,specialty,responsible_member_id,status,preparation
            FROM appointments WHERE appointment_at>=? ORDER BY appointment_at LIMIT 100
            """,(r,n)->new Appointment(r.getObject("id",UUID.class),
               r.getTimestamp("appointment_at").toInstant(),r.getString("hospital"),
               r.getString("specialty"),r.getObject("responsible_member_id",UUID.class),
               r.getString("status"),r.getString("preparation")),java.sql.Timestamp.from(from));
    }
    public record NewAppointment(Instant appointmentAt,String hospital,String specialty,
                                 UUID responsibleMemberId,String preparation) {}
    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> create(@RequestBody NewAppointment r){
        Session.current().adminOnly();
        if(r.appointmentAt()==null||r.hospital()==null||r.hospital().isBlank()||r.hospital().length()>160||
          r.specialty()==null||r.specialty().isBlank()||r.specialty().length()>120||
          (r.preparation()!=null&&r.preparation().length()>500))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Revisa la fecha, hospital o especialidad");
        UUID id=UUID.randomUUID();
        db.update("""
          INSERT INTO appointments(id,appointment_at,hospital,specialty,responsible_member_id,status,preparation,created_by)
          VALUES(?,?,?,?,?,'PLANNED',?,?)
          """,id,java.sql.Timestamp.from(r.appointmentAt()),r.hospital().strip(),r.specialty().strip(),
            r.responsibleMemberId(),r.preparation(),Session.current().userId());
        return Map.of("id",id);
    }
    public record ChangeStatus(String status) {}
    @PatchMapping("/{id}/status") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void status(@PathVariable UUID id,@RequestBody ChangeStatus r){
        var rows=db.query("SELECT responsible_member_id,status FROM appointments WHERE id=?",
          (rs,n)->Map.entry(Optional.ofNullable(rs.getObject(1,UUID.class)),rs.getString(2)),id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Cita no encontrada");
        if(!Session.current().isAdmin()){
            UUID member=rows.getFirst().getKey().orElseThrow(()->new ResponseStatusException(HttpStatus.FORBIDDEN));
            Session.current().ownsOrAdmin(member);
        }
        if(r.status()==null||!List.of("CONFIRMED","COMPLETED","CANCELLED").contains(r.status()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Estado desconocido");
        if(List.of("COMPLETED","CANCELLED").contains(rows.getFirst().getValue()))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Cita cerrada");
        db.update("UPDATE appointments SET status=? WHERE id=?",r.status(),id);
    }
}
