package pe.familiaprado.app;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.regex.Pattern;

/** Validation-only rules. No clinical interpretation or treatment advice. */
public final class CareRules {
    private CareRules() {}
    private static final Pattern HHMM = Pattern.compile("(?:[01][0-9]|2[0-3]):[0-5][0-9]");
    public static List<LocalTime> times(String raw) {
        if (raw == null || raw.isBlank() || raw.length()>120) throw new IllegalArgumentException("Registra uno o más horarios HH:mm");
        String[] tokens=raw.split(",",-1);
        if (tokens.length>8) throw new IllegalArgumentException("Máximo 8 horarios diarios");
        List<LocalTime> times=java.util.Arrays.stream(tokens).map(String::trim).map(value -> {
            if (!HHMM.matcher(value).matches()) throw new IllegalArgumentException("Formato de horario incorrecto");
            return LocalTime.parse(value);
        }).toList();
        if (times.stream().distinct().count()!=times.size()) throw new IllegalArgumentException("No repitas horarios");
        return times;
    }
    public static boolean scheduled(LocalDate start,LocalDate end,LocalDate date,LocalTime time,String times){
        return date!=null && !date.isBefore(start) && (end==null || !date.isAfter(end)) && times(times).contains(time);
    }
    public static void observation(String kind,BigDecimal main,BigDecimal secondary,String note) {
        if (kind==null || !List.of("GLUCOSE","BLOOD_PRESSURE","TEMPERATURE","NOTE").contains(kind))
            throw new IllegalArgumentException("Tipo de observación incorrecto");
        if (note!=null && note.length()>700) throw new IllegalArgumentException("Observación demasiado extensa");
        if (kind.equals("NOTE")) {
            if (note==null || note.isBlank() || main!=null || secondary!=null)
                throw new IllegalArgumentException("La nota requiere texto y no números");
            return;
        }
        if (main==null || main.signum()<=0 || main.compareTo(new BigDecimal("9999"))>0)
            throw new IllegalArgumentException("Valor inválido");
        if (kind.equals("BLOOD_PRESSURE") && (secondary==null || secondary.signum()<=0 || secondary.compareTo(new BigDecimal("9999"))>0))
            throw new IllegalArgumentException("Registra ambos valores de presión");
        if (!kind.equals("BLOOD_PRESSURE") && secondary!=null)
            throw new IllegalArgumentException("Este registro necesita un solo valor");
    }
    public static String status(String value) {
        if (value==null || !List.of("REPORTED_GIVEN","REPORTED_NOT_GIVEN").contains(value))
            throw new IllegalArgumentException("Selecciona un estado válido");
        return value;
    }
}
