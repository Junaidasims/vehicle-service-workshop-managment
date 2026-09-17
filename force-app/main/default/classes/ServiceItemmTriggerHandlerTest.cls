@IsTest
private class ServiceItemmTriggerHandlerTest {

    @TestSetup
    static void setupTestData() {
        Customerr__c customer = new Customerr__c(
            Customer_Status__c = 'Active',
            Customer_Type__c = 'Individual',
            Phone__c = '9876543210',
            Email__c = 'test@example.com'
        );
        insert customer;

        Vehiclee__c vehicle = new Vehiclee__c(
            Customerr__c = customer.Id,
            Registration_Number__c = 'TS09TEST01',
            VIN__c = 'TESTVIN123456789',
            Make__c = 'Toyota',
            Model__c = 'Innova',
            Manufacturing_Year__c = 2022,
            Vehicle_Type__c = 'MUV',
            Fuel_Type__c = 'Diesel',
            Current_Mileage__c = 25000,
            Vehicle_Status__c = 'Active'
        );
        insert vehicle;

        Service_Orderr__c serviceOrder = new Service_Orderr__c(
            Vehiclee__c = vehicle.Id,
            Customerr__c = customer.Id,
            Service_Date__c = Date.today(),
            Expected_Completion_Date__c = Date.today().addDays(2),
            Actual_Completion_Date__c = Date.today(),
            Service_Status__c = 'Draft',
            Priority__c = 'Normal',
            Service_Advisor__c = UserInfo.getUserId(),
            Problem_Description__c = 'Routine vehicle service',
            Customer_Approval__c = 'Pending',
            Service_Mileage__c = 25000
        );
        insert serviceOrder;

        Inventory_Itemm__c brakePart = new Inventory_Itemm__c(
            Part_Name__c = 'Brake Pad',
            Part_Category__c = 'Brakes',
            Part_Number__c = 'BP-TEST-001',
            Unit_Cost__c = 1000,
            Selling_Price__c = 1500,
            Stock_Quantity__c = 10,
            Reorder_Level__c = 3,
            Inventory_Status__c = 'Active'
        );

        Inventory_Itemm__c oilFilter = new Inventory_Itemm__c(
            Part_Name__c = 'Oil Filter',
            Part_Category__c = 'Filters',
            Part_Number__c = 'OF-TEST-001',
            Unit_Cost__c = 300,
            Selling_Price__c = 500,
            Stock_Quantity__c = 10,
            Reorder_Level__c = 2,
            Inventory_Status__c = 'Active'
        );

        insert new List<Inventory_Itemm__c>{
            brakePart,
            oilFilter
        };
    }

    private static Service_Orderr__c getServiceOrder() {
        return [
            SELECT Id
            FROM Service_Orderr__c
            LIMIT 1
        ];
    }

    private static Inventory_Itemm__c getInventoryItem(String partNumber) {
        return [
            SELECT Id, Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Part_Number__c = :partNumber
            LIMIT 1
        ];
    }

    @IsTest
    static void testCompletedPartDeductsStock() {
        Service_Orderr__c serviceOrder = getServiceOrder();
        Inventory_Itemm__c inventoryItem =
            getInventoryItem('BP-TEST-001');

        Service_Itemm__c item = new Service_Itemm__c(
            Service_Orderr__c = serviceOrder.Id,
            Item_Type__c = 'Part',
            Item_Name__c = 'Brake Pad',
            Quantity__c = 3,
            Unit_Price__c = 1500,
            Inventory_Itemm__c = inventoryItem.Id,
            Item_Status__c = 'Completed'
        );

        Test.startTest();
        insert item;
        Test.stopTest();

        Inventory_Itemm__c updatedInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :inventoryItem.Id
        ];

        Service_Itemm__c insertedItem = [
            SELECT Completed_Date__c
            FROM Service_Itemm__c
            WHERE Id = :item.Id
        ];

        System.assertEquals(
            7,
            Integer.valueOf(updatedInventory.Stock_Quantity__c),
            'Stock should decrease by the completed quantity.'
        );

