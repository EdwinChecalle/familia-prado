package pe.familiaprado.app;

import java.time.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class AppointmentSearchRulesTest {
    @Test void limaDayBoundariesAndPaging() {
        assertEquals(Instant.parse("2026-11-18T05:00:00Z"),AppointmentSearchRules.dayStart(LocalDate.of(2026,11,18)));
        assertEquals(Instant.parse("2026-11-19T05:00:00Z"),AppointmentSearchRules.nextDayStart(LocalDate.of(2026,11,18)));
        assertEquals("appointment_at DESC, id DESC",AppointmentSearchRules.order(AppointmentSearchRules.Bucket.HISTORY));
        assertEquals("appointment_at ASC, id ASC",AppointmentSearchRules.order(AppointmentSearchRules.Bucket.UPCOMING));
        assertEquals(AppointmentSearchRules.Bucket.CANCELLED,AppointmentSearchRules.bucket("cancelled"));
        assertThrows(IllegalArgumentException.class,()->AppointmentSearchRules.pageSize(0));
        assertThrows(IllegalArgumentException.class,()->AppointmentSearchRules.pageSize(51));
        assertThrows(IllegalArgumentException.class,()->AppointmentSearchRules.pageOffset(-1));
        assertThrows(IllegalArgumentException.class,()->AppointmentSearchRules.bucket("wrong"));
    }
}
