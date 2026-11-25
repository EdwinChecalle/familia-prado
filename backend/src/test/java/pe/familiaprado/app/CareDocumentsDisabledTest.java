package pe.familiaprado.app;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.server.ResponseStatusException;

/** 04-D2: deshabilitar documentos no debe impedir la carga del resto del modulo Cuidado. */
class CareDocumentsDisabledTest {
    private final JdbcTemplate db = mock(JdbcTemplate.class);
    private final CareAccess access = mock(CareAccess.class);
    private final CareDocumentsController controller = new CareDocumentsController(db, access, "", false, "");

    @AfterEach
    void clearSession() {
        SecurityContextHolder.clearContext();
    }

    private void authenticate(String role) {
        Session session = new Session(UUID.randomUUID(), "prueba@fprado.local", role, UUID.randomUUID());
        SecurityContextHolder.getContext().setAuthentication(
            new UsernamePasswordAuthenticationToken(session, null, List.of()));
    }

    @Test
    void authorizedUserSeesEmptyDocumentListWithoutDatabaseQuery() {
        authenticate("USER");
        assertEquals(List.of(), controller.list());
        verify(access).require();
        verifyNoInteractions(db);
    }

    @Test
    void disablingDocumentsDoesNotBypassCarePermissions() {
        authenticate("USER");
        doThrow(new ResponseStatusException(HttpStatus.FORBIDDEN)).when(access).require();
        ResponseStatusException ex = assertThrows(ResponseStatusException.class, controller::list);
        assertEquals(HttpStatus.FORBIDDEN, ex.getStatusCode());
        verifyNoInteractions(db);
    }

    @Test
    void uploadRemainsDisabledForAdministrator() {
        authenticate("ADMIN");
        var file = new MockMultipartFile("file", "test.pdf", "application/pdf", "%PDF-1.4".getBytes());
        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
            () -> controller.upload("Prueba", "EXAM", file));
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, ex.getStatusCode());
        verifyNoInteractions(db);
    }

    @Test
    void downloadRemainsDisabledForAuthorizedUser() {
        authenticate("USER");
        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
            () -> controller.download(UUID.randomUUID()));
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, ex.getStatusCode());
        verify(access).require();
        verifyNoInteractions(db);
    }
}
