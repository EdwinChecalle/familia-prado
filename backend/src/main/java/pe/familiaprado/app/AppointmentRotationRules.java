package pe.familiaprado.app;

import java.util.List;
import java.util.UUID;

public final class AppointmentRotationRules {
    private AppointmentRotationRules() {}
    public record Member(UUID id,String name,int position,boolean active) {}
    public static Member next(List<Member> order,int position) {
        for(int i=0;i<8;i++) {
            int p=(position-1+i)%8+1;
            for(Member member:order) if(member.position()==p && member.active()) return member;
        }
        return null;
    }
    public static boolean advances(Member suggested,UUID actual) {
        return suggested!=null && suggested.id().equals(actual);
    }
    public static int following(int position) {return position%8+1;}
}
