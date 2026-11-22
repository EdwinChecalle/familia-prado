package pe.familiaprado.app;

import java.math.BigDecimal;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/fund")
public class FundController {
    private final FundService s;
    private final IdempotencyService idem;
    public FundController(FundService s, IdempotencyService idem) {this.s=s;this.idem=idem;}
    @GetMapping("/summary") public FundService.Summary summary(){ return s.summary(); }
    @GetMapping("/report") public FundService.FundReport report(
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        return s.report(from,to);
    }
    @GetMapping("/collections") public List<FundService.Collection> collections(){return s.collections();}
    public record NewCollection(String concept,BigDecimal amountPerMember,LocalDate dueDate) {}
    @PostMapping("/collections") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> create(@RequestBody NewCollection r,
        @RequestHeader(value="Idempotency-Key",required=false) String key){
        return Map.of("id",idem.run(key,"fund.collections",r,
            ()->s.newCollection(r.concept(),r.amountPerMember(),r.dueDate())));
    }
    @GetMapping("/collections/{id}/contributions")
    public List<FundService.Payment> contributions(@PathVariable UUID id){ return s.payments(id); }
    public record NewContribution(UUID memberId,BigDecimal amount,String paymentMethod,String paymentReference) {}
    @PostMapping("/collections/{id}/contributions") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> contribute(@PathVariable UUID id,@RequestBody NewContribution r,
        @RequestHeader(value="Idempotency-Key",required=false) String key){
        return Map.of("id",idem.run(key,"fund.contributions:"+id,r,
            ()->s.submit(id,r.memberId(),r.amount(),r.paymentMethod(),r.paymentReference())));
    }
    public record Review(boolean accept) {}
    @PostMapping("/contributions/{id}/review") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void review(@PathVariable UUID id,@RequestBody Review r){s.reviewPayment(id,r.accept());}
    @GetMapping("/expenses") public List<FundService.Expense> expenses(){return s.expenses();}
    public record NewExpense(String concept,BigDecimal amount,String receiptReference) {}
    @PostMapping("/expenses") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> expense(@RequestBody NewExpense r,
        @RequestHeader(value="Idempotency-Key",required=false) String key){
        return Map.of("id",idem.run(key,"fund.expenses",r,
            ()->s.requestExpense(r.concept(),r.amount(),r.receiptReference())));
    }
    @PostMapping("/expenses/{id}/review") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void approve(@PathVariable UUID id,@RequestBody Review r){s.reviewExpense(id,r.accept());}
}
