package pe.familiaprado.app;

import java.time.Instant;
import java.time.temporal.ChronoUnit;

/** Ejecutable sin Maven: javac ... && java ...PushScheduleRulesCheck */
public final class PushScheduleRulesCheck {
    private static int checks=0;
    private static void ok(boolean value,String label) {
        checks++;
        if(!value)throw new AssertionError(label);
    }
    public static void main(String[] args) {
        Instant now=Instant.parse("2026-11-18T12:00:00Z");
        var after30=PushScheduleRules.forNewAppointment(now.plus(30,ChronoUnit.HOURS),now);
        ok(after30.size()==3,"30 h => NEW, 24H, 3H");
        ok("NEW".equals(after30.get(0).key()),"first now");
        ok(after30.get(0).at().equals(now),"immediate");
        ok(after30.get(1).at().equals(now.plus(6,ChronoUnit.HOURS)),"24 before");
        ok(after30.get(2).at().equals(now.plus(27,ChronoUnit.HOURS)),"3 before");
        var after4=PushScheduleRules.forNewAppointment(now.plus(4,ChronoUnit.HOURS),now);
        ok(after4.size()==2,"4 h => NEW, 3H");
        ok("3H".equals(after4.get(1).key()),"near trigger");
        var after2=PushScheduleRules.forNewAppointment(now.plus(2,ChronoUnit.HOURS),now);
        ok(after2.size()==1,"2 h => NEW only");
        ok(PushScheduleRules.forNewAppointment(now,now).isEmpty(),"past => none");
        ok(PushScheduleRules.forNewAppointment(now.minus(1,ChronoUnit.HOURS),now).isEmpty(),"past => none 2");
        System.out.println("PushScheduleRulesCheck: "+checks+"/"+checks+" PASS");
    }
}
