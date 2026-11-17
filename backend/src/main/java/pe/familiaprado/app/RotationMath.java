package pe.familiaprado.app;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;

/** Pure domain logic, independent of the database or HTTP. */
public final class RotationMath {
    private RotationMath() {}
    public static LocalDate monday(LocalDate date) {
        return date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    }
    public static int position(LocalDate anchor, int firstPosition, LocalDate date, int cycleSize) {
        if (anchor == null || date == null || cycleSize <= 0 || firstPosition<1 || firstPosition>cycleSize ||
            anchor.getDayOfWeek()!=DayOfWeek.MONDAY)
            throw new IllegalArgumentException("La rotación debe comenzar un lunes con un número válido");
        long weeks=ChronoUnit.WEEKS.between(anchor,monday(date));
        return Math.floorMod((int)(weeks % cycleSize)+firstPosition-1,cycleSize)+1;
    }
}
