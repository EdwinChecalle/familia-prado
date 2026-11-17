package pe.familiaprado.app;

import java.math.BigDecimal;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/alerts")
public class AlertsController {
    private static final ZoneId LIMA = ZoneId.of("America/Lima");
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("dd/MM/yyyy");
    private final JdbcTemplate db;
    private final RotationService rotation;
    public AlertsController(JdbcTemplate db, RotationService rotation) {
        this.db = db; this.rotation = rotation;
    }
    public record Alert(String id,String category,String title,String message,
                        String voiceText,boolean voiceRecommended,boolean read) {}
    private record Draft(String id,String category,String title,String message,
                         String voiceText,boolean voiceRecommended) {}

    @GetMapping
    public List<Alert> alerts() {
        Session user = Session.current();
        List<Draft> drafts = new ArrayList<>();
        LocalDate today = LocalDate.now(LIMA);
        Instant now = Instant.now();
        if (user.memberId() != null) {
            String name = db.queryForObject("SELECT display_name FROM family_members WHERE id=?",
                String.class,user.memberId());
            // Accepted swaps are respected by computing ownership on the server.
            if (rotation.config().confirmed()) {
                LocalDate thisMonday = RotationMath.monday(today);
                for (int offset=0;offset<=1;offset++) {
                    LocalDate monday=thisMonday.plusWeeks(offset);
                    if (rotation.owner(monday).id().equals(user.memberId())) {
                        boolean current=offset==0;
                        String voice=current?AlertWords.weekNow(name):AlertWords.weekNext(name);
                        String message=current
                            ? "Esta semana eres responsable de las tres comidas diarias de Papá Isidro."
                            : "La semana que comienza el " + DATE.format(monday)
                              + " te toca preparar las comidas de Papá Isidro.";
                        drafts.add(new Draft("turn-"+monday+"-"+user.memberId(), "TURN",
                            current?"Tu semana de comidas":"La próxima semana te toca",message,voice,true));
                    }
                }
            }
            db.query("""
                SELECT id,appointment_at FROM appointments
                WHERE responsible_member_id=? AND status IN ('PLANNED','CONFIRMED')
                  AND appointment_at >= NOW() AND appointment_at < NOW() + INTERVAL '24 hours'
                ORDER BY appointment_at LIMIT 20
                """,rs -> {
                UUID id=rs.getObject("id",UUID.class);
                Instant at=rs.getTimestamp("appointment_at").toInstant();
                boolean soon=Duration.between(now,at).toMinutes()<=180;
                boolean sameDay=at.atZone(LIMA).toLocalDate().equals(today);
                String stage=soon?"soon":sameDay?"today":"day";
                String when=at.atZone(LIMA).format(DateTimeFormatter.ofPattern("dd/MM HH:mm"));
                drafts.add(new Draft("appointment-"+id+"-"+stage,"APPOINTMENT",
                    soon?"Cita médica en unas horas":sameDay?"Cita médica hoy":"Cita médica mañana",
                    "Te toca acompañar a Papá Isidro el " + when + ". Revisa Citas para conocer los detalles.",
                    soon?AlertWords.appointmentSoon(name):sameDay?AlertWords.appointmentToday(name):
                      AlertWords.appointmentTomorrow(name),true));
            },user.memberId());
            db.query("""
                SELECT c.id,c.concept,c.amount_per_member,
                       COALESCE((SELECT SUM(p.amount) FROM contributions p
                         WHERE p.collection_id=c.id AND p.member_id=? AND p.status<>'REJECTED'),0) AS submitted
                FROM collections c WHERE c.created_at > NOW() - INTERVAL '14 days'
                ORDER BY c.created_at DESC LIMIT 20
                """,rs -> {
                BigDecimal remaining=rs.getBigDecimal("amount_per_member").subtract(rs.getBigDecimal("submitted"));
                if(remaining.signum()>0) {
                    String amount=remaining.stripTrailingZeros().toPlainString();
                    drafts.add(new Draft("collection-"+rs.getObject("id",UUID.class),"COLLECTION",
                        "Colecta familiar", "Se abrió una colecta para " + rs.getString("concept")
                        + ". Tu aporte pendiente es S/ " + amount + ".",
                        "Se abrió una colecta familiar. Revisa tu aporte en Familia Prado.",false));
                }
            },user.memberId());
        } else if (user.isAdmin()) {
            Integer pending=db.queryForObject("""
                SELECT (SELECT COUNT(*) FROM contributions WHERE status='SUBMITTED')
                     + (SELECT COUNT(*) FROM expenses WHERE status='REQUESTED')
                """,Integer.class);
            if (pending != null && pending>0)
                drafts.add(new Draft("fund-approvals","FUND","Operaciones pendientes",
                    "Hay " + pending + " operaciones de caja por revisar.",
                    "Hay operaciones pendientes de revisión en la caja familiar.",false));
        }
        Set<String> reads=new HashSet<>(db.query("SELECT alert_key FROM user_alert_reads WHERE user_id=?",
            (rs,index)->rs.getString(1),user.userId()));
        return drafts.stream().map(a->new Alert(a.id(),a.category(),a.title(),a.message(),
            a.voiceText(),a.voiceRecommended(),reads.contains(a.id()))).toList();
    }

    @PostMapping("/{id}/read") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void read(@PathVariable String id) {
        if(id.length()>160||!id.matches("[a-zA-Z0-9_-]+"))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Aviso incorrecto");
        if(alerts().stream().noneMatch(a->a.id().equals(id)))
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Aviso no disponible");
        db.update("INSERT INTO user_alert_reads(user_id,alert_key) VALUES(?,?) ON CONFLICT DO NOTHING",
            Session.current().userId(),id);
    }
}
