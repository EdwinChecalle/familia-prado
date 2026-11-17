package pe.familiaprado.app;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class AlertWordsTest {
  @Test void remindersArePersonalAndDiscreet() {
    assertTrue(AlertWords.weekNow("Carlos").contains("Papá Isidro"));
    assertTrue(AlertWords.weekNext("Olga").contains("próxima semana"));
    assertTrue(AlertWords.appointmentTomorrow("Jorge").contains("mañana"));
    assertTrue(AlertWords.appointmentToday("Olga").contains("hoy"));
    assertTrue(AlertWords.appointmentSoon("Carmen").contains("unas horas"));
    assertFalse(AlertWords.appointmentTomorrow("Carlos").contains("diagnóstico"));
  }
}
