/**
 * InvoiceeService
 *
 * Handles invoice generation logic for Service_Orderr__c.
 *
 * Invoked by ServiceOrderrTriggerHandler when a Service Orderr
 * transitions to "Completed".
 *
 * Demonstrates:
 *  - Aggregate SOQL (sum of service item amounts)
 *  - Relationship SOQL (child-to-parent and parent-to-child)
 *  - Bulkification (Set/Map/List, no SOQL or DML in loops)
 *  - Duplicate invoice prevention
 */
public without sharing class InvoiceeService {

    /**
     * Generate invoices for newly-completed service orders.
     * Only creates an invoice if one does not already exist.
     *
     * @param completedOrderIds  Set of Service_Orderr__c IDs that just became Completed
     */
    public static void generateInvoicesForCompletedOrders(
        Set<Id> completedOrderIds
    ) {
        if (completedOrderIds == null || completedOrderIds.isEmpty()) {
            return;
        }

        // Find orders that already have an invoice (prevent duplicates)
        Set<Id> alreadyInvoiced = new Set<Id>();
        for (Invoicee__c existing : [
            SELECT Service_Orderr__c
            FROM Invoicee__c
            WHERE Service_Orderr__c IN :completedOrderIds
        ]) {
            alreadyInvoiced.add(existing.Service_Orderr__c);
        }

        // Load the service orders with related vehicle and customer
        Map<Id, Service_Orderr__c> orderMap = new Map<Id, Service_Orderr__c>([
            SELECT Id,
                   Customerr__c,
                   Vehiclee__c,
                   Service_Date__c,
                   Total_Subtotal__c,
                   Total_Discount__c,
                   Total_Tax__c,
                   Total_Amount__c
            FROM Service_Orderr__c
            WHERE Id IN :completedOrderIds
        ]);

        List<Invoicee__c> toInsert = new List<Invoicee__c>();

        for (Id orderId : completedOrderIds) {
            if (alreadyInvoiced.contains(orderId)) {
                continue;
            }

            Service_Orderr__c order = orderMap.get(orderId);
            if (order == null) {
                continue;
            }

            Invoicee__c invoice = new Invoicee__c(
                Service_Orderr__c = orderId,
                Customerr__c      = order.Customerr__c,
                Vehiclee__c       = order.Vehiclee__c,
                Invoice_Date__c   = Date.today(),
                Invoice_Status__c = 'Issued',
                Payment_Terms__c  = 'Due on Receipt',
                Subtotal__c       = order.Total_Subtotal__c,
                Discount_Amount__c = order.Total_Discount__c,
                Tax_Amount__c     = order.Total_Tax__c,
                Total_Amount__c   = order.Total_Amount__c,
                Amount_Paid__c    = 0,
                Due_Date__c       = Date.today()
            );

            toInsert.add(invoice);
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
}
