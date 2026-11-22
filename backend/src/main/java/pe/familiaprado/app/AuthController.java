package pe.familiaprado.app;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
public class AuthController {
    private final AuthService service;
    public AuthController(AuthService service) { this.service=service; }
    public record Credentials(@Email @NotBlank String email,@NotBlank String password) {}
    public record ChangePassword(@NotBlank String currentPassword,@NotBlank String newPassword) {}
    public record NewAccount(@Email @NotBlank String email,@NotBlank String initialPassword,UUID memberId) {}
    @GetMapping("/ping") public Map<String,String> ping() { return Map.of("status","ok"); }
    @PostMapping("/auth/login") public Map<String,Object> login(@Valid @RequestBody Credentials r) {
        return service.login(r.email(),r.password());
    }
    @PostMapping("/auth/logout") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@RequestHeader("Authorization") String header) {
        if (header.startsWith("Bearer ")) service.logout(header.substring(7).trim());
    }
    @GetMapping("/auth/me") public Session me() { return Session.current(); }
    @PostMapping("/auth/change-password") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void change(@Valid @RequestBody ChangePassword r) { service.changePassword(r.currentPassword(),r.newPassword()); }
    @PostMapping("/admin/accounts") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,UUID> provision(@Valid @RequestBody NewAccount r) {
        return Map.of("id",service.provision(r.email(),r.initialPassword(),r.memberId()));
    }

    @GetMapping("/admin/accounts")
    public java.util.List<AuthService.FamilyAccount> accounts() { return service.familyAccounts(); }
    public record ResetPassword(@NotBlank String newPassword) {}
    @PostMapping("/admin/accounts/{id}/reset-password") @ResponseStatus(HttpStatus.NO_CONTENT)
    public void resetPassword(@PathVariable UUID id, @Valid @RequestBody ResetPassword r) {
        service.resetMemberPassword(id,r.newPassword());
    }
}
