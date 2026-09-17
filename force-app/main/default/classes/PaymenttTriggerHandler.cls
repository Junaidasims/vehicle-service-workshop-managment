/**
 * PaymenttTriggerHandler
 *
 * Handles trigger logic for Paymentt__c.
 *
 * Business rules:
 *  - Prevent overpayment: completed payment amount cannot push total
 *    paid over invoice total amount
 *  - Prevent payment on cancelled invoice
 *  - After a payment is created/updated/deleted (master-detail cascade
 *    handles delete), update the Invoicee__c.Amount_Paid__c to reflect
 *    only completed payments, then re-derive Invoice_Status__c
 *  - Bulkified — no SOQL or DML inside loops
 */
public without sharing class PaymenttTriggerHandler {

    private static Boolean isRunning = false;

    public static void handle() {
        if (isRunning) {
            return;
        }

        if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
            validatePayments();
        }

        if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
            isRunning = true;
            try {
                syncInvoicePaymentState();
            } finally {
                isRunning = false;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // BEFORE: Validate payment rules
    // ─────────────────────────────────────────────────────────────
    private static void validatePayments() {
        // Collect invoice IDs involved in completed payments being created/updated
        Set<Id> invoiceIds = new Set<Id>();
        for (Paymentt__c pmt : (List<Paymentt__c>) Trigger.new) {
            if (pmt.Invoicee__c != null) {
                invoiceIds.add(pmt.Invoicee__c);
            }
        }

        if (invoiceIds.isEmpty()) {
            return;
        }

        Map<Id, Invoicee__c> invoiceMap = new Map<Id, Invoicee__c>([
            SELECT Id, Invoice_Status__c, Total_Amount__c, Total_Payments__c
            FROM Invoicee__c
            WHERE Id IN :invoiceIds
        ]);

        for (Paymentt__c pmt : (List<Paymentt__c>) Trigger.new) {
            if (pmt.Invoicee__c == null) {
                continue;
            }

            Invoicee__c inv = invoiceMap.get(pmt.Invoicee__c);
            if (inv == null) {
                continue;
            }

            // Block payment on cancelled invoice
            if (inv.Invoice_Status__c == 'Cancelled') {
                pmt.addError(
                    'Payments cannot be added to a cancelled invoice.'
                );
                continue;
            }

            // Check overpayment for completed payments
            if (pmt.Payment_Status__c == 'Completed') {
                Decimal totalAmount = inv.Total_Amount__c == null ? 0 : inv.Total_Amount__c;
                Decimal existingCompleted = inv.Total_Payments__c == null
                    ? 0
                    : inv.Total_Payments__c;

                // Subtract old amount if this is an update to a completed payment
                if (Trigger.isUpdate) {
                    Paymentt__c oldPmt =
                        (Paymentt__c) Trigger.oldMap.get(pmt.Id);
                    if (oldPmt.Payment_Status__c == 'Completed') {
                        Decimal oldAmt = oldPmt.Payment_Amount__c == null
                            ? 0
                            : oldPmt.Payment_Amount__c;
                        existingCompleted -= oldAmt;
                    }
                }

                Decimal newPaymentAmt = pmt.Payment_Amount__c == null
                    ? 0
                    : pmt.Payment_Amount__c;

                if (existingCompleted + newPaymentAmt > totalAmount) {
                    pmt.addError(
                        'This payment would exceed the invoice total of ' +
                        totalAmount.format() +
                        '. Maximum additional payment allowed: ' +
                        (totalAmount - existingCompleted).format() + '.'
                    );
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // AFTER: Sync Invoice Amount_Paid and Status after payment change
    // ─────────────────────────────────────────────────────────────
    private static void syncInvoicePaymentState() {
        Set<Id> invoiceIds = new Set<Id>();
        for (Paymentt__c pmt : (List<Paymentt__c>) Trigger.new) {
            if (pmt.Invoicee__c != null) {
                invoiceIds.add(pmt.Invoicee__c);
            }
        }

        if (invoiceIds.isEmpty()) {
            return;
        }

        // Aggregate completed payments per invoice
        Map<Id, Decimal> completedByInvoice = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Invoicee__c invId, SUM(Payment_Amount__c) total
            FROM Paymentt__c
            WHERE Invoicee__c IN :invoiceIds
            AND Payment_Status__c = 'Completed'
            GROUP BY Invoicee__c
        ]) {
            completedByInvoice.put(
                (Id) ar.get('invId'),
                (Decimal) ar.get('total')
            );
        }

        Map<Id, Invoicee__c> invoiceMap = new Map<Id, Invoicee__c>([
            SELECT Id, Invoice_Status__c, Total_Amount__c,
                   Amount_Paid__c, Due_Date__c
            FROM Invoicee__c
            WHERE Id IN :invoiceIds
        ]);

        List<Invoicee__c> toUpdate = new List<Invoicee__c>();

        for (Id invId : invoiceIds) {
            Invoicee__c inv = invoiceMap.get(invId);
            if (inv == null) {
                continue;
            }

            // Do not touch cancelled invoices
            if (inv.Invoice_Status__c == 'Cancelled') {
                continue;
            }

            Decimal completedPaid = completedByInvoice.get(invId);
            if (completedPaid == null) {
                completedPaid = 0;
            }

            Decimal totalAmount = inv.Total_Amount__c == null
                ? 0
                : inv.Total_Amount__c;

            String newStatus = inv.Invoice_Status__c;
            if (totalAmount > 0) {
                if (completedPaid >= totalAmount) {
                    newStatus = 'Paid';
                } else if (completedPaid > 0) {
                    newStatus = 'Partially Paid';
                } else if (
                    inv.Due_Date__c != null &&
                    inv.Due_Date__c < Date.today() &&
                    inv.Invoice_Status__c != 'Draft'
                ) {
                    newStatus = 'Overdue';
                } else if (inv.Invoice_Status__c == 'Partially Paid' ||
                           inv.Invoice_Status__c == 'Paid') {
                    // Was paid/partial but now no completed payments
                    newStatus = 'Issued';
                }
            }

            Boolean dirty = false;
            Invoicee__c toSave = new Invoicee__c(Id = inv.Id);

            if (inv.Amount_Paid__c != completedPaid) {
                toSave.Amount_Paid__c = completedPaid;
                dirty = true;
            }

            if (inv.Invoice_Status__c != newStatus) {
                toSave.Invoice_Status__c = newStatus;
                dirty = true;
            }

            if (dirty) {
                toUpdate.add(toSave);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
