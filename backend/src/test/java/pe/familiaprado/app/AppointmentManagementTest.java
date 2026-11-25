package pe.familiaprado.app;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.server.ResponseStatusException;

class AppointmentManagementTest {
    private final JdbcTemplate db=mock(JdbcTemplate.class);
    private final ChangeFeed feed=mock(ChangeFeed.class);
    private final PushQueue push=mock(PushQueue.class);
    private final AppointmentsController controller=new AppointmentsController(db,feed,push,null);
    private final UUID id=UUID.randomUUID();
    private void login(String role){
        var session=new Session(UUID.randomUUID(),"test@example.invalid",role,null);
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(session,null,List.of()));
    }
    @AfterEach void clear(){ SecurityContextHolder.clearContext(); }
    @Test void memberCannotEditOrArchive(){
        login("MEMBER");
        var payload=new AppointmentsController.NewAppointment(Instant.now(),"Centro","Consulta",null,"");
        assertEquals(403,assertThrows(ResponseStatusException.class,()->controller.edit(id,payload)).getStatusCode().value());
        assertEquals(403,assertThrows(ResponseStatusException.class,()->controller.archive(id)).getStatusCode().value());
        verifyNoInteractions(db,push,feed);
    }
    @Test void sameEditDoesNotGenerateNewNotification(){
        login("ADMIN");
        var at=Instant.parse("2026-12-10T14:00:00Z");
        var old=new AppointmentsController.Appointment(id,at,"Centro","Consulta",null,"CONFIRMED",null);
        when(db.query(contains("FOR UPDATE"),org.mockito.ArgumentMatchers.<RowMapper<AppointmentsController.Appointment>>any(),eq(id))).thenReturn(List.of(old));
        controller.edit(id,new AppointmentsController.NewAppointment(at,"Centro","Consulta",null,""));
        verifyNoInteractions(push,feed);
        verify(db).query(contains("FOR UPDATE"),org.mockito.ArgumentMatchers.<RowMapper<AppointmentsController.Appointment>>any(),eq(id));
        verifyNoMoreInteractions(db);
    }
    @Test void archiveRetryDoesNotNotifyAgain(){
        login("ADMIN");
        var old=new AppointmentsController.Appointment(id,Instant.now(),"Centro","Consulta",null,"PLANNED",null);
        when(db.query(contains("FOR UPDATE"),org.mockito.ArgumentMatchers.<RowMapper<AppointmentsController.Appointment>>any(),eq(id))).thenReturn(List.of(old));
        when(db.update("UPDATE appointments SET deleted_at=NOW() WHERE id=? AND deleted_at IS NULL",id)).thenReturn(1,0);
        when(db.queryForObject(eq("SELECT next_position,revision FROM appointment_rotation_state WHERE id=1 FOR UPDATE"),org.mockito.ArgumentMatchers.<RowMapper<AppointmentRotation.State>>any())).thenReturn(new AppointmentRotation.State(1,0));
        controller.archive(id);
        controller.archive(id);
        verify(push,times(1)).appointmentStatusChanged(id,null,"CANCELLED");
        verify(feed,times(1)).changed("appointments");
    }
}
