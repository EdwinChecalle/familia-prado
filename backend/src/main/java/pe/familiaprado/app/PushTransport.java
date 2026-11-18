package pe.familiaprado.app;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.AndroidNotification;
import com.google.firebase.messaging.ApnsConfig;
import com.google.firebase.messaging.Aps;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import java.io.FileInputStream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class PushTransport {
    private static final Logger log=LoggerFactory.getLogger(PushTransport.class);
    private final FirebaseMessaging messaging;
    public boolean isEnabled() { return messaging!=null; }

    public PushTransport(@Value("${FIREBASE_SERVICE_ACCOUNT_FILE:}") String credentials,
                         @Value("${FIREBASE_PROJECT_ID:}") String project) {
        FirebaseMessaging result=null;
        if (!credentials.isBlank() && !project.isBlank()) {
            try (var stream=new FileInputStream(credentials)) {
                FirebaseOptions opts=FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(stream))
                    .setProjectId(project).build();
                FirebaseApp app=FirebaseApp.initializeApp(opts,"familia-prado-push");
                result=FirebaseMessaging.getInstance(app);
            } catch(Exception e) {
                log.error("FCM deshabilitado: revisa cuenta de servicio, ruta y proyecto",e);
            }
        } else log.warn("FCM sin configurar: solo recordatorios locales");
        messaging=result;
    }

    public void send(String token,String platform,boolean spoken,String kind,
                     String title,String body,String eventId,String route) throws Exception {
        if (messaging==null) throw new IllegalStateException("FCM no configurado");
        String sound=switch(kind) {
            case "APPOINTMENT","CANCELLED" -> "prado_cita";
            case "TURN" -> "prado_turno";
            case "COLLECTION" -> "prado_colecta";
            default -> "prado_aviso";
        };
        String channel=spoken ? switch(kind) {
            case "APPOINTMENT","CANCELLED" -> "prado_cita_voz_v2";
            case "TURN" -> "prado_turno_voz_v2";
            case "COLLECTION" -> "prado_colecta_voz_v2";
            default -> "prado_aviso_voz_v2";
        } : "prado_general_v2";
        var android=AndroidConfig.builder()
            .setPriority(AndroidConfig.Priority.HIGH)
            .setNotification(AndroidNotification.builder()
                .setChannelId(channel)
                .setSound(spoken ? sound : "default").build())
            .build();
        var ios=ApnsConfig.builder().setAps(Aps.builder()
            .setSound(spoken ? sound+".wav" : "default").build()).build();
        Message message=Message.builder()
            .setToken(token)
            .setNotification(Notification.builder().setTitle(title).setBody(body).build())
            .setAndroidConfig(android)
            .setApnsConfig(ios)
            .putData("kind",kind)
            .putData("route",route)
            .putData("eventId",eventId)
            .build();
        messaging.send(message);
    }
}
