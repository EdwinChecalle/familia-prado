package pe.familiaprado.app;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;

/** Arithmetic and range policy shared by reporting and independent tests. */
public final class FundReportMath {
    private FundReportMath() {}
    public static boolean validRange(LocalDate from, LocalDate to) {
        return from != null && to != null && !to.isBefore(from)
            && ChronoUnit.DAYS.between(from, to) <= 366;
    }
    public static BigDecimal closing(BigDecimal opening, BigDecimal verified, BigDecimal approved) {
        return opening.add(verified).subtract(approved);
    }
}
