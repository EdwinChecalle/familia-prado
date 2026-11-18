package pe.familiaprado.app;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;

/** Calendario de avisos: lógica pura e independiente de Firebase. */
public final class PushScheduleRules {
    private PushScheduleRules() {}
    public record Due(String key, Instant at, Instant expiresAt) {}

    public static List<Due> forNewAppointment(Instant appointmentAt,Instant now) {
        if (appointmentAt==null || now==null || !appointmentAt.isAfter(now)) return List.of();
        List<Due> due=new ArrayList<>();
        due.add(new Due("NEW",now,now.plus(12,ChronoUnit.HOURS)));
        for(long before:new long[]{24,3}) {
            Instant at=appointmentAt.minus(before,ChronoUnit.HOURS);
            if(at.isAfter(now)) {
                due.add(new Due(before+"H",at,at.plus(3,ChronoUnit.HOURS)));
            }
        }
        return List.copyOf(due);
    }
}
