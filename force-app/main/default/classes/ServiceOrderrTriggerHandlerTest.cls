/**
 * ServiceOrderrTriggerHandlerTest
 *
 * Tests for ServiceOrderrTriggerHandler.
 * Covers: completion date, duplicate prevention,
 * invoice generation, bulk operations.
 */
@IsTest
private class ServiceOrderrTriggerHandlerTest {

    @TestSetup
    static void setupTestData() {
        Customerr__c customer = TestDataFactory.createCustomer(true);
        Vehiclee__c vehicle   = TestDataFactory.createVehicle(customer.Id, true);
        TestDataFactory.createServiceOrder(
            customer.Id, vehicle.Id, 'Draft', true
        );
    }

    private static Customerr__c getCustomer() {
        return [SELECT Id FROM Customerr__c LIMIT 1];
    }

    private static Vehiclee__c getVehicle() {
        return [SELECT Id FROM Vehiclee__c LIMIT 1];
    }

    private static Service_Orderr__c getOrder() {
        return [SELECT Id, Service_Status__c, Actual_Completion_Date__c
                FROM Service_Orderr__c LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────
    // Completion date is set when order becomes Completed
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testCompletionDateSetOnCompletion() {
        Service_Orderr__c order = getOrder();
        order.Service_Status__c = 'Completed';

        Test.startTest();
        update order;
        Test.stopTest();

        Service_Orderr__c updated = [
            SELECT Actual_Completion_Date__c
            FROM Service_Orderr__c
            WHERE Id = :order.Id
        ];

        System.assertEquals(
            Date.today(),
            updated.Actual_Completion_Date__c,
            'Actual Completion Date should be set to today when Completed.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Completion date is cleared when order moves away from Completed
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testCompletionDateClearedOnStatusChange() {
        Service_Orderr__c order = getOrder();
        order.Service_Status__c = 'Completed';
        update order;

        order.Service_Status__c = 'In Progress';

        Test.startTest();
        update order;
        Test.stopTest();

        Service_Orderr__c updated = [
            SELECT Actual_Completion_Date__c
            FROM Service_Orderr__c
            WHERE Id = :order.Id
        ];

        System.assertEquals(
            null,
            updated.Actual_Completion_Date__c,
            'Actual Completion Date should be cleared when status leaves Completed.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Invoice generated when order becomes Completed
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testInvoiceGeneratedOnCompletion() {
        Service_Orderr__c order = getOrder();
        order.Service_Status__c = 'Completed';

        Test.startTest();
        update order;
        Test.stopTest();

        List<Invoicee__c> invoices = [
            SELECT Id, Service_Orderr__c, Invoice_Status__c
            FROM Invoicee__c
            WHERE Service_Orderr__c = :order.Id
        ];

        System.assertEquals(
            1,
            invoices.size(),
            'Exactly one invoice should be generated when order completes.'
        );

        System.assertEquals(
            'Issued',
            invoices[0].Invoice_Status__c,
            'Auto-generated invoice status should be Issued.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Duplicate invoice not created if order already has one
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testNoDuplicateInvoice() {
        Customerr__c customer = getCustomer();
        Vehiclee__c vehicle   = getVehicle();

        Service_Orderr__c order = getOrder();
        order.Service_Status__c = 'Completed';
        update order;

        // Manually update back to Draft and re-complete
        order.Service_Status__c = 'In Progress';
        update order;
        order.Service_Status__c = 'Completed';

        Test.startTest();
        update order;
        Test.stopTest();

        List<Invoicee__c> invoices = [
            SELECT Id FROM Invoicee__c
            WHERE Service_Orderr__c = :order.Id
        ];

        System.assertEquals(
            1,
            invoices.size(),
            'Only one invoice should exist even after multiple completions.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Duplicate active order for same vehicle is blocked
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testDuplicateActiveOrderBlocked() {
        Customerr__c customer = getCustomer();
        Vehiclee__c vehicle   = getVehicle();

        // First order active
        Service_Orderr__c first = getOrder();
        first.Service_Status__c = 'Checked In';
        update first;

        // Try to create a second active order for same vehicle
        Service_Orderr__c second = new Service_Orderr__c(
            Vehiclee__c              = vehicle.Id,
            Customerr__c             = customer.Id,
            Service_Date__c          = Date.today(),
            Expected_Completion_Date__c = Date.today().addDays(2),
            Service_Status__c        = 'Checked In',
            Priority__c              = 'Normal',
            Service_Advisor__c       = UserInfo.getUserId(),
            Problem_Description__c   = 'Second service attempt',
            Customer_Approval__c     = 'Pending',
            Service_Mileage__c       = 26000
        );

        Test.startTest();
        try {
            insert second;
            System.assert(false, 'Should have thrown an error for duplicate active order.');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('active Service Orderr'),
                'Error should mention active Service Orderr. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // Bulk: multiple orders completing generates one invoice each
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testBulkCompletion() {
        Customerr__c customer = getCustomer();

        // Create 3 vehicles and draft orders
        List<Vehiclee__c> vehicles = new List<Vehiclee__c>();
        for (Integer i = 0; i < 3; i++) {
            vehicles.add(new Vehiclee__c(
                Customerr__c            = customer.Id,
                Registration_Number__c  = 'BULK-TEST-0' + i,
                VIN__c                  = 'BULKVIN00000000' + i,
                Make__c                 = 'Honda',
                Model__c                = 'City',
                Manufacturing_Year__c   = 2020,
                Vehicle_Type__c         = 'Sedan',
                Fuel_Type__c            = 'Petrol',
                Current_Mileage__c      = 10000,
                Vehicle_Status__c       = 'Active'
            ));
        }
        insert vehicles;

        List<Service_Orderr__c> orders = new List<Service_Orderr__c>();
        for (Vehiclee__c v : vehicles) {
            orders.add(new Service_Orderr__c(
                Vehiclee__c              = v.Id,
                Customerr__c             = customer.Id,
                Service_Date__c          = Date.today(),
                Expected_Completion_Date__c = Date.today().addDays(1),
                Service_Status__c        = 'Draft',
                Priority__c              = 'Normal',
                Service_Advisor__c       = UserInfo.getUserId(),
                Problem_Description__c   = 'Bulk test service',
                Customer_Approval__c     = 'Pending',
                Service_Mileage__c       = 10000
            ));
        }
        insert orders;

        for (Service_Orderr__c o : orders) {
            o.Service_Status__c = 'Completed';
        }

        Test.startTest();
        update orders;
        Test.stopTest();

        List<Invoicee__c> invoices = [
            SELECT Id FROM Invoicee__c
            WHERE Service_Orderr__c IN :orders
        ];

        System.assertEquals(
            3,
            invoices.size(),
            'Each completed order should generate exactly one invoice.'
        );
    }
}
