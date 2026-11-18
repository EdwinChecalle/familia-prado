package pe.familiaprado.app;

import java.math.BigDecimal;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class FundReportMathTest {
    @Test void closingUsesOnlyApprovedTotals() {
        assertEquals(new BigDecimal("304.30"), FundReportMath.closing(
          new BigDecimal("69.30"),new BigDecimal("300.00"),new BigDecimal("65.00")));
    }
    @Test void noFloatDrift() {
        assertEquals(new BigDecimal("0.30"), FundReportMath.closing(
          new BigDecimal("0.00"),new BigDecimal("0.10"),new BigDecimal("-0.20")));
    }
    @Test void boundedPeriod() {
        assertTrue(FundReportMath.validRange(LocalDate.of(2026,11,1),LocalDate.of(2026,11,30)));
        assertFalse(FundReportMath.validRange(LocalDate.of(2026,11,30),LocalDate.of(2026,11,1)));
        assertFalse(FundReportMath.validRange(null,LocalDate.of(2026,11,1)));
    }
}
