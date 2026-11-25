package pe.familiaprado.app;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

class AppointmentCalendarTest {
    @Test
    void usesLimaMonthBoundsAndIncludesEveryStatus() {
        JdbcTemplate db=mock(JdbcTemplate.class);
        var controller=new AppointmentsController(db,null,null,null);
        var planned=new AppointmentsController.Appointment(UUID.randomUUID(),Instant.parse("2026-12-01T05:00:00Z"),"Centro","Consulta",null,"PLANNED",null);
        var cancelled=new AppointmentsController.Appointment(UUID.randomUUID(),Instant.parse("2027-01-01T04:59:00Z"),"Centro","Consulta",null,"CANCELLED",null);
        String sql="SELECT id,appointment_at,hospital,specialty,responsible_member_id,status,preparation,actual_member_id FROM appointments WHERE deleted_at IS NULL AND appointment_at >= ? AND appointment_at < ? ORDER BY appointment_at ASC,id ASC";
        Timestamp from=Timestamp.from(Instant.parse("2026-12-01T05:00:00Z"));
        Timestamp to=Timestamp.from(Instant.parse("2027-01-01T05:00:00Z"));
        when(db.query(eq(sql),org.mockito.ArgumentMatchers.<RowMapper<AppointmentsController.Appointment>>any(),eq(from),eq(to)))
            .thenReturn(List.of(planned,cancelled));
        assertEquals(List.of(planned,cancelled),controller.calendar(LocalDate.of(2026,12,15)));
        verify(db).query(eq(sql),org.mockito.ArgumentMatchers.<RowMapper<AppointmentsController.Appointment>>any(),eq(from),eq(to));
        verifyNoMoreInteractions(db);
    }
}
