package pe.familiaprado.app;

import java.time.*;
import java.util.Locale;

/** Centralizes Lima calendar boundaries and appointment list ordering. */
public final class AppointmentSearchRules {
    public static final ZoneId LIMA = ZoneId.of("America/Lima");
    private AppointmentSearchRules() {}

    public enum Bucket { UPCOMING, TODAY, HISTORY, CANCELLED }

    public static Bucket bucket(String value) {
        try { return Bucket.valueOf((value == null ? "UPCOMING" : value).toUpperCase(Locale.ROOT)); }
        catch (IllegalArgumentException ex) { throw new IllegalArgumentException("Filtro de citas no reconocido"); }
    }

    public static Instant dayStart(LocalDate date) { return date.atStartOfDay(LIMA).toInstant(); }
    public static Instant nextDayStart(LocalDate date) { return date.plusDays(1).atStartOfDay(LIMA).toInstant(); }
    public static LocalDate today(Clock clock) { return LocalDate.now(clock.withZone(LIMA)); }

    public static String order(Bucket bucket) {
        return switch (bucket) {
            case UPCOMING, TODAY -> "appointment_at ASC, id ASC";
            case HISTORY, CANCELLED -> "appointment_at DESC, id DESC";
        };
    }

    public static int pageSize(int limit) {
        if (limit < 1 || limit > 50) throw new IllegalArgumentException("El límite debe estar entre 1 y 50");
        return limit;
    }
    public static int pageOffset(int offset) {
        if (offset < 0 || offset > 100000) throw new IllegalArgumentException("Desplazamiento de página incorrecto");
        return offset;
    }
}
