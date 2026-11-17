package pe.familiaprado.app;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class RotationService {
    private final JdbcTemplate db;
    private final ChangeFeed feed;
    private static final ZoneId PERU=ZoneId.of("America/Lima");
    public RotationService(JdbcTemplate db,ChangeFeed feed) { this.db=db;this.feed=feed; }
    public record Member(UUID id,String name,int position) {}
    public record Week(LocalDate monday,LocalDate sunday,UUID memberId,String memberName,int completedMeals,boolean configured) {}
    public record Config(LocalDate anchorMonday,int anchorPosition,boolean confirmed) {}
    public record Meal(LocalDate date,String meal,boolean completed) {}
    static LocalDate monday(LocalDate day) { return RotationMath.monday(day); }
    static int position(LocalDate anchor, int anchorPosition, LocalDate week, int cycle) {
        return RotationMath.position(anchor,anchorPosition,week,cycle);
    }
    public List<Member> members() {
        return db.query("SELECT id,display_name,rotation_position FROM family_members WHERE active=true ORDER BY rotation_position",
            (rs,n)->new Member(rs.getObject("id",UUID.class),rs.getString("display_name"),rs.getInt("rotation_position")));
    }
    public Config config() {
        return db.queryForObject("SELECT anchor_monday,anchor_position,confirmed FROM rotation_config WHERE id=1",
            (r,n)->new Config(r.getObject("anchor_monday",LocalDate.class),r.getInt("anchor_position"),r.getBoolean("confirmed")));
    }
    public Member owner(LocalDate week) {
        LocalDate mon=monday(week);
        var overridden=db.query("SELECT f.id,f.display_name,f.rotation_position FROM week_overrides w " +
             "JOIN family_members f ON f.id=w.member_id WHERE w.week_monday=?",
             (r,n)->new Member(r.getObject("id",UUID.class),r.getString("display_name"),r.getInt("rotation_position")),
             java.sql.Date.valueOf(mon));
        if (!overridden.isEmpty()) return overridden.getFirst();
        var order=members();
        if (order.size()!=8) throw new ResponseStatusException(HttpStatus.CONFLICT,"Deben existir ocho miembros activos");
        Config c=config();
        int pos=position(c.anchorMonday(),c.anchorPosition(),mon,order.size());
        return order.get(pos-1);
    }
    public List<Week> weeks(LocalDate from,int count) {
        if (count<1 || count>32) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Entre 1 y 32 semanas");
        var out=new ArrayList<Week>();
        boolean confirmed=config().confirmed();
        for(int i=0;i<count;i++) {
            LocalDate mon=monday(from).plusWeeks(i);
            Member member=owner(mon);
            Integer checked=db.queryForObject("SELECT COUNT(*) FROM meal_checks WHERE week_monday=? AND completed=true",
                Integer.class,java.sql.Date.valueOf(mon));
            out.add(new Week(mon,mon.plusDays(6),member.id(),member.name(),checked==null?0:checked,confirmed));
        }
        return out;
    }
    public List<Meal> meals(LocalDate week) {
        return db.query("SELECT meal_date,meal,completed FROM meal_checks WHERE week_monday=? ORDER BY meal_date,meal",
             (r,n)->new Meal(r.getObject("meal_date",LocalDate.class),r.getString("meal"),r.getBoolean("completed")),
             java.sql.Date.valueOf(monday(week)));
    }
    @Transactional
    public void checkMeal(LocalDate week,LocalDate date,String meal,boolean completed) {
        if (!config().confirmed()) throw new ResponseStatusException(HttpStatus.CONFLICT,"Primero confirma el calendario familiar");
        LocalDate mon=monday(week);
        if (!monday(date).equals(mon)) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"La comida no pertenece a esta semana");
        if (date.isAfter(LocalDate.now(PERU))) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"No puedes marcar una comida futura");
        if (meal==null || !List.of("BREAKFAST","LUNCH","DINNER").contains(meal))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Comida incorrecta");
        Session.current().ownsOrAdmin(owner(mon).id());
        db.update("""
            INSERT INTO meal_checks(id,week_monday,meal_date,meal,completed,changed_by) VALUES(?,?,?,?,?,?)
            ON CONFLICT(meal_date,meal) DO UPDATE SET completed=EXCLUDED.completed,
               changed_by=EXCLUDED.changed_by,changed_at=NOW()
            """,UUID.randomUUID(),java.sql.Date.valueOf(mon),java.sql.Date.valueOf(date),
            meal,completed,Session.current().userId());
        feed.changed("turns");
    }
    @Transactional
    public void configure(LocalDate anchor,List<UUID> ordered,UUID first) {
        Session.current().adminOnly();
        if (anchor==null || anchor.getDayOfWeek()!=DayOfWeek.MONDAY || ordered==null || ordered.size()!=8 ||
                new HashSet<>(ordered).size()!=8 || !ordered.contains(first))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Se necesitan ocho miembros únicos y un lunes válido");
        var actual=members().stream().map(Member::id).toList();
        if (!new HashSet<>(ordered).equals(new HashSet<>(actual)))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Los miembros no coinciden con los registrados");
        // Changing history would change the meaning of previous checks or accepted swaps.
        Integer historical=db.queryForObject("""
            SELECT (SELECT COUNT(*) FROM meal_checks) + (SELECT COUNT(*) FROM week_overrides)
            """,Integer.class);
        if (historical!=null && historical>0)
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Ya existe historial: no se permite reiniciar la rotación");
        db.queryForObject("SELECT id FROM rotation_config WHERE id=1 FOR UPDATE",Integer.class);
        for(int i=0;i<ordered.size();i++)
            db.update("UPDATE family_members SET rotation_position=? WHERE id=?",i+1,ordered.get(i));
        db.update("UPDATE rotation_config SET anchor_monday=?,anchor_position=?,confirmed=true WHERE id=1",
            java.sql.Date.valueOf(anchor),ordered.indexOf(first)+1);
        feed.changed("turns");
    }
    public record Swap(UUID id,LocalDate weekA,LocalDate weekB,UUID memberA,UUID memberB,String status) {}
    public List<Swap> swaps() {
        return db.query("SELECT id,week_a,week_b,member_a,member_b,status FROM swap_requests ORDER BY created_at DESC LIMIT 100",
            (r,n)->new Swap(r.getObject("id",UUID.class),r.getObject("week_a",LocalDate.class),
              r.getObject("week_b",LocalDate.class),r.getObject("member_a",UUID.class),
              r.getObject("member_b",UUID.class),r.getString("status")));
    }
    @Transactional
    public UUID requestSwap(LocalDate a, LocalDate b) {
        if (!config().confirmed()) throw new ResponseStatusException(HttpStatus.CONFLICT,"Confirma la rotación primero");
        db.queryForObject("SELECT id FROM rotation_config WHERE id=1 FOR UPDATE",Integer.class);
        if (a==null||b==null||!a.equals(monday(a))||!b.equals(monday(b))||a.equals(b))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Selecciona dos lunes diferentes");
        LocalDate earliest=monday(LocalDate.now(PERU)).plusWeeks(1);
        if (a.isBefore(earliest)||b.isBefore(earliest))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Solo se pueden cambiar semanas que todavía no comienzan");
        Member ma=owner(a),mb=owner(b);
        if(ma.id().equals(mb.id())) throw new ResponseStatusException(HttpStatus.CONFLICT,"Ambas semanas pertenecen al mismo familiar");
        Session.current().ownsOrAdmin(ma.id());
        Integer open=db.queryForObject("SELECT COUNT(*) FROM swap_requests WHERE status='PENDING' AND (week_a IN (?,?) OR week_b IN (?,?))",
          Integer.class,java.sql.Date.valueOf(a),java.sql.Date.valueOf(b),java.sql.Date.valueOf(a),java.sql.Date.valueOf(b));
        if(open!=null&&open>0) throw new ResponseStatusException(HttpStatus.CONFLICT,"Existe una solicitud pendiente para una de las semanas");
        UUID id=UUID.randomUUID();
        db.update("INSERT INTO swap_requests(id,week_a,week_b,member_a,member_b,requested_by,status) VALUES(?,?,?,?,?,?,'PENDING')",
            id,java.sql.Date.valueOf(a),java.sql.Date.valueOf(b),ma.id(),mb.id(),Session.current().userId());
        feed.changed("turns");
        return id;
    }
    @Transactional
    public void decideSwap(UUID id,boolean accept) {
        db.queryForObject("SELECT id FROM rotation_config WHERE id=1 FOR UPDATE",Integer.class);
        var rows=db.query("SELECT week_a,week_b,member_a,member_b,status FROM swap_requests WHERE id=? FOR UPDATE",
            (r,n)->new Swap(id,r.getObject("week_a",LocalDate.class),r.getObject("week_b",LocalDate.class),
                r.getObject("member_a",UUID.class),r.getObject("member_b",UUID.class),r.getString("status")),id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Solicitud inexistente");
        Swap swap=rows.getFirst();
        if(!swap.status().equals("PENDING")) throw new ResponseStatusException(HttpStatus.CONFLICT,"Solicitud ya resuelta");
        Session.current().ownsOrAdmin(swap.memberB());
        if(accept) {
            LocalDate earliest=monday(LocalDate.now(PERU)).plusWeeks(1);
            if(swap.weekA().isBefore(earliest)||swap.weekB().isBefore(earliest)||
              !owner(swap.weekA()).id().equals(swap.memberA()) || !owner(swap.weekB()).id().equals(swap.memberB()))
                throw new ResponseStatusException(HttpStatus.CONFLICT,"La asignación ya cambió o la semana comenzó");
            db.update("INSERT INTO week_overrides(week_monday,member_id) VALUES (?,?) ON CONFLICT(week_monday) DO UPDATE SET member_id=EXCLUDED.member_id",
                java.sql.Date.valueOf(swap.weekA()),swap.memberB());
            db.update("INSERT INTO week_overrides(week_monday,member_id) VALUES (?,?) ON CONFLICT(week_monday) DO UPDATE SET member_id=EXCLUDED.member_id",
                java.sql.Date.valueOf(swap.weekB()),swap.memberA());
        }
        db.update("UPDATE swap_requests SET status=?,decided_by=?,decided_at=NOW() WHERE id=?",
          accept?"ACCEPTED":"REJECTED",Session.current().userId(),id);
        feed.changed("turns");
    }
}
