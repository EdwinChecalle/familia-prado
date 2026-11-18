package pe.familiaprado.app;
import static org.junit.jupiter.api.Assertions.*;
import java.math.BigDecimal;
import java.time.*;
import org.junit.jupiter.api.Test;
class CareRulesTest {
  @Test void schedulesAndPeriods(){
    assertEquals(3,CareRules.times("08:00, 14:00,20:00").size());
    assertThrows(IllegalArgumentException.class,()->CareRules.times("08:00,08:00"));
    assertThrows(IllegalArgumentException.class,()->CareRules.times("25:00"));
    assertTrue(CareRules.scheduled(LocalDate.of(2026,11,1),null,LocalDate.of(2026,11,17),LocalTime.of(8,0),"08:00"));
    assertFalse(CareRules.scheduled(LocalDate.of(2026,11,1),LocalDate.of(2026,11,15),LocalDate.of(2026,11,17),LocalTime.of(8,0),"08:00"));
    assertFalse(CareRules.scheduled(LocalDate.of(2026,11,1),null,LocalDate.of(2026,11,17),LocalTime.of(9,0),"08:00"));
  }
  @Test void measurementsAndStates(){
    assertDoesNotThrow(()->CareRules.observation("GLUCOSE",new BigDecimal("100"),null,null));
    assertDoesNotThrow(()->CareRules.observation("BLOOD_PRESSURE",new BigDecimal("120"),new BigDecimal("80"),null));
    assertThrows(IllegalArgumentException.class,()->CareRules.observation("BLOOD_PRESSURE",new BigDecimal("120"),null,null));
    assertThrows(IllegalArgumentException.class,()->CareRules.observation("NOTE",null,null,"  "));
    assertEquals("REPORTED_GIVEN",CareRules.status("REPORTED_GIVEN"));
    assertThrows(IllegalArgumentException.class,()->CareRules.status("UNKNOWN"));
  }
}
