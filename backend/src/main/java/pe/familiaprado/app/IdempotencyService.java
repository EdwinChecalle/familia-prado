package pe.familiaprado.app;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.UUID;
import java.util.function.Supplier;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

/** Clave única por usuario. La reserva, la escritura y su respuesta se confirman en UNA transacción. */
@Service
public class IdempotencyService {
    private final JdbcTemplate db;
    private final TransactionTemplate transactions;
    public IdempotencyService(JdbcTemplate db, PlatformTransactionManager manager) {
        this.db=db;
        this.transactions=new TransactionTemplate(manager);
    }
    static String normalize(String key) {
        if (key==null || key.isBlank()) return null; // Clientes anteriores: sin protección de reenvío.
        try { return UUID.fromString(key.strip()).toString(); }
        catch (IllegalArgumentException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Idempotency-Key debe ser UUID");
        }
    }
    static String hash(String text) {
        try {
            byte[] digest=MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception ex) { throw new IllegalStateException(ex); }
    }
    private record Saved(String route,String fingerprint,UUID resultId) {}
    public UUID run(String key, String route, Object request, Supplier<UUID> operation) {
        String normalized=normalize(key);
        if (normalized==null) return operation.get();
        UUID user=Session.current().userId();
        String fingerprint=hash(route+"\n"+String.valueOf(request));
        return transactions.execute(tx -> {
            int inserted=db.update("""
                INSERT INTO idempotency_requests(user_id,request_key,route,fingerprint)
                VALUES(?,?,?,?) ON CONFLICT(user_id,request_key) DO NOTHING
                """, user,normalized,route,fingerprint);
            if (inserted==0) {
                Saved saved=db.queryForObject("""
                    SELECT route,fingerprint,result_id FROM idempotency_requests
                    WHERE user_id=? AND request_key=?
                    """,(r,n)->new Saved(r.getString(1),r.getString(2),r.getObject(3,UUID.class)),
                    user,normalized);
                if (saved==null || !route.equals(saved.route()) || !fingerprint.equals(saved.fingerprint()))
                    throw new ResponseStatusException(HttpStatus.CONFLICT,"Clave de operación reutilizada con datos diferentes");
                if (saved.resultId()==null)
                    throw new ResponseStatusException(HttpStatus.CONFLICT,"Operación en curso; vuelve a consultar");
                return saved.resultId();
            }
            UUID result=operation.get();
            db.update("UPDATE idempotency_requests SET result_id=? WHERE user_id=? AND request_key=?",
                result,user,normalized);
            return result;
        });
    }
}
