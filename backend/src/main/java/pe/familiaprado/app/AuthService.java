package pe.familiaprado.app;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AuthService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private final JdbcTemplate db;
    private final PasswordEncoder passwordEncoder;
    public AuthService(JdbcTemplate db, PasswordEncoder passwordEncoder) {
        this.db=db; this.passwordEncoder=passwordEncoder;
    }
    public static String hashToken(String token) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) { throw new IllegalStateException("SHA-256 unavailable",e); }
    }
    private static String norm(String email) { return email.strip().toLowerCase(Locale.ROOT); }

    @Transactional
    public Map<String,Object> login(String email,String password) {
        var rows=db.query("SELECT id,member_id,role,password_hash FROM app_users WHERE email=?",
            (r,n)->new LoginRow(r.getObject("id",UUID.class),r.getObject("member_id",UUID.class),
                r.getString("role"),r.getString("password_hash")),norm(email));
        if (rows.isEmpty() || !passwordEncoder.matches(password,rows.getFirst().passwordHash()))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"Correo o contraseña incorrectos");
        var user=rows.getFirst();
        byte[] bytes=new byte[32]; RANDOM.nextBytes(bytes);
        String token=Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Instant expires=Instant.now().plusSeconds(14L*24*3600);
        db.update("INSERT INTO login_tokens(token_hash,user_id,expires_at) VALUES (?,?,?)",
            hashToken(token),user.id(),java.sql.Timestamp.from(expires));
        return Map.of("token",token,"expiresAt",expires.toString());
    }
    private record LoginRow(UUID id,UUID memberId,String role,String passwordHash) {}

    @Transactional
    public void logout(String token) {
        db.update("UPDATE login_tokens SET revoked_at=NOW() WHERE token_hash=? AND revoked_at IS NULL",
            hashToken(token));
    }
    @Transactional
    public void changePassword(String previous,String next) {
        Session user=Session.current();
        if (next==null || next.length()<8 || next.length()>100)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"La nueva contraseña debe tener 8 a 100 caracteres");
        String original=db.queryForObject("SELECT password_hash FROM app_users WHERE id=?",String.class,user.userId());
        if (!passwordEncoder.matches(previous,original))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Contraseña actual incorrecta");
        db.update("UPDATE app_users SET password_hash=? WHERE id=?",passwordEncoder.encode(next),user.userId());
        db.update("UPDATE login_tokens SET revoked_at=NOW() WHERE user_id=? AND revoked_at IS NULL",user.userId());
    }
    @Transactional
    public UUID provision(String email,String password,UUID memberId) {
        Session.current().adminOnly();
        if (password==null || password.length()<8 || password.length()>100)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Contraseña inicial de 8 a 100 caracteres");
        Integer count=db.queryForObject("SELECT COUNT(*) FROM family_members WHERE id=? AND active=true",Integer.class,memberId);
        if (count==null || count==0) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Miembro no encontrado");
        UUID id=UUID.randomUUID();
        db.update("INSERT INTO app_users(id,email,password_hash,role,member_id) VALUES(?,?,?,'MEMBER',?)",
            id,norm(email),passwordEncoder.encode(password),memberId);
        return id;
    }


    /** Solo administración: consultar los accesos ya creados sin exponer hashes. */
    public record FamilyAccount(UUID id, String email, UUID memberId) {}
    public java.util.List<FamilyAccount> familyAccounts() {
        Session.current().adminOnly();
        return db.query("SELECT id,email,member_id FROM app_users WHERE role='MEMBER' ORDER BY created_at,id",
            (r,n)->new FamilyAccount(r.getObject("id",UUID.class),r.getString("email"),
                r.getObject("member_id",UUID.class)));
    }

    /** Restablecimiento asistido: invalida inmediatamente todos los tokens previos. */
    @Transactional
    public void resetMemberPassword(UUID target, String newPassword) {
        Session.current().adminOnly();
        if (newPassword==null || newPassword.length()<8 || newPassword.length()>100)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Contraseña de 8 a 100 caracteres");
        var matches=db.query("SELECT id FROM app_users WHERE id=? AND role='MEMBER' FOR UPDATE",
            (r,n)->r.getObject(1,UUID.class),target);
        if (matches.isEmpty())
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Cuenta familiar no encontrada");
        db.update("UPDATE app_users SET password_hash=? WHERE id=?",
            passwordEncoder.encode(newPassword),target);
        db.update("UPDATE login_tokens SET revoked_at=NOW() WHERE user_id=? AND revoked_at IS NULL",target);
    }

    @Bean ApplicationRunner bootstrapAdmin(@Value("${BOOTSTRAP_ADMIN_EMAIL:}") String email,
                                            @Value("${BOOTSTRAP_ADMIN_PASSWORD:}") String pass) {
        return args -> {
            Integer count=db.queryForObject("SELECT COUNT(*) FROM app_users WHERE role='ADMIN'",Integer.class);
            if (count != null && count>0) return;
            if (email.isBlank() || pass.length()<12 || pass.contains("CAMBIAR_"))
                throw new IllegalStateException("Configura BOOTSTRAP_ADMIN_EMAIL y una contraseña segura (mínimo 12 caracteres)");
            db.update("INSERT INTO app_users(id,email,password_hash,role) VALUES(?,?,?,'ADMIN')",
                UUID.randomUUID(),norm(email),passwordEncoder.encode(pass));
        };
    }
}
