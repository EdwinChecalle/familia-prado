package pe.familiaprado.app;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class TokenFilter extends OncePerRequestFilter {
    private final JdbcTemplate db;
    public TokenFilter(JdbcTemplate db) { this.db=db; }

    @Override protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        try {
            String header=req.getHeader("Authorization");
            if (header!=null && header.startsWith("Bearer ")) {
                String token=header.substring(7).trim();
                if (token.length()>=32 && token.length()<=256) {
                    var sessions=db.query("""
                        SELECT u.id,u.email,u.role,u.member_id FROM login_tokens t
                        JOIN app_users u ON u.id=t.user_id
                        WHERE t.token_hash=? AND t.revoked_at IS NULL AND t.expires_at>NOW()
                        """, (rs,n)->new Session(rs.getObject("id",UUID.class),rs.getString("email"),
                            rs.getString("role"),rs.getObject("member_id",UUID.class)), AuthService.hashToken(token));
                    if (!sessions.isEmpty()) {
                        Session s=sessions.getFirst();
                        var auth=new UsernamePasswordAuthenticationToken(s,null,
                            java.util.List.of(new SimpleGrantedAuthority("ROLE_"+s.role())));
                        SecurityContextHolder.getContext().setAuthentication(auth);
                    }
                }
            }
            chain.doFilter(req,res);
        } finally { SecurityContextHolder.clearContext(); }
    }
}
