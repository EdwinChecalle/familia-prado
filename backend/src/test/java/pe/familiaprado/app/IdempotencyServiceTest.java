package pe.familiaprado.app;

import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import static org.junit.jupiter.api.Assertions.*;

class IdempotencyServiceTest {
    @Test void normalizesUuidAndRejectsInvalidKey() {
        String key="f18ee9e7-6e82-4b17-a9d1-1e9ba7610b05";
        assertEquals(key,IdempotencyService.normalize(key));
        assertNull(IdempotencyService.normalize(null));
        assertThrows(ResponseStatusException.class,()->IdempotencyService.normalize("not-a-uuid"));
    }
    @Test void fingerprintIsDeterministicAndIncludesOperation() {
        assertEquals(IdempotencyService.hash("fund.collections\nNewCollection[concept=A]"),
            IdempotencyService.hash("fund.collections\nNewCollection[concept=A]"));
        assertNotEquals(IdempotencyService.hash("fund.collections\nA"),
            IdempotencyService.hash("fund.expenses\nA"));
    }
}
