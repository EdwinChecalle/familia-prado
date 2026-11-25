package pe.familiaprado.app;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/fund/collections")
public class CollectionReportController {
    private static final ZoneId LIMA = ZoneId.of("America/Lima");
    private final JdbcTemplate db;
    public CollectionReportController(JdbcTemplate db) { this.db=db; }
    public record CollectionInfo(String concept, BigDecimal amountPerMember, Instant createdAt) {}
    public record MemberAmount(String name, BigDecimal expected, BigDecimal verified, BigDecimal submitted, BigDecimal pending) {}
    public record ExpenseLine(String concept, BigDecimal amount, Instant createdAt, Instant approvedAt) {}
    public record Report(CollectionInfo collection, Instant generatedAt, Instant from, Instant to,
        String period, BigDecimal expected, BigDecimal verified, BigDecimal pending, BigDecimal submitted,
        BigDecimal opening, BigDecimal periodIncome, BigDecimal periodExpenses, BigDecimal closing,
        BigDecimal currentAvailable, List<MemberAmount> members, List<ExpenseLine> expenses) {}
    private BigDecimal totalBefore(String kind, Instant time) {
        String sql = kind.equals("IN") ?
            "SELECT COALESCE(SUM(amount),0) FROM contributions WHERE status='VERIFIED' AND reviewed_at < ?" :
            "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE status='APPROVED' AND reviewed_at < ?";
        return db.queryForObject(sql, BigDecimal.class, Timestamp.from(time));
    }
    @GetMapping("/{id}/image-report")
    @Transactional(readOnly=true, isolation=Isolation.REPEATABLE_READ)
    public Report report(@PathVariable UUID id, @RequestParam(defaultValue="CURRENT") String period,
                         @RequestParam(required=false) LocalDate from, @RequestParam(required=false) LocalDate to) {
        Session.current();
        Instant now=db.queryForObject("SELECT transaction_timestamp()", (r,n)->r.getTimestamp(1).toInstant());
        var rows=db.query("SELECT concept,amount_per_member,created_at FROM collections WHERE id=?",
            (r,n)->new CollectionInfo(r.getString(1),r.getBigDecimal(2),r.getTimestamp(3).toInstant()),id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Colecta no encontrada");
        var selected=rows.getFirst();
        var earlier=db.query("SELECT created_at FROM collections WHERE (created_at,id)<(?,?) ORDER BY created_at DESC,id DESC LIMIT 1",
            (r,n)->r.getTimestamp(1).toInstant(),Timestamp.from(selected.createdAt()),id);
        Instant start,end;
        switch(period) {
            case "CURRENT" -> { start=selected.createdAt(); end=now; }
            case "BETWEEN", "PREVIOUS_TO_NOW" -> {
                if(earlier.isEmpty()) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"No existe una colecta anterior a la seleccionada");
                start=earlier.getFirst(); end=period.equals("BETWEEN")?selected.createdAt():now;
            }
            case "CUSTOM" -> {
                if(from==null||to==null||from.isAfter(to)||to.isAfter(LocalDate.ofInstant(now,LIMA))||java.time.temporal.ChronoUnit.DAYS.between(from,to)>366)
                    throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Elige un periodo válido de hasta 367 días, no futuro");
                start=from.atStartOfDay(LIMA).toInstant(); end=to.plusDays(1).atStartOfDay(LIMA).toInstant();
                if(end.isAfter(now)) end=now;
            }
            default -> throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Periodo desconocido");
        }
        // Existing schema has no historical membership snapshot. Include active members and anyone with a contribution in this collection.
        var members=db.query("""
            SELECT f.display_name, COALESCE(SUM(p.amount) FILTER (WHERE p.status='VERIFIED'),0) AS verified,
              COALESCE(SUM(p.amount) FILTER (WHERE p.status='SUBMITTED'),0) AS submitted
            FROM family_members f LEFT JOIN contributions p ON p.member_id=f.id AND p.collection_id=?
            WHERE f.active OR p.id IS NOT NULL
            GROUP BY f.id,f.display_name,f.rotation_position ORDER BY f.rotation_position
            """,(r,n)->{
                var v=r.getBigDecimal("verified"); var sub=r.getBigDecimal("submitted");
                return new MemberAmount(r.getString("display_name"),selected.amountPerMember(),v,sub,
                    selected.amountPerMember().subtract(v).max(BigDecimal.ZERO));
            },id);
        BigDecimal expected=selected.amountPerMember().multiply(BigDecimal.valueOf(members.size()));
        BigDecimal received=members.stream().map(MemberAmount::verified).reduce(BigDecimal.ZERO,BigDecimal::add);
        BigDecimal waiting=members.stream().map(MemberAmount::pending).reduce(BigDecimal.ZERO,BigDecimal::add);
        BigDecimal submitted=members.stream().map(MemberAmount::submitted).reduce(BigDecimal.ZERO,BigDecimal::add);
        BigDecimal beforeIn=totalBefore("IN",start),beforeOut=totalBefore("OUT",start);
        BigDecimal endIn=totalBefore("IN",end),endOut=totalBefore("OUT",end);
        var expenses=db.query("""
            SELECT concept,amount,created_at,reviewed_at FROM expenses
            WHERE status='APPROVED' AND reviewed_at>=? AND reviewed_at<? ORDER BY reviewed_at,id
            """,(r,n)->new ExpenseLine(r.getString(1),r.getBigDecimal(2),r.getTimestamp(3).toInstant(),r.getTimestamp(4).toInstant()),Timestamp.from(start),Timestamp.from(end));
        return new Report(selected,now,start,end,period,expected,received,waiting,submitted,
            beforeIn.subtract(beforeOut),endIn.subtract(beforeIn),endOut.subtract(beforeOut),endIn.subtract(endOut),
            totalBefore("IN",now).subtract(totalBefore("OUT",now)),members,expenses);
    }
}
