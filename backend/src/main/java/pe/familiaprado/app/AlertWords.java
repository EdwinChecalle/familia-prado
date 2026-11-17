package pe.familiaprado.app;

/** Spoken reminders intentionally omit diagnoses, medical specialties and payment references. */
public final class AlertWords {
    private AlertWords() {}
    public static String weekNow(String name) {
        return name + ", esta semana te toca preparar desayuno, almuerzo y cena para Papá Isidro.";
    }
    public static String weekNext(String name) {
        return name + ", la próxima semana te toca preparar la comida para Papá Isidro.";
    }
    public static String appointmentTomorrow(String name) {
        return name + ", mañana tienes que acompañar a Papá Isidro a su cita médica. Revisa la hora en Familia Prado.";
    }
    public static String appointmentToday(String name) {
        return name + ", hoy tienes que acompañar a Papá Isidro a su cita médica. Revisa la hora en Familia Prado.";
    }
    public static String appointmentSoon(String name) {
        return name + ", en unas horas tienes que acompañar a Papá Isidro a su cita médica.";
    }
}
