package pe.familiaprado.app;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class MoneyRulesTest {
  @Test void cannotSpendUnverifiedOrMoreThanBalance() {
    assertTrue(MoneyRules.canApproveExpense(new BigDecimal("800"),new BigDecimal("350"),new BigDecimal("450")));
    assertFalse(MoneyRules.canApproveExpense(new BigDecimal("800"),new BigDecimal("350"),new BigDecimal("450.01")));
  }
  @Test void cannotExceedPerPersonContribution() {
    assertTrue(MoneyRules.canSubmitContribution(new BigDecimal("40"),new BigDecimal("60"),new BigDecimal("100")));
    assertFalse(MoneyRules.canSubmitContribution(new BigDecimal("40"),new BigDecimal("61"),new BigDecimal("100")));
  }
}
