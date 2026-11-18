package pe.familiaprado.app;

import java.math.BigDecimal;
import java.sql.Date;
import java.sql.Time;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/care")
public class CareController {
    private final JdbcTemplate db;
    private final CareAccess access;
    CareController(JdbcTemplate db,CareAccess access){this.db=db;this.access=access;}

    public record NewMedication(String name,String instructions,String prescriber,
                                String scheduleTimes,LocalDate startsOn,LocalDate endsOn){}
    public record NewRecord(LocalDate scheduledDate,String scheduledTime,String status,String comment){}
    public record CorrectRecord(String status,String reason){}
    public record Observation(String kind,BigDecimal valuePrimary,BigDecimal valueSecondary,
                              String notes,Instant observedAt){}

    private static String required(String value,int limit,String label){
        if(value==null || value.isBlank() || value.length()>limit)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Revisa "+label);
        return value.strip();
    }
    private static String optional(String value,int limit,String label){
        if(value!=null && value.length()>limit) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Revisa "+label);
        return value==null?null:value.strip();
    }
    private static void rules(Runnable validator){
        try {validator.run();} catch(IllegalArgumentException e){
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,e.getMessage());
        }
    }
    @GetMapping("/medications") public List<Map<String,Object>> medications(){
        access.require();
        return db.query("""
            SELECT id,name,instructions,prescriber,schedule_times,starts_on,ends_on,active
            FROM care_medications ORDER BY active DESC,created_at DESC
            """,(r,i)->{
            Map<String,Object> data=new LinkedHashMap<>();
            data.put("id",r.getObject("id",UUID.class));data.put("name",r.getString("name"));
            data.put("instructions",r.getString("instructions"));data.put("prescriber",r.getString("prescriber"));
            data.put("scheduleTimes",r.getString("schedule_times"));
            data.put("startsOn",r.getDate("starts_on").toLocalDate());
            Date end=r.getDate("ends_on");data.put("endsOn",end==null?null:end.toLocalDate());
            data.put("active",r.getBoolean("active")); return data;
        });
    }
    @PostMapping("/medications") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> addMedication(@RequestBody NewMedication r){
        Session.current().adminOnly();
        String name=required(r.name(),140,"nombre");String instructions=required(r.instructions(),500,"indicaciones médicas");
        String prescriber=optional(r.prescriber(),140,"profesional");
        if(r.startsOn()==null || r.endsOn()!=null && r.endsOn().isBefore(r.startsOn()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Revisa las fechas de la indicación");
        rules(()->CareRules.times(r.scheduleTimes()));
        UUID id=UUID.randomUUID();
        db.update("""
            INSERT INTO care_medications(id,name,instructions,prescriber,schedule_times,starts_on,ends_on,created_by)
            VALUES(?,?,?,?,?,?,?,?)
            """,id,name,instructions,prescriber,r.scheduleTimes(),Date.valueOf(r.startsOn()),
            r.endsOn()==null?null:Date.valueOf(r.endsOn()),Session.current().userId());
        return Map.of("id",id);
    }
    @PatchMapping("/medications/{id}/stop") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void stop(@PathVariable UUID id) {
        Session.current().adminOnly();
        if(db.update("UPDATE care_medications SET active=false WHERE id=? AND active=true",id)==0)
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Indicación no encontrada o ya inactiva");
    }
    @GetMapping("/medication-records") public List<Map<String,Object>> medicationRecords(
            @RequestParam(required=false) LocalDate from){
        access.require();
        LocalDate start=from==null?LocalDate.now(ZoneId.of("America/Lima")).minusDays(14):from;
        if(start.isBefore(LocalDate.now(ZoneId.of("America/Lima")).minusYears(2)))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Periodo fuera de rango");
        return db.query("""
            SELECT l.id,l.medication_id,m.name,l.scheduled_date,l.scheduled_time,l.status,
                   l.comment,l.registered_at,COALESCE(f.display_name,'Administrador') author
            FROM care_medication_records l JOIN care_medications m ON m.id=l.medication_id
            JOIN app_users u ON u.id=l.registered_by LEFT JOIN family_members f ON f.id=u.member_id
            WHERE l.scheduled_date>=? ORDER BY l.scheduled_date DESC,l.scheduled_time DESC LIMIT 250
            """,(r,i)->{
             Map<String,Object> out=new LinkedHashMap<>();
             out.put("id",r.getObject("id",UUID.class));out.put("medicationId",r.getObject("medication_id",UUID.class));
             out.put("medicationName",r.getString("name"));out.put("scheduledDate",r.getDate("scheduled_date").toLocalDate());
             out.put("scheduledTime",r.getTime("scheduled_time").toLocalTime().toString());
             out.put("status",r.getString("status"));out.put("comment",r.getString("comment"));
             out.put("registeredAt",r.getTimestamp("registered_at").toInstant());out.put("registeredBy",r.getString("author"));
             return out;
            },Date.valueOf(start));
    }
    @PostMapping("/medications/{id}/records") @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    public Map<String,UUID> addRecord(@PathVariable UUID id,@RequestBody NewRecord r){
        access.require();
        if(r.scheduledDate()==null || r.scheduledTime()==null)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Selecciona fecha y horario");
        String status;
        try{status=CareRules.status(r.status());}
        catch(IllegalArgumentException ex){throw new ResponseStatusException(HttpStatus.BAD_REQUEST,ex.getMessage());}
        String comment=optional(r.comment(),500,"observación");
        LocalTime time;
        try{time=LocalTime.parse(r.scheduledTime());}
        catch(Exception e){throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Horario inválido");}
        var meds=db.query("""
            SELECT schedule_times,starts_on,ends_on,active FROM care_medications WHERE id=? FOR UPDATE
            """,(rs,n)->new Object[]{rs.getString(1),rs.getDate(2).toLocalDate(),
                rs.getDate(3)==null?null:rs.getDate(3).toLocalDate(),rs.getBoolean(4)},id);
        if(meds.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Indicación no encontrada");
        Object[] med=meds.getFirst();
        if(!(boolean)med[3] || !CareRules.scheduled((LocalDate)med[1],(LocalDate)med[2],r.scheduledDate(),time,(String)med[0]))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Horario o fecha fuera de la indicación vigente");
        LocalDate today=LocalDate.now(ZoneId.of("America/Lima"));
        if(r.scheduledDate().isAfter(today) || r.scheduledDate().isBefore(today.minusDays(14)))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Solo se registran fechas pasadas, hasta 14 días atrás");
        if (ZonedDateTime.of(r.scheduledDate(),time,ZoneId.of("America/Lima"))
                .isAfter(ZonedDateTime.now(ZoneId.of("America/Lima"))))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"No se puede confirmar anticipadamente una administración");
        UUID recordId=UUID.randomUUID();
        try {
            db.update("""
                INSERT INTO care_medication_records(id,medication_id,scheduled_date,scheduled_time,status,comment,registered_by)
                VALUES(?,?,?,?,?,?,?)
                """,recordId,id,Date.valueOf(r.scheduledDate()),Time.valueOf(time),status,comment,Session.current().userId());
        } catch (org.springframework.dao.DataIntegrityViolationException ex) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Ese horario ya fue registrado; revisa el historial antes de repetir");
        }
        return Map.of("id",recordId);
    }
    @PatchMapping("/medication-records/{id}/correct") @ResponseStatus(HttpStatus.NO_CONTENT)
    @Transactional public void correct(@PathVariable UUID id,@RequestBody CorrectRecord r){
        Session.current().adminOnly();
        String newStatus;
        try{newStatus=CareRules.status(r.status());}
        catch(IllegalArgumentException ex){throw new ResponseStatusException(HttpStatus.BAD_REQUEST,ex.getMessage());}
        String reason=required(r.reason(),300,"motivo de corrección");
        var old=db.query("SELECT status FROM care_medication_records WHERE id=? FOR UPDATE",
            (rs,n)->rs.getString(1),id);
        if(old.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Registro no encontrado");
        if(old.getFirst().equals(newStatus)) throw new ResponseStatusException(HttpStatus.CONFLICT,"El estado ya coincide");
        db.update("""
            INSERT INTO care_medication_corrections(id,record_id,old_status,new_status,reason,corrected_by)
            VALUES(?,?,?,?,?,?)
            """,UUID.randomUUID(),id,old.getFirst(),newStatus,reason,Session.current().userId());
        db.update("UPDATE care_medication_records SET status=? WHERE id=?",newStatus,id);
    }
    @PostMapping("/observations") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> observe(@RequestBody Observation r){
        access.require();
        rules(()->CareRules.observation(r.kind(),r.valuePrimary(),r.valueSecondary(),r.notes()));
        if(r.observedAt()==null || r.observedAt().isAfter(Instant.now().plusSeconds(300)) ||
            r.observedAt().isBefore(Instant.now().minusSeconds(86400L*365)))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Revisa fecha y hora del registro");
        UUID id=UUID.randomUUID();
        db.update("""
           INSERT INTO care_observations(id,kind,value_primary,value_secondary,notes,observed_at,recorded_by)
           VALUES(?,?,?,?,?,?,?)
           """,id,r.kind(),r.valuePrimary(),r.valueSecondary(),optional(r.notes(),700,"notas"),
               Timestamp.from(r.observedAt()),Session.current().userId());
        return Map.of("id",id);
    }
    @GetMapping("/observations") public List<Map<String,Object>> observations(){
        access.require();
        return db.query("""
            SELECT o.id,o.kind,o.value_primary,o.value_secondary,o.notes,o.observed_at,
                   COALESCE(m.display_name,'Administrador') author
            FROM care_observations o JOIN app_users u ON u.id=o.recorded_by
            LEFT JOIN family_members m ON m.id=u.member_id
            ORDER BY o.observed_at DESC LIMIT 150
            """,(rs,n)->{
              Map<String,Object> out=new LinkedHashMap<>();
              out.put("id",rs.getObject("id",UUID.class));out.put("kind",rs.getString("kind"));
              out.put("valuePrimary",rs.getBigDecimal("value_primary"));
              out.put("valueSecondary",rs.getBigDecimal("value_secondary"));
              out.put("notes",rs.getString("notes"));out.put("observedAt",rs.getTimestamp("observed_at").toInstant());
              out.put("registeredBy",rs.getString("author"));return out;
            });
    }
}
