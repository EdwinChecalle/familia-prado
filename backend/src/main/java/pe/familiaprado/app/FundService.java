package pe.familiaprado.app;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class FundService {
    private final JdbcTemplate db;
    public FundService(JdbcTemplate db){this.db=db;}
    public record Collection(UUID id,String concept,BigDecimal amountPerMember,LocalDate dueDate) {}
    public record Payment(UUID id,UUID collectionId,UUID memberId,BigDecimal amount,String method,String reference,String status) {}
    public record Expense(UUID id,String concept,BigDecimal amount,String receiptReference,String status) {}
    public record Summary(BigDecimal collected,BigDecimal spent,BigDecimal available) {}
    private static void validAmount(BigDecimal v) {
        if(v==null||v.signum()<=0||v.scale()>2||v.compareTo(new BigDecimal("99999999"))>0)
          throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"El importe debe ser positivo y tener máximo dos decimales");
    }
    public Summary summary() {
        BigDecimal in=db.queryForObject("SELECT COALESCE(SUM(amount),0) FROM contributions WHERE status='VERIFIED'",BigDecimal.class);
        BigDecimal out=db.queryForObject("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE status='APPROVED'",BigDecimal.class);
        return new Summary(in,out,in.subtract(out));
    }
    public List<Collection> collections() {
        return db.query("SELECT id,concept,amount_per_member,due_date FROM collections ORDER BY created_at DESC",
          (r,n)->new Collection(r.getObject("id",UUID.class),r.getString("concept"),r.getBigDecimal("amount_per_member"),r.getObject("due_date",LocalDate.class)));
    }
    @Transactional public UUID newCollection(String concept, BigDecimal amount, LocalDate due) {
        Session.current().adminOnly(); validAmount(amount);
        if(concept==null||concept.isBlank()||concept.length()>200)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Indica el concepto de la colecta");
        UUID id=UUID.randomUUID();
        db.update("INSERT INTO collections(id,concept,amount_per_member,due_date,created_by) VALUES(?,?,?,?,?)",
          id,concept.strip(),amount,due==null?null:java.sql.Date.valueOf(due),Session.current().userId());
        return id;
    }
    public List<Payment> payments(UUID collection) {
        return db.query("""
          SELECT id,collection_id,member_id,amount,payment_method,payment_reference,status
          FROM contributions WHERE collection_id=? ORDER BY created_at DESC
          """,(r,n)->new Payment(r.getObject("id",UUID.class),r.getObject("collection_id",UUID.class),
            r.getObject("member_id",UUID.class),r.getBigDecimal("amount"),r.getString("payment_method"),
            r.getString("payment_reference"),r.getString("status")),collection);
    }
    @Transactional public UUID submit(UUID collection,UUID member,BigDecimal amount,String method,String reference) {
        validAmount(amount); Session.current().ownsOrAdmin(member);
        if(method==null||!List.of("YAPE","PLIN","TRANSFER","CASH").contains(method))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Forma de pago desconocida");
        if(reference!=null && reference.length()>120) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Referencia muy larga");
        // Serialize submissions for the same collection to prevent concurrent overpayment.
        var max=db.query("SELECT amount_per_member FROM collections WHERE id=? FOR UPDATE",
            (r,n)->r.getBigDecimal(1),collection);
        if(max.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Colecta no encontrada");
        BigDecimal total=db.queryForObject("""
          SELECT COALESCE(SUM(amount),0) FROM contributions
          WHERE collection_id=? AND member_id=? AND status <> 'REJECTED'
          """,BigDecimal.class,collection,member);
        if(!MoneyRules.canSubmitContribution(total,amount,max.getFirst()))
          throw new ResponseStatusException(HttpStatus.CONFLICT,"Los aportes superan lo solicitado a este familiar");
        UUID id=UUID.randomUUID();
        db.update("""
          INSERT INTO contributions(id,collection_id,member_id,amount,payment_method,payment_reference,status,submitted_by)
          VALUES(?,?,?,?,?,?,'SUBMITTED',?)
          """,id,collection,member,amount,method,reference,Session.current().userId());
        return id;
    }
    @Transactional public void reviewPayment(UUID id,boolean verify) {
        Session.current().adminOnly();
        db.queryForObject("SELECT id FROM family_fund_lock WHERE id=1 FOR UPDATE",Integer.class);
        var status=db.query("SELECT status FROM contributions WHERE id=? FOR UPDATE",(r,n)->r.getString(1),id);
        if(status.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Aporte no encontrado");
        if(!status.getFirst().equals("SUBMITTED")) throw new ResponseStatusException(HttpStatus.CONFLICT,"Aporte ya revisado");
        db.update("UPDATE contributions SET status=?,reviewed_by=?,reviewed_at=NOW() WHERE id=?",
          verify?"VERIFIED":"REJECTED",Session.current().userId(),id);
    }
    public List<Expense> expenses() {
        return db.query("SELECT id,concept,amount,receipt_reference,status FROM expenses ORDER BY created_at DESC",
          (r,n)->new Expense(r.getObject("id",UUID.class),r.getString("concept"),r.getBigDecimal("amount"),
            r.getString("receipt_reference"),r.getString("status")));
    }
    @Transactional public UUID requestExpense(String concept,BigDecimal amount,String receipt) {
        validAmount(amount);
        if(concept==null||concept.isBlank()||concept.length()>200 || (receipt!=null&&receipt.length()>250))
          throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Concepto o referencia incorrectos");
        UUID id=UUID.randomUUID();
        db.update("INSERT INTO expenses(id,concept,amount,receipt_reference,status,requested_by) VALUES(?,?,?,?,'REQUESTED',?)",
          id,concept.strip(),amount,receipt,Session.current().userId());
        return id;
    }
    @Transactional public void reviewExpense(UUID id,boolean approve) {
        Session.current().adminOnly();
        // One lock for every financial approval to protect against negative balances.
        db.queryForObject("SELECT id FROM family_fund_lock WHERE id=1 FOR UPDATE",Integer.class);
        var rows=db.query("SELECT status,amount FROM expenses WHERE id=? FOR UPDATE",
            (r,n)->Map.entry(r.getString(1),r.getBigDecimal(2)),id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Gasto no encontrado");
        if(!rows.getFirst().getKey().equals("REQUESTED"))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Gasto ya revisado");
        if(approve && !MoneyRules.canApproveExpense(summary().collected(),summary().spent(),rows.getFirst().getValue()))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"La caja no tiene dinero suficiente");
        db.update("UPDATE expenses SET status=?,reviewed_by=?,reviewed_at=NOW() WHERE id=?",
           approve?"APPROVED":"REJECTED",Session.current().userId(),id);
    }
}
