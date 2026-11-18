package pe.familiaprado.app;

import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@Component
public class CareAccess {
    private final JdbcTemplate db;
    CareAccess(JdbcTemplate db) {this.db=db;}
    public boolean allowed(Session s) {
        if(s.isAdmin()) return true;
        if(s.memberId()==null) return false;
        Integer count=db.queryForObject("SELECT COUNT(*) FROM care_access WHERE member_id=?",Integer.class,s.memberId());
        return count!=null && count>0;
    }
    public void require() {
        if(!allowed(Session.current())) throw new ResponseStatusException(HttpStatus.FORBIDDEN,
            "Acceso médico restringido. Solicita autorización al administrador familiar.");
    }
}

@RestController
@RequestMapping("/api/care/access")
class CareAccessController {
    private final JdbcTemplate db;
    private final CareAccess access;
    CareAccessController(JdbcTemplate db,CareAccess access){this.db=db;this.access=access;}
    @GetMapping("/me") public Map<String,Boolean> me(){ return Map.of("allowed",access.allowed(Session.current()),"admin",Session.current().isAdmin()); }
    @GetMapping public List<Map<String,Object>> members() {
        Session.current().adminOnly();
        return db.query("""
          SELECT m.id,m.display_name,(a.member_id IS NOT NULL) allowed FROM family_members m
          LEFT JOIN care_access a ON a.member_id=m.id ORDER BY m.rotation_position
          """,(r,i)->Map.of("memberId",r.getObject(1,UUID.class),"displayName",r.getString(2),"allowed",r.getBoolean(3)));
    }
    record Grant(boolean allowed){}
    @PutMapping("/{memberId}") @org.springframework.web.bind.annotation.ResponseStatus(HttpStatus.NO_CONTENT)
    public void set(@PathVariable UUID memberId,@RequestBody Grant grant){
        Session.current().adminOnly();
        Integer exists=db.queryForObject("SELECT COUNT(*) FROM family_members WHERE id=? AND active=true",Integer.class,memberId);
        if(exists==null || exists==0) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Familiar no encontrado");
        if(grant.allowed()) db.update("""
            INSERT INTO care_access(member_id,granted_by) VALUES (?,?)
            ON CONFLICT(member_id) DO UPDATE SET granted_by=EXCLUDED.granted_by,granted_at=NOW()
            """,memberId,Session.current().userId());
        else db.update("DELETE FROM care_access WHERE member_id=?",memberId);
    }
}
