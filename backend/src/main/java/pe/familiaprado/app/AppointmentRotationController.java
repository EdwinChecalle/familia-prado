package pe.familiaprado.app;

import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.HttpStatus;

@RestController
@RequestMapping("/api/appointments/rotation")
public class AppointmentRotationController {
    private final AppointmentRotation rotation;
    private final ChangeFeed feed;
    public AppointmentRotationController(JdbcTemplate db,ChangeFeed feed){rotation=new AppointmentRotation(db);this.feed=feed;}
    @GetMapping @Transactional
    public AppointmentRotation.View view(){Session.current();return rotation.view();}
    public record Configuration(List<UUID> memberIds,UUID nextMemberId,long revision) {}
    @PatchMapping @Transactional @ResponseStatus(HttpStatus.NO_CONTENT)
    public void configure(@RequestBody Configuration r){Session.current().adminOnly();rotation.configure(r.memberIds(),r.nextMemberId(),r.revision());feed.changed("appointments");}
    public record Skip(long revision,String reason) {}
    @PostMapping("/skip") @Transactional @ResponseStatus(HttpStatus.NO_CONTENT)
    public void skip(@RequestBody Skip r){Session.current().adminOnly();rotation.skip(r.revision(),r.reason());feed.changed("appointments");}
}
