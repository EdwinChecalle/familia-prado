package pe.familiaprado.app;

import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.server.ResponseStatusException;

public record Session(UUID userId, String email, String role, UUID memberId) {
    public static Session current() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof Session session)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Debes iniciar sesión");
        }
        return session;
    }
    public boolean isAdmin() { return "ADMIN".equals(role); }
    public void adminOnly() {
        if (!isAdmin()) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Solo administración familiar");
    }
    public void ownsOrAdmin(UUID member) {
        if (!isAdmin() && (memberId == null || !memberId.equals(member)))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "La operación corresponde a otra persona");
    }
}
