package pe.familiaprado.app;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

/** Documentos privados: contenido cifrado en Neon. Sin archivos nuevos en Render. */
@RestController
@RequestMapping("/api/care/documents")
public class CareDocumentsController {
    private static final long LIMIT = 5L * 1024 * 1024;
    // Reserva una fraccion pequena de la cuota de almacenamiento Neon Free.
    private static final long TOTAL_LIMIT = 80L * 1024 * 1024;
    private final JdbcTemplate db;
    private final CareAccess access;
    private final String legacyStorage;
    private final boolean enabled;
    private final CareDocumentCrypto crypto;

    public CareDocumentsController(JdbcTemplate db, CareAccess access,
            @Value("${CARE_DOCUMENT_DIR:}") String legacyStorage,
            @Value("${CARE_DOCUMENTS_ENABLED:true}") boolean enabled,
            @Value("${CARE_DOCUMENT_KEY_BASE64:}") String key) {
        this.db = db;
        this.access = access;
        this.legacyStorage = legacyStorage;
        this.enabled = enabled;
        this.crypto = new CareDocumentCrypto(key);
    }

    private void checkEnabled() {
        if (!enabled) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
            "Los documentos médicos están deshabilitados en este entorno");
    }

    private void checkKey() {
        if (!crypto.ready()) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
            "Documentos cifrados no disponibles: falta configurar la clave privada");
    }

    public record Document(UUID id, String title, String category, String originalName, String mimeType,
                           long sizeBytes, Instant uploadedAt, String uploadedBy) {}

    @GetMapping
    public List<Document> list() {
        access.require();
        // En staging, los documentos pueden estar deshabilitados sin bloquear
        // medicamentos, registros y observaciones en la pantalla de Cuidado.
        if (!enabled) return List.of();
        return db.query("""
            SELECT d.id,d.title,d.category,d.original_name,d.mime_type,d.size_bytes,d.uploaded_at,
                   COALESCE(m.display_name,'Administrador') author
            FROM care_documents d JOIN app_users u ON u.id=d.uploaded_by
            LEFT JOIN family_members m ON m.id=u.member_id
            ORDER BY d.uploaded_at DESC LIMIT 100
            """, (rs, n) -> new Document(rs.getObject("id", UUID.class),rs.getString("title"),
               rs.getString("category"),rs.getString("original_name"),rs.getString("mime_type"),
               rs.getLong("size_bytes"),rs.getTimestamp("uploaded_at").toInstant(),rs.getString("author")));
    }

    private static String detect(byte[] bytes) {
        if (bytes.length >= 5 && bytes[0] == '%' && bytes[1] == 'P' && bytes[2] == 'D'
                && bytes[3] == 'F' && bytes[4] == '-') return "application/pdf";
        if (bytes.length >= 3 && (bytes[0] & 255) == 255 && (bytes[1] & 255) == 216
                && (bytes[2] & 255) == 255) return "image/jpeg";
        if (bytes.length >= 8 && (bytes[0] & 255) == 137 && bytes[1] == 80
                && bytes[2] == 78 && bytes[3] == 71 && bytes[4] == 13
                && bytes[5] == 10 && bytes[6] == 26 && bytes[7] == 10) return "image/png";
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Solo se aceptan PDF, JPG o PNG");
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    public Map<String, UUID> upload(@RequestParam String title, @RequestParam String category,
                                    @RequestPart("file") MultipartFile file) {
        Session.current().adminOnly();
        checkEnabled();
        checkKey();
        if (title == null || title.isBlank() || title.length() > 140 || category == null
                || !List.of("RECIPE", "EXAM", "ORDER", "OTHER").contains(category)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Revisa el título o la categoría");
        }
        if (file.isEmpty() || file.getSize() > LIMIT) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El archivo debe tener máximo 5 MB");
        }
        String original = Optional.ofNullable(file.getOriginalFilename()).orElse("documento");
        original = original.replace('\\', '/');
        original = original.substring(original.lastIndexOf('/') + 1).replaceAll("[\\p{Cntrl}]", "");
        if (original.isBlank() || original.length() > 180) original = "documento";
        byte[] bytes;
        try { bytes = file.getBytes(); }
        catch (IOException e) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "No se pudo leer el archivo"); }
        if (bytes.length == 0 || bytes.length > LIMIT) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Archivo demasiado grande");
        }
        String mime = detect(bytes);
        UUID id = UUID.randomUUID();
        CareDocumentCrypto.Encrypted encrypted;
        try { encrypted = crypto.encrypt(id, bytes); }
        catch (java.security.GeneralSecurityException e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "No se pudo proteger el documento");
        }

        // Serializa subidas concurrentes para respetar la cuota en una sola transaccion.
        db.execute("SELECT pg_advisory_xact_lock(24042026)");
        Long occupied = db.queryForObject("""
            SELECT COALESCE(SUM(d.size_bytes), 0) FROM care_documents d
            JOIN care_document_contents c ON c.document_id = d.id
            """, Long.class);
        if ((occupied == null ? 0L : occupied) > TOTAL_LIMIT - bytes.length) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                "Límite privado de 80 MB alcanzado. Conserva espacio para la base de datos.");
        }
        String stored = id.toString() + switch (mime) {
            case "application/pdf" -> ".pdf";
            case "image/png" -> ".png";
            default -> ".jpg";
        };
        db.update("""
            INSERT INTO care_documents(id,title,category,original_name,stored_name,mime_type,size_bytes,uploaded_by)
            VALUES(?,?,?,?,?,?,?,?)
            """, id,title.strip(),category,original,stored,mime,bytes.length,Session.current().userId());
        db.update("""
            INSERT INTO care_document_contents(document_id,key_version,nonce,ciphertext)
            VALUES(?,?,?,?)
            """,id,1,encrypted.nonce(),encrypted.ciphertext());
        return Map.of("id", id);
    }

    private record Stored(String originalName, String mimeType, String legacyName,
                          byte[] nonce, byte[] ciphertext, int keyVersion) {}

    @GetMapping("/{id}/download")
    public ResponseEntity<byte[]> download(@PathVariable UUID id) {
        access.require();
        checkEnabled();
        var rows = db.query("""
            SELECT d.original_name,d.mime_type,d.stored_name,c.nonce,c.ciphertext,c.key_version
            FROM care_documents d LEFT JOIN care_document_contents c ON c.document_id=d.id
            WHERE d.id=?
            """, (rs,n) -> new Stored(rs.getString(1),rs.getString(2),rs.getString(3),
                rs.getBytes(4),rs.getBytes(5),rs.getInt(6)), id);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Documento no encontrado");
        Stored record = rows.getFirst();
        byte[] bytes;
        if (record.ciphertext() != null) {
            checkKey();
            if (record.keyVersion() != 1) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "Versión de cifrado no soportada");
            try { bytes = crypto.decrypt(id, record.nonce(), record.ciphertext()); }
            catch (java.security.GeneralSecurityException e) {
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "No se pudo descifrar el documento. Verifica la clave privada.");
            }
        } else {
            // Compatibilidad solo para documentos locales previos: no se borran ni alteran.
            if (legacyStorage.isBlank()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                "Documento anterior no disponible en este servidor; se necesita su archivo original");
            Path root = Path.of(legacyStorage).toAbsolutePath().normalize();
            Path path = root.resolve(record.legacyName()).normalize();
            if (!path.startsWith(root)) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Ruta no válida");
            try { bytes = Files.readAllBytes(path); }
            catch (IOException e) { throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Archivo anterior no disponible"); }
        }
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(record.mimeType()))
            .header(HttpHeaders.CACHE_CONTROL, "no-store, private")
            .header("Pragma", "no-cache")
            .header("X-Content-Type-Options", "nosniff")
            .header(HttpHeaders.CONTENT_DISPOSITION,
                ContentDisposition.attachment().filename(record.originalName(),java.nio.charset.StandardCharsets.UTF_8).build().toString())
            .body(bytes);
    }
}
