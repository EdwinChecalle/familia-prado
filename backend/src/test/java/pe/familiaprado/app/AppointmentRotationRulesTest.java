package pe.familiaprado.app;
import static org.junit.jupiter.api.Assertions.*;
import java.util.*;
import org.junit.jupiter.api.Test;
class AppointmentRotationRulesTest {
    private final UUID a=UUID.randomUUID(),b=UUID.randomUUID(),c=UUID.randomUUID();
    private final List<AppointmentRotationRules.Member> order=List.of(
        new AppointmentRotationRules.Member(a,"A",1,true),new AppointmentRotationRules.Member(b,"B",2,false),new AppointmentRotationRules.Member(c,"C",3,true));
    @Test void suggestionAndWrap(){assertEquals(a,AppointmentRotationRules.next(order,1).id());assertEquals(c,AppointmentRotationRules.next(order,2).id());assertEquals(a,AppointmentRotationRules.next(order,4).id());assertEquals(1,AppointmentRotationRules.following(8));}
    @Test void replacementDoesNotAdvance(){var suggested=AppointmentRotationRules.next(order,1);assertFalse(AppointmentRotationRules.advances(suggested,c));assertTrue(AppointmentRotationRules.advances(suggested,a));}
    @Test void noActiveMember(){assertNull(AppointmentRotationRules.next(List.of(),1));assertFalse(AppointmentRotationRules.advances(null,a));}
}
