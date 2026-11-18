package pe.familiaprado.app;

import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/push")
public class PushController {
    private static final Pattern TOKEN=Pattern.compile("^[A-Za-z0-9_:\\-]{20,4096}$");
    private final JdbcTemplate db;
    private final PushQueue queue;
    private final PushTransport transport;
    public PushController(JdbcTemplate db,PushQueue queue,PushTransport transport) {
        this.db=db;this.queue=queue;this.transport=transport;
    }
    public record Device(String token,String platform,boolean spokenSound) {}
    public record Remove(String token) {}

    @GetMapping("/status")
    public Map<String,Object> status() {
        return Map.of("configured",transport.isEnabled());
    }
    @PostMapping("/devices") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void register(@RequestBody Device r) {
        validate(r.token());
        if (r.platform()==null || !r.platform().matches("ANDROID|IOS"))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Plataforma inválida");
        // Reasigna de manera segura al usuario autenticado actual. Un logout
        // desde otro dispositivo no permite gestionar tokens de otro usuario.
        db.update("""
            INSERT INTO push_devices(token,user_id,platform,spoken_sound)
            VALUES(?,?,?,?)
            ON CONFLICT(token) DO UPDATE SET user_id=EXCLUDED.user_id,
               platform=EXCLUDED.platform,spoken_sound=EXCLUDED.spoken_sound,
               last_seen_at=NOW()
            """,r.token(),Session.current().userId(),r.platform(),r.spokenSound());
    }
    @PostMapping("/devices/remove") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void remove(@RequestBody Remove r) {
        validate(r.token());
        db.update("DELETE FROM push_devices WHERE token=? AND user_id=?",
            r.token(),Session.current().userId());
    }
    private static void validate(String token) {
        if (token==null || !TOKEN.matcher(token).matches())
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Token de dispositivo inválido");
    }
    @PostMapping("/test") @ResponseStatus(HttpStatus.ACCEPTED)
    public Map<String,String> test() {
        UUID user=Session.current().userId();
        if (!transport.isEnabled())
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Configura Firebase en Spring Boot");
        // Límite por cuenta para evitar inundación de notificaciones de prueba.
        Integer count=db.queryForObject("""
            SELECT COUNT(*) FROM push_outbox
            WHERE recipient_user_id=? AND event_type='TEST'
              AND created_at>NOW()-INTERVAL '1 hour'
            """,Integer.class,user);
        if (count!=null && count>=3)
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"Máximo 3 pruebas por hora");
        queue.enqueue(user,"TEST",UUID.randomUUID(),"NOW",
            java.time.Instant.now(),java.time.Instant.now().plusSeconds(300));
        return Map.of("status","queued");
    }
}
