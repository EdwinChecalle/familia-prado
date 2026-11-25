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
    private final IdempotencyService idem;
    public AppointmentsController(JdbcTemplate db,ChangeFeed feed,PushQueue push,IdempotencyService idem){this.db=db;this.feed=feed;this.push=push;this.idem=idem;}
    public record Appointment(UUID id,Instant appointmentAt,String hospital,String specialty,
                              UUID responsibleMemberId,String status,String preparation,UUID actualMemberId) {
        public Appointment(UUID id,Instant appointmentAt,String hospital,String specialty,UUID responsibleMemberId,String status,String preparation){
            this(id,appointmentAt,hospital,specialty,responsibleMemberId,status,preparation,null);
        }
    }
    private static final String COLUMNS = "id,appointment_at,hospital,specialty,responsible_member_id,status,preparation,actual_member_id";
    private static final org.springframework.jdbc.core.RowMapper<Appointment> ROW = (r,n)->new Appointment(
        r.getObject("id",UUID.class),r.getTimestamp("appointment_at").toInstant(),
        r.getString("hospital"),r.getString("specialty"),
        r.getObject("responsible_member_id",UUID.class),r.getString("status"),r.getString("preparation"),r.getObject("actual_member_id",UUID.class));

    /** Legacy consumer: preserved until all clients have migrated to /search. */
    @GetMapping public List<Appointment> list(@RequestParam(required=false) Instant after){
        Instant from=after==null?Instant.now().minusSeconds(30L*86400):after;
        return db.query("SELECT "+COLUMNS+" FROM appointments WHERE deleted_at IS NULL AND appointment_at>=? ORDER BY appointment_at, id LIMIT 100",
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
        StringBuilder filter=new StringBuilder(" WHERE deleted_at IS NULL");
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

    /** Full calendar month, including all statuses, using the same Lima time boundaries. */
    @GetMapping("/calendar")
    public List<Appointment> calendar(@RequestParam("month") @org.springframework.format.annotation.DateTimeFormat(iso=org.springframework.format.annotation.DateTimeFormat.ISO.DATE) LocalDate month) {
        LocalDate first=month.withDayOfMonth(1);
        LocalDate next=first.plusMonths(1);
        return db.query("SELECT "+COLUMNS+" FROM appointments WHERE deleted_at IS NULL AND appointment_at >= ? AND appointment_at < ? ORDER BY appointment_at ASC,id ASC",
            ROW, Timestamp.from(AppointmentSearchRules.dayStart(first)),
            Timestamp.from(AppointmentSearchRules.dayStart(next)));
    }

    public record AppointmentSummary(long upcoming,long today,long history,long cancelled,Appointment next,
                                     List<Appointment> todayItems, Appointment nextAfterToday) {}
    @GetMapping("/summary")
    public AppointmentSummary summary(){
        LocalDate day=LocalDate.now(AppointmentSearchRules.LIMA);
        Instant startToday=AppointmentSearchRules.dayStart(day);
        Instant startTomorrow=AppointmentSearchRules.nextDayStart(day);
        List<Appointment> todayItems=db.query("SELECT "+COLUMNS+" FROM appointments WHERE deleted_at IS NULL AND appointment_at >= ? AND appointment_at < ? AND status <> 'CANCELLED' ORDER BY appointment_at ASC,id ASC",
            ROW,Timestamp.from(startToday),Timestamp.from(startTomorrow));
        long today=todayItems.size();
        long upcoming = db.queryForObject("SELECT COUNT(*) FROM appointments WHERE deleted_at IS NULL AND appointment_at >= ? AND status IN ('PLANNED','CONFIRMED')",
            Long.class,Timestamp.from(startTomorrow));
        long history = db.queryForObject("SELECT COUNT(*) FROM appointments WHERE deleted_at IS NULL AND appointment_at < ? AND status <> 'CANCELLED'",
            Long.class,Timestamp.from(startToday));
        long cancelled = db.queryForObject("SELECT COUNT(*) FROM appointments WHERE deleted_at IS NULL AND status='CANCELLED'",Long.class);
        List<Appointment> next=db.query("SELECT "+COLUMNS+" FROM appointments WHERE deleted_at IS NULL AND appointment_at >= ? AND status IN ('PLANNED','CONFIRMED') ORDER BY appointment_at ASC,id ASC LIMIT 1",
            ROW,Timestamp.from(Instant.now()));
        List<Appointment> afterToday=db.query("SELECT "+COLUMNS+" FROM appointments WHERE deleted_at IS NULL AND appointment_at >= ? AND status IN ('PLANNED','CONFIRMED') ORDER BY appointment_at ASC,id ASC LIMIT 1",
            ROW,Timestamp.from(startTomorrow));
        return new AppointmentSummary(upcoming,today,history,cancelled,next.isEmpty()?null:next.getFirst(),
            todayItems,afterToday.isEmpty()?null:afterToday.getFirst());
    }

    public record NewAppointment(Instant appointmentAt,String hospital,String specialty,
                                 UUID responsibleMemberId,String preparation,Long rotationRevision) {
        public NewAppointment(Instant appointmentAt,String hospital,String specialty,UUID responsibleMemberId,String preparation) {
            this(appointmentAt,hospital,specialty,responsibleMemberId,preparation,null);
        }
    }
    @Transactional @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> create(@RequestBody NewAppointment r,
        @RequestHeader(value="Idempotency-Key",required=false) String key){
        Session.current().adminOnly();
        validate(r);
        return Map.of("id",idem.run(key,"appointments.create",r,()->{
        UUID id=UUID.randomUUID();
        db.update("""
          INSERT INTO appointments(id,appointment_at,hospital,specialty,responsible_member_id,status,preparation,created_by)
          VALUES(?,?,?,?,?,'PLANNED',?,?)
          """,id,Timestamp.from(r.appointmentAt()),r.hospital().strip(),r.specialty().strip(),
            r.responsibleMemberId(),r.preparation(),Session.current().userId());
        new AppointmentRotation(db).reserve(id,r.responsibleMemberId(),r.rotationRevision());
        push.appointmentCreated(id,r.responsibleMemberId(),r.appointmentAt());
        feed.changed("appointments");
        return id;
        }));
    }
    private void validate(NewAppointment r){
        if(r.appointmentAt()==null||r.hospital()==null||r.hospital().isBlank()||r.hospital().length()>160||
          r.specialty()==null||r.specialty().isBlank()||r.specialty().length()>120||
          (r.preparation()!=null&&r.preparation().length()>500))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Revisa la fecha, hospital o especialidad");
        if(r.responsibleMemberId()!=null && !Boolean.TRUE.equals(db.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM family_members WHERE id=? AND active=true)",Boolean.class,r.responsibleMemberId())))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Acompañante no disponible");
    }
    private Appointment lock(UUID id){
        var rows=db.query("SELECT "+COLUMNS+" FROM appointments WHERE deleted_at IS NULL AND id=? FOR UPDATE",ROW,id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Cita no encontrada");
        return rows.getFirst();
    }
    private void audit(UUID id,String action){
        db.update("INSERT INTO appointment_audit(id,appointment_id,actor_user_id,action) VALUES(?,?,?,?)",
            UUID.randomUUID(),id,Session.current().userId(),action);
    }
    @Transactional @PatchMapping("/{id}") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void edit(@PathVariable UUID id,@RequestBody NewAppointment r){
        Session.current().adminOnly();
        Appointment old=lock(id);
        if(!List.of("PLANNED","CONFIRMED").contains(old.status()))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"No se puede editar una cita cerrada");
        validate(r);
        String prep=r.preparation()==null?"":r.preparation().strip();
        if(old.appointmentAt().equals(r.appointmentAt()) && old.hospital().equals(r.hospital().strip())
            && old.specialty().equals(r.specialty().strip()) && Objects.equals(old.responsibleMemberId(),r.responsibleMemberId())
            && Objects.equals(old.preparation()==null?"":old.preparation().strip(),prep)) return;
        boolean reassigned=!Objects.equals(old.responsibleMemberId(),r.responsibleMemberId());
        boolean rescheduled=!old.appointmentAt().equals(r.appointmentAt());
        String status=reassigned||rescheduled?"PLANNED":old.status();
        db.update("""
            UPDATE appointments SET appointment_at=?,hospital=?,specialty=?,responsible_member_id=?,
                preparation=?,status=?,revision=revision+1 WHERE id=?
            """,Timestamp.from(r.appointmentAt()),r.hospital().strip(),r.specialty().strip(),r.responsibleMemberId(),prep,status,id);
        if(reassigned) {
            var rotation=new AppointmentRotation(db);
            rotation.release(id);
            rotation.reserve(id,r.responsibleMemberId());
        }
        int revision=db.queryForObject("SELECT revision FROM appointments WHERE id=?",Integer.class,id);
        push.appointmentEdited(id,r.responsibleMemberId(),r.appointmentAt(),revision);
        audit(id,"EDITED"); feed.changed("appointments");
    }
    // Endpoint explícito: no elimina físicamente los datos, ni depende de DELETE en clientes antiguos.
    @Transactional @PatchMapping("/{id}/archive") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void archive(@PathVariable UUID id){
        Session.current().adminOnly();
        var rows=db.query("SELECT "+COLUMNS+" FROM appointments WHERE id=? FOR UPDATE",ROW,id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Cita no encontrada");
        int changed=db.update("UPDATE appointments SET deleted_at=NOW() WHERE id=? AND deleted_at IS NULL",id);
        if(changed==0)return;
        var old=rows.getFirst();
        if(List.of("PLANNED","CONFIRMED").contains(old.status())) {
            new AppointmentRotation(db).release(id);
            push.appointmentStatusChanged(id,old.responsibleMemberId(),"CANCELLED");
        }
        else push.cancelAppointmentPending(id);
        audit(id,"DELETED"); feed.changed("appointments");
    }
    public record ChangeStatus(String status,UUID actualMemberId) {
        public ChangeStatus(String status){this(status,null);}
    }
    @Transactional @PatchMapping("/{id}/status") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void status(@PathVariable UUID id,@RequestBody ChangeStatus r){
        var rows=db.query("SELECT responsible_member_id,status FROM appointments WHERE deleted_at IS NULL AND id=? FOR UPDATE",
          (rs,n)->Map.entry(Optional.ofNullable(rs.getObject(1,UUID.class)),rs.getString(2)),id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Cita no encontrada");
        if(!Session.current().isAdmin()){
            UUID member=rows.getFirst().getKey().orElseThrow(()->new ResponseStatusException(HttpStatus.FORBIDDEN));
            Session.current().ownsOrAdmin(member);
        }
        if(r.status()==null||!List.of("CONFIRMED","COMPLETED","CANCELLED").contains(r.status()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Estado desconocido");
        if(r.status().equals(rows.getFirst().getValue())) return;
        if(List.of("COMPLETED","CANCELLED").contains(rows.getFirst().getValue()))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Cita cerrada");
        if("COMPLETED".equals(r.status())) {
            UUID actual=r.actualMemberId()==null?rows.getFirst().getKey().orElse(null):r.actualMemberId();
            if(!Session.current().isAdmin() && !Objects.equals(actual,Session.current().memberId()))
                throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Solo administración puede confirmar otro acompañante");
            new AppointmentRotation(db).attendance(id,actual);
            db.update("UPDATE appointments SET status=?,actual_member_id=? WHERE id=?",r.status(),actual,id);
        } else {
            if("CANCELLED".equals(r.status())) new AppointmentRotation(db).release(id);
            db.update("UPDATE appointments SET status=? WHERE id=?",r.status(),id);
        }
        push.appointmentStatusChanged(id,rows.getFirst().getKey().orElse(null),r.status());
        audit(id,r.status());
        feed.changed("appointments");
    }
}
