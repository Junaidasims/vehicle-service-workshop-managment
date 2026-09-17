/**
 * ServiceItemmTriggerHandler
 *
 * Handles all trigger logic for Service_Itemm__c.
 * Uses without sharing because inventory stock management is a
 * system-level operation that must not be restricted by record
 * sharing or FLS — the trigger runs on behalf of the system,
 * not the end user.
 *
 * Business rules enforced:
 *  - Auto-populate Completed_Date__c when status becomes Completed
 *  - Validate inventory availability before deducting stock
 *  - Deduct / restore / adjust inventory stock based on Part completion state
 *  - Prevent inactive inventory usage
 *  - Bulkified — no SOQL or DML inside loops
 *  - Recursion guard to prevent re-entrant trigger execution
 */
public without sharing class ServiceItemmTriggerHandler {

    // Recursion guard — prevents re-entry when updating Inventory_Itemm__c
    private static Boolean isRunning = false;

    public static void handle() {
        if (isRunning) {
            return;
        }

        if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
            manageCompletionDate();
            validateStockAvailability();
        }

        if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
            isRunning = true;
            try {
                updateInventoryStock();
            } finally {
                isRunning = false;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // BEFORE: Auto-set Completed_Date__c
    // ─────────────────────────────────────────────────────────────
    private static void manageCompletionDate() {
        for (Service_Itemm__c item : (List<Service_Itemm__c>) Trigger.new) {
            if (item.Item_Status__c == 'Completed') {
                if (Trigger.isInsert) {
                    if (item.Completed_Date__c == null) {
                        item.Completed_Date__c = Date.today();
                    }
                } else {
                    Service_Itemm__c oldItem =
                        (Service_Itemm__c) Trigger.oldMap.get(item.Id);
                    if (oldItem.Item_Status__c != 'Completed' &&
                        item.Completed_Date__c == null) {
                        item.Completed_Date__c = Date.today();
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // BEFORE: Validate sufficient and active stock
    // ─────────────────────────────────────────────────────────────
    private static void validateStockAvailability() {
        Map<Id, Integer> stockChangeByInventory = calculateStockChanges();

        if (stockChangeByInventory.isEmpty()) {
            return;
        }

        Map<Id, Inventory_Itemm__c> inventoryMap =
            new Map<Id, Inventory_Itemm__c>([
                SELECT Id, Part_Name__c, Stock_Quantity__c, Inventory_Status__c
                FROM Inventory_Itemm__c
                WHERE Id IN :stockChangeByInventory.keySet()
                FOR UPDATE
            ]);

        for (Id inventoryId : stockChangeByInventory.keySet()) {
            Inventory_Itemm__c inv = inventoryMap.get(inventoryId);

            if (inv == null) {
                addInventoryNotFoundErrors(inventoryId);
                continue;
            }

            Integer stockChange = stockChangeByInventory.get(inventoryId);

            // Net change is a restoration or no change — no validation needed
            if (stockChange >= 0) {
                continue;
            }

            if (inv.Inventory_Status__c != 'Active') {
                addErrorToConsumingItems(
                    inventoryId,
                    'The selected Inventory Itemm "' + inv.Part_Name__c +
                    '" is not active and cannot be used.'
                );
                continue;
            }

            Integer currentStock = inv.Stock_Quantity__c == null
                ? 0
                : Integer.valueOf(inv.Stock_Quantity__c);

            Integer requiredStock = -stockChange;

            if (requiredStock > currentStock) {
                addErrorToConsumingItems(
                    inventoryId,
                    'Insufficient stock for "' + inv.Part_Name__c +
                    '". Available: ' + currentStock +
                    ', Required: ' + requiredStock + '.'
                );
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // AFTER: Apply the calculated net stock changes
    // ─────────────────────────────────────────────────────────────
    private static void updateInventoryStock() {
        Map<Id, Integer> stockChangeByInventory = calculateStockChanges();

        if (stockChangeByInventory.isEmpty()) {
            return;
        }

        List<Inventory_Itemm__c> toUpdate = new List<Inventory_Itemm__c>();

        for (Inventory_Itemm__c inv : [
            SELECT Id, Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id IN :stockChangeByInventory.keySet()
            FOR UPDATE
        ]) {
            Integer currentStock = inv.Stock_Quantity__c == null
                ? 0
                : Integer.valueOf(inv.Stock_Quantity__c);

            Integer change = stockChangeByInventory.get(inv.Id);

            inv.Stock_Quantity__c = currentStock + change;
            toUpdate.add(inv);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ─────────────────────────────────────────────────────────────
    // SHARED: Calculate net stock delta per inventory item
    //
    // Logic: for each Service_Itemm__c in the batch,
    //   - If old state = completed Part → restore old quantity (+)
    //   - If new state = completed Part → deduct new quantity (-)
    // Net of these two gives the correct adjustment.
    // ─────────────────────────────────────────────────────────────
    private static Map<Id, Integer> calculateStockChanges() {
        Map<Id, Integer> stockChangeByInventory = new Map<Id, Integer>();

        for (Service_Itemm__c item : (List<Service_Itemm__c>) Trigger.new) {
            Service_Itemm__c oldItem = null;
            if (Trigger.isUpdate) {
                oldItem = (Service_Itemm__c) Trigger.oldMap.get(item.Id);
            }

            Boolean oldWasCompleted =
                oldItem != null &&
                oldItem.Item_Type__c == 'Part' &&
                oldItem.Item_Status__c == 'Completed' &&
                oldItem.Inventory_Itemm__c != null;

            Boolean newIsCompleted =
                item.Item_Type__c == 'Part' &&
                item.Item_Status__c == 'Completed' &&
                item.Inventory_Itemm__c != null;

            // Restore old inventory if previously completed
            if (oldWasCompleted) {
                Integer oldQty = oldItem.Quantity__c == null
                    ? 0
                    : Integer.valueOf(oldItem.Quantity__c);
                addToMap(stockChangeByInventory, oldItem.Inventory_Itemm__c, +oldQty);
            }

            // Deduct new inventory if now completed
            if (newIsCompleted) {
                Integer newQty = item.Quantity__c == null
                    ? 0
                    : Integer.valueOf(item.Quantity__c);
                addToMap(stockChangeByInventory, item.Inventory_Itemm__c, -newQty);
            }
        }

        return stockChangeByInventory;
    }

    private static void addToMap(
        Map<Id, Integer> stockMap,
        Id inventoryId,
        Integer delta
    ) {
        Integer current = stockMap.get(inventoryId);
        stockMap.put(inventoryId, (current == null ? 0 : current) + delta);
    }

    private static void addErrorToConsumingItems(Id inventoryId, String msg) {
        for (Service_Itemm__c item : (List<Service_Itemm__c>) Trigger.new) {
            if (item.Inventory_Itemm__c == inventoryId &&
                item.Item_Type__c == 'Part' &&
                item.Item_Status__c == 'Completed') {
                item.addError(msg);
            }
        }
    }

    private static void addInventoryNotFoundErrors(Id inventoryId) {
        for (Service_Itemm__c item : (List<Service_Itemm__c>) Trigger.new) {
            if (item.Inventory_Itemm__c == inventoryId &&
                item.Item_Type__c == 'Part' &&
                item.Item_Status__c == 'Completed') {
                item.addError(
                    'The selected Inventory Itemm could not be found.'
                );
            }
        }
    }
}
