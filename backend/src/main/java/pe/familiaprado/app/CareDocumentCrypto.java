package pe.familiaprado.app;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.UUID;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** AES-256-GCM. La clave se administra FUERA de PostgreSQL y del repositorio. */
final class CareDocumentCrypto {
    static final int NONCE_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final SecureRandom RANDOM = new SecureRandom();
    private final SecretKeySpec key;

    CareDocumentCrypto(String base64Key) {
        if (base64Key == null || base64Key.isBlank()) {
            key = null;
            return;
        }
        byte[] decoded;
        try {
            decoded = Base64.getDecoder().decode(base64Key.strip());
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("CARE_DOCUMENT_KEY_BASE64 no es Base64 valido", e);
        }
        if (decoded.length != 32) {
            throw new IllegalArgumentException("CARE_DOCUMENT_KEY_BASE64 debe representar 32 bytes");
        }
        key = new SecretKeySpec(decoded, "AES");
        java.util.Arrays.fill(decoded, (byte) 0);
    }

    boolean ready() { return key != null; }

    record Encrypted(byte[] nonce, byte[] ciphertext) {}

    Encrypted encrypt(UUID documentId, byte[] bytes) throws GeneralSecurityException {
        if (!ready()) throw new IllegalStateException("No hay clave para documentos");
        byte[] nonce = new byte[NONCE_BYTES];
        RANDOM.nextBytes(nonce);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, nonce));
        cipher.updateAAD(documentId.toString().getBytes(StandardCharsets.UTF_8));
        return new Encrypted(nonce, cipher.doFinal(bytes));
    }

    byte[] decrypt(UUID documentId, byte[] nonce, byte[] ciphertext) throws GeneralSecurityException {
        if (!ready()) throw new IllegalStateException("No hay clave para documentos");
        if (nonce == null || nonce.length != NONCE_BYTES) throw new GeneralSecurityException("Nonce incorrecto");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, nonce));
        cipher.updateAAD(documentId.toString().getBytes(StandardCharsets.UTF_8));
        return cipher.doFinal(ciphertext);
    }
}
