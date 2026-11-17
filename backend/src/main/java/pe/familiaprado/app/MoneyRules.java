package pe.familiaprado.app;

import java.math.BigDecimal;

/** Pure finance assertions to avoid mistakes in cash approvals. */
public final class MoneyRules {
    private MoneyRules() {}
    public static boolean canApproveExpense(BigDecimal verifiedIncome, BigDecimal approvedExpenses, BigDecimal proposed) {
        return proposed!=null && proposed.signum()>0 &&
            verifiedIncome.subtract(approvedExpenses).compareTo(proposed)>=0;
    }
    public static boolean canSubmitContribution(BigDecimal alreadySubmittedOrVerified,BigDecimal proposed,BigDecimal expected) {
        return proposed!=null && proposed.signum()>0 &&
            alreadySubmittedOrVerified.add(proposed).compareTo(expected)<=0;
    }
}
