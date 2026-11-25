package pe.familiaprado.app;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.web.server.ResponseStatusException;

class AppointmentReservationTest {
    private final JdbcTemplate db=mock(JdbcTemplate.class);
    private final AppointmentRotation rotation=new AppointmentRotation(db);
    private final UUID a=UUID.randomUUID(), b=UUID.randomUUID(), appointment=UUID.randomUUID();
    private final String move="UPDATE appointment_rotation_state SET next_position=?,revision=revision+1 WHERE id=1";
    private final String insert="INSERT INTO appointment_turn_reservations(appointment_id,member_id,status) VALUES(?,?,'RESERVED')";
    private void state(int position,long revision) {
        when(db.queryForObject(eq("SELECT next_position,revision FROM appointment_rotation_state WHERE id=1 FOR UPDATE"),org.mockito.ArgumentMatchers.<RowMapper<AppointmentRotation.State>>any())).thenReturn(new AppointmentRotation.State(position,revision));
    }
    private void order() {
        when(db.query(contains("FROM appointment_rotation_order o"),org.mockito.ArgumentMatchers.<RowMapper<AppointmentRotationRules.Member>>any())).thenReturn(List.of(new AppointmentRotationRules.Member(a,"A",1,true),new AppointmentRotationRules.Member(b,"B",2,true)));
    }
    @Test void reservationMovesCursorBeforeAttendance() {
        state(1,0); order();
        rotation.reserve(appointment,a,0L);
        verify(db).update(move,2);
        verify(db).update(insert,appointment,a);
    }
    @Test void substituteDoesNotConsumeTurn() {
        state(1,0); order();
        rotation.reserve(appointment,b);
        verify(db,never()).update(eq(move),anyInt());
        verify(db,never()).update(eq(insert),any(),any());
    }
    @Test void returnedTurnHasPriorityAndKeepsRegularCursor() {
        state(2,5); order();
        when(db.query(contains("WHERE r.status='RELEASED'"),org.mockito.ArgumentMatchers.<RowMapper<Map.Entry<Long,UUID>>>any())).thenReturn(List.of(Map.entry(7L,a)));
        rotation.reserve(appointment,a,5L);
        verify(db).update("UPDATE appointment_turn_reservations SET status='REUSED' WHERE id=?",7L);
        verify(db).update(move,2);
        verify(db).update(insert,appointment,a);
    }
    @Test void staleSuggestionCannotConsumeAnotherTurn() {
        state(2,1); order();
        assertEquals(409,assertThrows(ResponseStatusException.class,()->rotation.reserve(appointment,a,0L)).getStatusCode().value());
        verify(db,never()).update(eq(insert),any(),any());
    }
    @Test void releaseDoesNotRollBackRegularCursor() {
        state(2,1);
        when(db.update("UPDATE appointment_turn_reservations SET status='RELEASED',released_at=clock_timestamp() WHERE appointment_id=? AND status='RESERVED'",appointment)).thenReturn(1,0);
        rotation.release(appointment); rotation.release(appointment);
        verify(db,times(1)).update(move,2);
    }
}
