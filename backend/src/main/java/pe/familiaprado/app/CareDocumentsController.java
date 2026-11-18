package pe.familiaprado.app;

import java.io.IOException;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

/** Private files, never served from public/static. Configure CARE_DOCUMENT_DIR outside the repo. */
@RestController
@RequestMapping("/api/care/documents")
public class CareDocumentsController {
    private static final long LIMIT=5L*1024*1024;
    private final JdbcTemplate db;
    private final CareAccess access;
    private final String storage;
    public CareDocumentsController(JdbcTemplate db,CareAccess access,@Value("${CARE_DOCUMENT_DIR:}") String storage){
        this.db=db;this.access=access;this.storage=storage;
    }
    private Path root(){
        if(storage.isBlank()) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
            "Configura CARE_DOCUMENT_DIR en .env fuera del repositorio");
        Path path=Path.of(storage).toAbsolutePath().normalize();
        try{ Files.createDirectories(path); }
        catch(IOException e){throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Almacenamiento privado no disponible");}
        return path;
    }
    public record Document(UUID id,String title,String category,String originalName,String mimeType,long sizeBytes,
                           Instant uploadedAt,String uploadedBy){}
    @GetMapping public List<Document> list(){
        access.require();
        return db.query("""
            SELECT d.id,d.title,d.category,d.original_name,d.mime_type,d.size_bytes,d.uploaded_at,
                   COALESCE(m.display_name,'Administrador') author
            FROM care_documents d JOIN app_users u ON u.id=d.uploaded_by
            LEFT JOIN family_members m ON m.id=u.member_id
            ORDER BY d.uploaded_at DESC LIMIT 100
            """,(rs,n)->new Document(rs.getObject("id",UUID.class),rs.getString("title"),
               rs.getString("category"),rs.getString("original_name"),rs.getString("mime_type"),rs.getLong("size_bytes"),
               rs.getTimestamp("uploaded_at").toInstant(),rs.getString("author")));
    }
    private static String detect(byte[] bytes){
        if(bytes.length>=5 && bytes[0]=='%' && bytes[1]=='P' && bytes[2]=='D' && bytes[3]=='F' && bytes[4]=='-')
            return "application/pdf";
        if(bytes.length>=3 && (bytes[0]&0xff)==0xff && (bytes[1]&0xff)==0xd8 && (bytes[2]&0xff)==0xff)
            return "image/jpeg";
        if(bytes.length>=8 && (bytes[0]&0xff)==137 && bytes[1]==80 && bytes[2]==78 && bytes[3]==71 &&
                bytes[4]==13 && bytes[5]==10 && bytes[6]==26 && bytes[7]==10) return "image/png";
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Solo se aceptan PDF, JPG o PNG");
    }
    @PostMapping(consumes=MediaType.MULTIPART_FORM_DATA_VALUE) @ResponseStatus(HttpStatus.CREATED)
    @Transactional
    public Map<String,UUID> upload(@RequestParam String title,@RequestParam String category,
                                   @RequestPart("file") MultipartFile file){
        Session.current().adminOnly();
        if(title==null || title.isBlank() || title.length()>140 ||
           category==null || !List.of("RECIPE","EXAM","ORDER","OTHER").contains(category))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Revisa el título o la categoría");
        if(file.isEmpty() || file.getSize()>LIMIT)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"El documento debe tener máximo 5 MB");
        // No se confía en el nombre ni MIME recibido desde el cliente.
        String original=Optional.ofNullable(file.getOriginalFilename()).orElse("documento");
        original=original.replace('\\','/');original=original.substring(original.lastIndexOf('/')+1);
        original=original.replaceAll("[\\p{Cntrl}]", "");
        if(original.isBlank() || original.length()>180) original="documento";
        byte[] bytes;
        try{bytes=file.getBytes();}catch(IOException e){throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"No se pudo leer el archivo");}
        if(bytes.length==0 || bytes.length>LIMIT) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Archivo demasiado grande");
        String mime=detect(bytes);
        UUID id=UUID.randomUUID();
        String stored=id.toString()+switch(mime){case "application/pdf"->".pdf";case "image/png"->".png";default->".jpg";};
        Path output=root().resolve(stored);
        try{
            Files.write(output,bytes,StandardOpenOption.CREATE_NEW);
            try{
                db.update("""
                    INSERT INTO care_documents(id,title,category,original_name,stored_name,mime_type,size_bytes,uploaded_by)
                    VALUES(?,?,?,?,?,?,?,?)
                    """,id,title.strip(),category,original,stored,mime,bytes.length,Session.current().userId());
            }catch(RuntimeException e){Files.deleteIfExists(output);throw e;}
        }catch(IOException e){throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"No se pudo guardar el documento privado");}
        return Map.of("id",id);
    }
    @GetMapping("/{id}/download") public ResponseEntity<byte[]> download(@PathVariable UUID id){
        access.require();
        var rows=db.query("SELECT stored_name,original_name,mime_type FROM care_documents WHERE id=?",
             (r,n)->new String[]{r.getString(1),r.getString(2),r.getString(3)},id);
        if(rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Documento no encontrado");
        String[] info=rows.getFirst();
        Path file=root().resolve(info[0]);
        if(!file.startsWith(root())) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"Ruta no válida");
        byte[] bytes;
        try{bytes=Files.readAllBytes(file);}catch(IOException e){throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Archivo no disponible");}
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(info[2]))
            .header(HttpHeaders.CACHE_CONTROL,"no-store, private")
            .header("X-Content-Type-Options","nosniff")
            .header(HttpHeaders.CONTENT_DISPOSITION,ContentDisposition.attachment().filename(info[1],java.nio.charset.StandardCharsets.UTF_8).build().toString())
            .body(bytes);
    }
}
