package pe.familiaprado.app;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/fund")
public class FundController {
    private final FundService s;
    public FundController(FundService s) {this.s=s;}
    @GetMapping("/summary") public FundService.Summary summary(){ return s.summary(); }
    @GetMapping("/collections") public List<FundService.Collection> collections(){return s.collections();}
    public record NewCollection(String concept,BigDecimal amountPerMember,LocalDate dueDate) {}
    @PostMapping("/collections") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> create(@RequestBody NewCollection r){
        return Map.of("id",s.newCollection(r.concept(),r.amountPerMember(),r.dueDate()));
    }
    @GetMapping("/collections/{id}/contributions")
    public List<FundService.Payment> contributions(@PathVariable UUID id){ return s.payments(id); }
    public record NewContribution(UUID memberId,BigDecimal amount,String paymentMethod,String paymentReference) {}
    @PostMapping("/collections/{id}/contributions") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> contribute(@PathVariable UUID id,@RequestBody NewContribution r){
        return Map.of("id",s.submit(id,r.memberId(),r.amount(),r.paymentMethod(),r.paymentReference()));
    }
    public record Review(boolean accept) {}
    @PostMapping("/contributions/{id}/review") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void review(@PathVariable UUID id,@RequestBody Review r){s.reviewPayment(id,r.accept());}
    @GetMapping("/expenses") public List<FundService.Expense> expenses(){return s.expenses();}
    public record NewExpense(String concept,BigDecimal amount,String receiptReference) {}
    @PostMapping("/expenses") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> expense(@RequestBody NewExpense r){
        return Map.of("id",s.requestExpense(r.concept(),r.amount(),r.receiptReference()));
    }
    @PostMapping("/expenses/{id}/review") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void approve(@PathVariable UUID id,@RequestBody Review r){s.reviewExpense(id,r.accept());}
}
