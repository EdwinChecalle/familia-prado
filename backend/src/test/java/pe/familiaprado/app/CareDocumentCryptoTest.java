package pe.familiaprado.app;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.Base64;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class CareDocumentCryptoTest {
    private static CareDocumentCrypto crypto() {
        byte[] key = new byte[32];
        for (int i = 0; i < key.length; i++) key[i] = (byte) (i + 1);
        return new CareDocumentCrypto(Base64.getEncoder().encodeToString(key));
    }

    @Test void roundTripYNonceDiferente() throws Exception {
        var crypto = crypto();
        UUID id = UUID.randomUUID();
        byte[] data = "resultado médico confidencial".getBytes(StandardCharsets.UTF_8);
        var a = crypto.encrypt(id, data);
        var b = crypto.encrypt(id, data);
        assertArrayEquals(data, crypto.decrypt(id, a.nonce(), a.ciphertext()));
        assertFalse(java.util.Arrays.equals(data, a.ciphertext()));
        assertFalse(java.util.Arrays.equals(a.nonce(), b.nonce()));
    }

    @Test void otroDocumentoNoDescifra() throws Exception {
        var crypto = crypto();
        var a = crypto.encrypt(UUID.randomUUID(), "pdf".getBytes(StandardCharsets.UTF_8));
        assertThrows(GeneralSecurityException.class,
            () -> crypto.decrypt(UUID.randomUUID(), a.nonce(), a.ciphertext()));
    }

    @Test void contenidoAlteradoNoDescifra() throws Exception {
        var crypto = crypto();
        UUID id = UUID.randomUUID();
        var a = crypto.encrypt(id, "imagen".getBytes(StandardCharsets.UTF_8));
        byte[] altered = a.ciphertext().clone(); altered[0] ^= 1;
        assertThrows(GeneralSecurityException.class, () -> crypto.decrypt(id, a.nonce(), altered));
    }

    @Test void claveAusenteOInvalida() {
        assertFalse(new CareDocumentCrypto("").ready());
        assertThrows(IllegalArgumentException.class, () -> new CareDocumentCrypto("abcd"));
        assertThrows(IllegalArgumentException.class, () -> new CareDocumentCrypto("@@"));
    }
}
