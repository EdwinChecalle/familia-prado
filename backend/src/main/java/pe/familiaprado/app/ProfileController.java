package pe.familiaprado.app;

import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProfileController {
    private final JdbcTemplate db;
    ProfileController(JdbcTemplate db){this.db=db;}
    @GetMapping("/api/profile")
    public Map<String,Object> profile() {
        Session user=Session.current();
        String name=user.isAdmin()?"Administrador":db.queryForObject(
            "SELECT display_name FROM family_members WHERE id=?",String.class,user.memberId());
        return Map.of("displayName",name,"role",user.role(),"isAdmin",user.isAdmin());
    }
}