        System.assertEquals(
            Date.today(),
            insertedItem.Completed_Date__c,
            'Completed Date should be populated automatically.'
        );
    }

    @IsTest
    static void testInsufficientStockIsBlocked() {
        Service_Orderr__c serviceOrder = getServiceOrder();
        Inventory_Itemm__c inventoryItem =
            getInventoryItem('BP-TEST-001');

        Service_Itemm__c item = new Service_Itemm__c(
            Service_Orderr__c = serviceOrder.Id,
            Item_Type__c = 'Part',
            Item_Name__c = 'Brake Pad',
            Quantity__c = 11,
            Unit_Price__c = 1500,
            Inventory_Itemm__c = inventoryItem.Id,
            Item_Status__c = 'Completed'
        );

        Test.startTest();

        try {
            insert item;
            System.assert(
                false,
                'The transaction should fail because stock is insufficient.'
            );
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Insufficient stock'),
                'The error should explain that stock is insufficient.'
            );
        }

        Test.stopTest();

        Inventory_Itemm__c unchangedInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :inventoryItem.Id
        ];

        System.assertEquals(
            10,
            Integer.valueOf(unchangedInventory.Stock_Quantity__c),
            'Stock should remain unchanged after a failed transaction.'
        );
    }

    @IsTest
    static void testCompletedQuantityChangeAdjustsStock() {
        Service_Orderr__c serviceOrder = getServiceOrder();
        Inventory_Itemm__c inventoryItem =
            getInventoryItem('BP-TEST-001');

        Service_Itemm__c item = new Service_Itemm__c(
            Service_Orderr__c = serviceOrder.Id,
            Item_Type__c = 'Part',
            Item_Name__c = 'Brake Pad',
            Quantity__c = 3,
            Unit_Price__c = 1500,
            Inventory_Itemm__c = inventoryItem.Id,
            Item_Status__c = 'Completed'
        );

        insert item;

        // Re-query to get a clean sObject — avoids formula field write errors
        Service_Itemm__c toUpdate = new Service_Itemm__c(
            Id = item.Id,
            Quantity__c = 5
        );

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        Inventory_Itemm__c updatedInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :inventoryItem.Id
        ];

        System.assertEquals(
            5,
            Integer.valueOf(updatedInventory.Stock_Quantity__c),
            'Only the additional quantity should be deducted.'
        );
    }

    @IsTest
    static void testCompletedToInProgressRestoresStock() {
        Service_Orderr__c serviceOrder = getServiceOrder();
        Inventory_Itemm__c inventoryItem =
            getInventoryItem('BP-TEST-001');

        Service_Itemm__c item = new Service_Itemm__c(
            Service_Orderr__c = serviceOrder.Id,
            Item_Type__c = 'Part',
            Item_Name__c = 'Brake Pad',
            Quantity__c = 4,
            Unit_Price__c = 1500,
            Inventory_Itemm__c = inventoryItem.Id,
            Item_Status__c = 'Completed'
        );

        insert item;

        // Use clean sObject for update to avoid formula field write errors
        Service_Itemm__c toUpdate = new Service_Itemm__c(
            Id = item.Id,
            Item_Status__c = 'In Progress'
        );

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        Inventory_Itemm__c updatedInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :inventoryItem.Id
        ];

        Service_Itemm__c updatedItem = [
            SELECT Completed_Date__c
            FROM Service_Itemm__c
            WHERE Id = :item.Id
        ];

        System.assertEquals(
            10,
            Integer.valueOf(updatedInventory.Stock_Quantity__c),
            'Stock should be restored when a completed item becomes non-completed.'
        );

        System.assertEquals(
            Date.today(),
            updatedItem.Completed_Date__c,
            'Completed Date should remain as historical completion information.'
        );
    }

    @IsTest
    static void testChangingInventoryRestoresOldAndDeductsNewStock() {
        Service_Orderr__c serviceOrder = getServiceOrder();

        Inventory_Itemm__c oldInventory =
            getInventoryItem('BP-TEST-001');

        Inventory_Itemm__c newInventory =
            getInventoryItem('OF-TEST-001');

        Service_Itemm__c item = new Service_Itemm__c(
            Service_Orderr__c = serviceOrder.Id,
            Item_Type__c = 'Part',
            Item_Name__c = 'Brake Pad',
            Quantity__c = 3,
            Unit_Price__c = 1500,
            Inventory_Itemm__c = oldInventory.Id,
            Item_Status__c = 'Completed'
        );

        insert item;

        // Use clean sObject for update — avoids formula field write errors
        Service_Itemm__c toUpdate = new Service_Itemm__c(
            Id = item.Id,
            Inventory_Itemm__c = newInventory.Id
        );

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        Inventory_Itemm__c updatedOldInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :oldInventory.Id
        ];

        Inventory_Itemm__c updatedNewInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :newInventory.Id
        ];

        System.assertEquals(
            10,
            Integer.valueOf(updatedOldInventory.Stock_Quantity__c),
            'Old inventory stock should be restored.'
        );

        System.assertEquals(
            7,
            Integer.valueOf(updatedNewInventory.Stock_Quantity__c),
            'New inventory stock should be deducted.'
        );
    }

    @IsTest
    static void testBulkCompletedParts() {
        Service_Orderr__c serviceOrder = getServiceOrder();
        Inventory_Itemm__c inventoryItem =
            getInventoryItem('BP-TEST-001');

        List<Service_Itemm__c> items =
            new List<Service_Itemm__c>();

        for (Integer i = 1; i <= 2; i++) {
            items.add(new Service_Itemm__c(
                Service_Orderr__c = serviceOrder.Id,
                Item_Type__c = 'Part',
                Item_Name__c = 'Brake Pad ' + i,
                Quantity__c = 3,
                Unit_Price__c = 1500,
                Inventory_Itemm__c = inventoryItem.Id,
                Item_Status__c = 'Completed'
            ));
        }

        Test.startTest();
        insert items;
        Test.stopTest();

        Inventory_Itemm__c updatedInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :inventoryItem.Id
        ];

        System.assertEquals(
            4,
            Integer.valueOf(updatedInventory.Stock_Quantity__c),
            'Bulk processing should deduct the combined quantity.'
        );
    }

    @IsTest
    static void testServiceItemDoesNotAffectInventory() {
        Service_Orderr__c serviceOrder = getServiceOrder();
        Inventory_Itemm__c inventoryItem =
            getInventoryItem('BP-TEST-001');

        Service_Itemm__c item = new Service_Itemm__c(
            Service_Orderr__c = serviceOrder.Id,
            Item_Type__c = 'Service',
            Item_Name__c = 'Engine Oil Change',
            Quantity__c = 1,
            Unit_Price__c = 1000,
            Item_Status__c = 'Completed'
        );

        Test.startTest();
        insert item;
        Test.stopTest();

        Inventory_Itemm__c unchangedInventory = [
            SELECT Stock_Quantity__c
            FROM Inventory_Itemm__c
            WHERE Id = :inventoryItem.Id
        ];

        System.assertEquals(
            10,
            Integer.valueOf(unchangedInventory.Stock_Quantity__c),
            'Service items should not change inventory stock.'
        );
    }

    @IsTest
    static void testSimpleUpdateDiagnostic() {
        Service_Orderr__c serviceOrder = getServiceOrder();
        Inventory_Itemm__c inventoryItem =
            getInventoryItem('BP-TEST-001');

        Service_Itemm__c item = new Service_Itemm__c(
            Service_Orderr__c = serviceOrder.Id,
            Item_Type__c = 'Part',
            Item_Name__c = 'Diagnostic Brake Pad',
            Quantity__c = 2,
            Unit_Price__c = 1500,
            Inventory_Itemm__c = inventoryItem.Id,
            Item_Status__c = 'In Progress'
        );

        insert item;

        // Use clean sObject — do not carry formula fields from the insert result
        Service_Itemm__c toUpdate = new Service_Itemm__c(
            Id = item.Id,
            Quantity__c = 3
        );

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        Service_Itemm__c updatedItem = [
            SELECT Quantity__c
            FROM Service_Itemm__c
            WHERE Id = :item.Id
        ];

        System.assertEquals(
            3,
            Integer.valueOf(updatedItem.Quantity__c),
            'Quantity should be updated successfully.'
        );
    }
}