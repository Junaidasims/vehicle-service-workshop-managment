/**
 * InvoiceeTriggerHandler
 *
 * Handles trigger logic for Invoicee__c.
 *
 * Business rules:
 *  - Auto-update Invoice Status based on payment state (via Amount_Paid__c)
 *  - Amount_Paid__c is kept in sync from Total_Payments__c (completed payments)
 *    by PaymenttTriggerHandler; Invoicee only re-derives status here.
 *  - Prevent cancelled invoices from receiving payments (enforced in Paymentt handler)
 *  - Calculate Due Date when Invoice Date and Payment Terms are set
 */
public without sharing class InvoiceeTriggerHandler {

    public static void handle() {
        if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
            calculateDueDate();
            syncAmountPaid();
            deriveInvoiceStatus();
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Auto-calculate Due Date from Invoice Date + Payment Terms
    // ─────────────────────────────────────────────────────────────
    private static void calculateDueDate() {
        for (Invoicee__c inv : (List<Invoicee__c>) Trigger.new) {
            if (inv.Invoice_Date__c == null || inv.Payment_Terms__c == null) {
                continue;
            }

            Invoicee__c oldInv = Trigger.isUpdate
                ? (Invoicee__c) Trigger.oldMap.get(inv.Id)
                : null;

            Boolean changed = oldInv == null
                || inv.Invoice_Date__c != oldInv.Invoice_Date__c
                || inv.Payment_Terms__c != oldInv.Payment_Terms__c;

            if (!changed) {
                continue;
            }

            Integer days = 0;
            if (inv.Payment_Terms__c == 'Due on Receipt') {
                days = 0;
            } else if (inv.Payment_Terms__c == '7 Days') {
                days = 7;
            } else if (inv.Payment_Terms__c == '15 Days') {
                days = 15;
            } else if (inv.Payment_Terms__c == '30 Days') {
                days = 30;
            }

            inv.Due_Date__c = inv.Invoice_Date__c.addDays(days);
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Sync Amount_Paid__c from Total_Payments__c (roll-up)
    // Called from PaymenttTriggerHandler after roll-up updates
    // Also called in before-context to ensure Amount_Paid is current
    // ─────────────────────────────────────────────────────────────
    private static void syncAmountPaid() {
        for (Invoicee__c inv : (List<Invoicee__c>) Trigger.new) {
            // Total_Payments__c is a roll-up (read-only in triggers)
            // Amount_Paid__c is set by Paymentt trigger; nothing to sync here
            // This method is a hook for future explicit sync if needed
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Derive Invoice Status from payment amounts
    // Uses Amount_Paid__c which is maintained by PaymenttTriggerHandler
    // ─────────────────────────────────────────────────────────────
    private static void deriveInvoiceStatus() {
        for (Invoicee__c inv : (List<Invoicee__c>) Trigger.new) {
            // Do not override Cancelled status automatically
            if (inv.Invoice_Status__c == 'Cancelled') {
                continue;
            }

            // Only derive status for Issued/Partially Paid/Paid/Overdue
            if (inv.Invoice_Status__c == 'Draft') {
                continue;
            }

            if (inv.Total_Amount__c == null || inv.Total_Amount__c == 0) {
                continue;
            }

            Decimal amountPaid = inv.Amount_Paid__c == null
                ? 0
                : inv.Amount_Paid__c;
            Decimal totalAmount = inv.Total_Amount__c;
            Date dueDate = inv.Due_Date__c;

            if (amountPaid >= totalAmount) {
                inv.Invoice_Status__c = 'Paid';
            } else if (amountPaid > 0 && amountPaid < totalAmount) {
                inv.Invoice_Status__c = 'Partially Paid';
            } else if (
                amountPaid == 0 &&
                dueDate != null &&
                dueDate < Date.today() &&
                inv.Invoice_Status__c != 'Draft'
            ) {
                inv.Invoice_Status__c = 'Overdue';
            }
        }
    }
}
