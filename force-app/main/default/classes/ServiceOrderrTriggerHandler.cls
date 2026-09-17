/**
 * ServiceOrderrTriggerHandler
 *
 * Handles trigger logic for Service_Orderr__c.
 *
 * Business rules:
 *  - Prevent duplicate active service orders for the same vehicle
 *  - Auto-populate Actual_Completion_Date__c when status → Completed
 *  - Clear Actual_Completion_Date__c if status moves away from Completed
 *  - Auto-generate Invoice when order becomes Completed
 *  - Bulkified — no SOQL or DML inside loops
 */
public with sharing class ServiceOrderrTriggerHandler {

    public static void handle() {
        if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
            preventDuplicateActiveOrders();
            manageCompletionDate();
        }

        if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
            generateInvoicesOnCompletion();
        }
    }

    // ─────────────────────────────────────────────────────────────
    // BEFORE: Block duplicate active orders for same vehicle
    // ─────────────────────────────────────────────────────────────
    private static void preventDuplicateActiveOrders() {
        Set<Id> vehicleIds = new Set<Id>();

        for (Service_Orderr__c order : (List<Service_Orderr__c>) Trigger.new) {
            if (order.Vehiclee__c != null) {
                vehicleIds.add(order.Vehiclee__c);
            }
        }

        if (vehicleIds.isEmpty()) {
            return;
        }

        Set<String> activeStatuses = new Set<String>{
            'Checked In',
            'Inspection',
            'Estimate Pending',
            'Approved',
            'In Progress',
            'Waiting for Parts',
            'Ready for Delivery'
        };

        // Count active orders per vehicle (excluding records being updated)
        Set<Id> updatingIds = new Set<Id>();
        if (Trigger.isUpdate) {
            for (Service_Orderr__c o : (List<Service_Orderr__c>) Trigger.old) {
                updatingIds.add(o.Id);
            }
        }

        Map<Id, Integer> activeCountByVehicle = new Map<Id, Integer>();

        for (Service_Orderr__c existing : [
            SELECT Id, Vehiclee__c
            FROM Service_Orderr__c
            WHERE Vehiclee__c IN :vehicleIds
            AND Service_Status__c IN :activeStatuses
            AND Id NOT IN :updatingIds
        ]) {
            Integer count = activeCountByVehicle.get(existing.Vehiclee__c);
            activeCountByVehicle.put(
                existing.Vehiclee__c,
                count == null ? 1 : count + 1
            );
        }

        for (Service_Orderr__c order : (List<Service_Orderr__c>) Trigger.new) {
            if (order.Vehiclee__c == null) {
                continue;
            }

            if (!activeStatuses.contains(order.Service_Status__c)) {
                continue;
            }

            Integer existingActive =
                activeCountByVehicle.get(order.Vehiclee__c);
            if (existingActive == null) {
                existingActive = 0;
            }

            if (existingActive > 0) {
                order.addError(
                    'This vehicle already has an active Service Orderr. ' +
                    'Complete or cancel the existing service order before ' +
                    'creating another.'
                );
            }

            // Track this order in the map so bulk-insert siblings are also blocked
            if (Trigger.isInsert) {
                activeCountByVehicle.put(
                    order.Vehiclee__c,
                    existingActive + 1
                );
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // BEFORE: Auto-set / clear Actual_Completion_Date__c
    // ─────────────────────────────────────────────────────────────
    private static void manageCompletionDate() {
        for (Service_Orderr__c order : (List<Service_Orderr__c>) Trigger.new) {
            if (order.Service_Status__c == 'Completed') {
                if (Trigger.isInsert) {
                    order.Actual_Completion_Date__c = Date.today();
                } else {
                    Service_Orderr__c oldOrder =
                        (Service_Orderr__c) Trigger.oldMap.get(order.Id);
                    if (oldOrder.Service_Status__c != 'Completed') {
                        // Transition into Completed — set the date
                        order.Actual_Completion_Date__c = Date.today();
                    }
                    // Already completed — preserve existing date
                }
            } else if (Trigger.isUpdate) {
                Service_Orderr__c oldOrder =
                    (Service_Orderr__c) Trigger.oldMap.get(order.Id);
                if (oldOrder.Service_Status__c == 'Completed') {
                    // Moving away from Completed — clear the date
                    order.Actual_Completion_Date__c = null;
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // AFTER: Generate invoices for newly-completed orders
    // ─────────────────────────────────────────────────────────────
    private static void generateInvoicesOnCompletion() {
        Set<Id> justCompleted = new Set<Id>();

        for (Service_Orderr__c order : (List<Service_Orderr__c>) Trigger.new) {
            if (order.Service_Status__c != 'Completed') {
                continue;
            }

            if (Trigger.isInsert) {
                justCompleted.add(order.Id);
            } else {
                Service_Orderr__c oldOrder =
                    (Service_Orderr__c) Trigger.oldMap.get(order.Id);
                if (oldOrder.Service_Status__c != 'Completed') {
                    justCompleted.add(order.Id);
                }
            }
        }

        if (!justCompleted.isEmpty()) {
            InvoiceeService.generateInvoicesForCompletedOrders(justCompleted);
        }
    }
}
