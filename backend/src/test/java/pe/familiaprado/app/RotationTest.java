package pe.familiaprado.app;

import org.junit.jupiter.api.Test;
import java.time.LocalDate;
import static org.junit.jupiter.api.Assertions.*;

class RotationTest {
  @Test void mondayFromAnyDay() {
    assertEquals(LocalDate.parse("2026-11-16"),RotationService.monday(LocalDate.parse("2026-11-22")));
  }
  @Test void eightWeekCycle() {
    var anchor=LocalDate.parse("2026-11-16");
    for(int i=-20;i<=20;i++) assertEquals(3,
      RotationService.position(anchor,3,anchor.plusWeeks(i*8L),8));
  }
  @Test void roundRobinAndReverseWeeks() {
    var anchor=LocalDate.parse("2026-11-16");
    assertEquals(1,RotationService.position(anchor,1,anchor,8));
    assertEquals(8,RotationService.position(anchor,1,anchor.minusWeeks(1),8));
    assertEquals(2,RotationService.position(anchor,1,anchor.plusWeeks(1),8));
  }
}
