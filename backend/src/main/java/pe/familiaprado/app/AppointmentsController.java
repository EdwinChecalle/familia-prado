package pe.familiaprado.app;

import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/appointments")
public class AppointmentsController {
    private final JdbcTemplate db;
    private final ChangeFeed feed;
    private final PushQueue push;
    public AppointmentsController(JdbcTemplate db,ChangeFeed feed,PushQueue push){this.db=db;this.feed=feed;this.push=push;}
    public record Appointment(UUID id,Instant appointmentAt,String hospital,String specialty,
                              UUID responsibleMemberId,String status,String preparation) {}
    private static final String COLUMNS = "id,appointment_at,hospital,specialty,responsible_member_id,status,preparation";
    private static final org.springframework.jdbc.core.RowMapper<Appointment> ROW = (r,n)->new Appointment(
        r.getObject("id",UUID.class),r.getTimestamp("appointment_at").toInstant(),
        r.getString("hospital"),r.getString("specialty"),
        r.getObject("responsible_member_id",UUID.class),r.getString("status"),r.getString("preparation"));

    /** Legacy consumer: preserved until all clients have migrated to /search. */
    @GetMapping public List<Appointment> list(@RequestParam(required=false) Instant after){
        Instant from=after==null?Instant.now().minusSeconds(30L*86400):after;
        return db.query("SELECT "+COLUMNS+" FROM appointments WHERE appointment_at>=? ORDER BY appointment_at, id LIMIT 100",
            ROW, Timestamp.from(from));
    }

    /** Explicit paging: the server sorts before LIMIT/OFFSET, never the Flutter client. */
    public record SearchPage(List<Appointment> items,long total,int limit,int offset,boolean hasMore) {}
    @GetMapping("/search")
    public SearchPage search(@RequestParam(defaultValue="UPCOMING") String bucket,
                             @RequestParam(required=false) LocalDate from,
                             @RequestParam(required=false) LocalDate to,
                             @RequestParam(required=false) UUID responsibleMemberId,
                             @RequestParam(required=false) String status,
                             @RequestParam(defaultValue="20") int limit,
                             @RequestParam(defaultValue="0") int offset) {
        final AppointmentSearchRules.Bucket group;
        try { group = AppointmentSearchRules.bucket(bucket);
              AppointmentSearchRules.pageSize(limit); AppointmentSearchRules.pageOffset(offset); }
        catch (IllegalArgumentException ex) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST,ex.getMessage()); }
        if (from!=null && to!=null && from.isAfter(to))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"El inicio es posterior al fin del rango");
        if (status!=null && !List.of("PLANNED","CONFIRMED","COMPLETED","CANCELLED").contains(status))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Estado de cita desconocido");
        LocalDate today = LocalDate.now(AppointmentSearchRules.LIMA);
        Instant startToday = AppointmentSearchRules.dayStart(today);
        Instant startTomorrow = AppointmentSearchRules.nextDayStart(today);
        StringBuilder filter=new StringBuilder(" WHERE 1=1");
        List<Object> args=new ArrayList<>();
        switch(group) {
            case UPCOMING -> {filter.append(" AND appointment_at >= ? AND status IN ('PLANNED','CONFIRMED')");args.add(Timestamp.from(startTomorrow));}
            case TODAY -> {filter.append(" AND appointment_at >= ? AND appointment_at < ? AND status <> 'CANCELLED'");
                           args.add(Timestamp.from(startToday));args.add(Timestamp.from(startTomorrow));}
            case HISTORY -> {filter.append(" AND appointment_at < ? AND status <> 'CANCELLED'");args.add(Timestamp.from(startToday));}
            case CANCELLED -> filter.append(" AND status = 'CANCELLED'");
        }
        if (from!=null){filter.append(" AND appointment_at >= ?");args.add(Timestamp.from(AppointmentSearchRules.dayStart(from)));}
        if (to!=null){filter.append(" AND appointment_at < ?");args.add(Timestamp.from(AppointmentSearchRules.nextDayStart(to)));}
        if (responsibleMemberId!=null){filter.append(" AND responsible_member_id = ?");args.add(responsibleMemberId);}
        if (status!=null){filter.append(" AND status = ?");args.add(status);}
        Long total=db.queryForObject("SELECT COUNT(*) FROM appointments"+filter,Long.class,args.toArray());
        List<Object> pageArgs=new ArrayList<>(args);pageArgs.add(limit);pageArgs.add(offset);
        List<Appointment> results=db.query("SELECT "+COLUMNS+" FROM appointments"+filter+
            " ORDER BY "+AppointmentSearchRules.order(group)+" LIMIT ? OFFSET ?",ROW,pageArgs.toArray());
        long count=total==null?0:total;
        return new SearchPage(results,count,limit,offset,(long)offset+results.size()<count);
    }

    public record AppointmentSummary(long upcoming,long today,long history,long cancelled,Appointment next) {}
    @GetMapping("/summary")
    public AppointmentSummary summary(){
        Instant startToday=AppointmentSearchRules.dayStart(LocalDate.now(AppointmentSearchRules.LIMA));
        Instant startTomorrow=AppointmentSearchRules.nextDayStart(LocalDate.now(AppointmentSearchRules.LIMA));
        long today = db.queryForObject("SELECT COUNT(*) FROM appointments WHERE appointment_at >= ? AND appointment_at < ? AND status <> 'CANCELLED'",
            Long.class,Timestamp.from(startToday),Timestamp.from(startTomorrow));
        long upcoming = db.queryForObject("SELECT COUNT(*) FROM appointments WHERE appointment_at >= ? AND status IN ('PLANNED','CONFIRMED')",
            Long.class,Timestamp.from(startTomorrow));
        long history = db.queryForObject("SELECT COUNT(*) FROM appointments WHERE appointment_at < ? AND status <> 'CANCELLED'",
            Long.class,Timestamp.from(startToday));
        long cancelled = db.queryForObject("SELECT COUNT(*) FROM appointments WHERE status='CANCELLED'",Long.class);
        List<Appointment> next=db.query("SELECT "+COLUMNS+" FROM appointments WHERE appointment_at >= ? AND status IN ('PLANNED','CONFIRMED') ORDER BY appointment_at ASC,id ASC LIMIT 1",
            ROW,Timestamp.from(Instant.now()));
        return new AppointmentSummary(upcoming,today,history,cancelled,next.isEmpty()?null:next.getFirst());
    }

    public record NewAppointment(Instant appointmentAt,String hospital,String specialty,
                                 UUID responsibleMemberId,String preparation) {}
    @Transactional @PostMapping @ResponseStatus(HttpStatus.CREATED)
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
          """,id,Timestamp.from(r.appointmentAt()),r.hospital().strip(),r.specialty().strip(),
            r.responsibleMemberId(),r.preparation(),Session.current().userId());
        push.appointmentCreated(id,r.responsibleMemberId(),r.appointmentAt());
        feed.changed("appointments");
        return Map.of("id",id);
    }
    public record ChangeStatus(String status) {}
    @Transactional @PatchMapping("/{id}/status") @ResponseStatus(HttpStatus.NO_CONTENT)
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
        push.appointmentStatusChanged(id,rows.getFirst().getKey().orElse(null),r.status());
        feed.changed("appointments");
    }
}
