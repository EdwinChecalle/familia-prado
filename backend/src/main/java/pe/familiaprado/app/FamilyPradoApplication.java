package pe.familiaprado.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class FamilyPradoApplication {
    public static void main(String[] args) { SpringApplication.run(FamilyPradoApplication.class, args); }
}
