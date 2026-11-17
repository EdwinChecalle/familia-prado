package pe.familiaprado.app;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class RotationController {
    private final RotationService s;
    RotationController(RotationService s) { this.s=s; }
    @GetMapping("/members") public List<RotationService.Member> members(){ return s.members(); }
    @GetMapping("/rotation") public RotationService.Config config(){ return s.config(); }
    public record SetRotation(LocalDate anchorMonday,List<UUID> memberIdsInOrder,UUID memberStarting) {}
    @PutMapping("/admin/rotation") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void configure(@RequestBody SetRotation r) {s.configure(r.anchorMonday(),r.memberIdsInOrder(),r.memberStarting());}
    @GetMapping("/turns") public List<RotationService.Week> turns(
            @RequestParam(defaultValue="2026-11-16") LocalDate from,@RequestParam(defaultValue="8") int weeks) {
        return s.weeks(from,weeks);
    }
    @GetMapping("/turns/{monday}/meals") public List<RotationService.Meal> meals(@PathVariable LocalDate monday) {
        return s.meals(monday);
    }
    public record ChangeMeal(LocalDate date,String meal,boolean completed) {}
    @PutMapping("/turns/{monday}/meals") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void meal(@PathVariable LocalDate monday,@RequestBody ChangeMeal r) {
        s.checkMeal(monday,r.date(),r.meal(),r.completed());
    }
    @GetMapping("/swaps") public List<RotationService.Swap> swaps(){ return s.swaps(); }
    public record NewSwap(LocalDate firstMonday,LocalDate secondMonday) {}
    @PostMapping("/swaps") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> requestSwap(@RequestBody NewSwap r){
        return Map.of("id",s.requestSwap(r.firstMonday(),r.secondMonday()));
    }
    public record Decision(boolean accept) {}
    @PostMapping("/swaps/{id}/decision") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void decide(@PathVariable UUID id,@RequestBody Decision d){s.decideSwap(id,d.accept());}
}
