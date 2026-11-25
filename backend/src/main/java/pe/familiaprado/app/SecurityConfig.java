package pe.familiaprado.app;

import jakarta.servlet.DispatcherType;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
public class SecurityConfig {
    @Bean PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(12); }
    @Bean SecurityFilterChain securityFilterChain(HttpSecurity http, TokenFilter tokens) throws Exception {
        return http.csrf(csrf -> csrf.disable())
            .httpBasic(basic -> basic.disable())
            .formLogin(form -> form.disable())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            // Una sesión ausente, caducada o revocada es 401; los permisos insuficientes son 403.
            .exceptionHandling(e -> e.authenticationEntryPoint((request,response,exception) ->
                response.sendError(jakarta.servlet.http.HttpServletResponse.SC_UNAUTHORIZED)))
            .authorizeHttpRequests(a -> a
                .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                .requestMatchers(HttpMethod.OPTIONS, "/**").denyAll()
                .requestMatchers("/api/ping", "/api/auth/login", "/actuator/health").permitAll()
                .anyRequest().authenticated())
            .addFilterBefore(tokens, UsernamePasswordAuthenticationFilter.class)
            .build();
    }
}
