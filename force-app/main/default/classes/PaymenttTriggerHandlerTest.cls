/**
 * PaymenttTriggerHandlerTest
 *
 * Tests for PaymenttTriggerHandler and invoice payment state.
 * Covers: partial payments, full payment, overpayment prevention,
 * cancelled invoice, failed/refunded payments, bulk operations.
 */
@IsTest
private class PaymenttTriggerHandlerTest {

    @TestSetup
    static void setupTestData() {
        Customerr__c customer = TestDataFactory.createCustomer(true);
        Vehiclee__c  vehicle  = TestDataFactory.createVehicle(customer.Id, true);
        Service_Orderr__c order = TestDataFactory.createServiceOrder(
            customer.Id, vehicle.Id, 'Draft', true
        );
        TestDataFactory.createInvoice(
            order.Id, customer.Id, vehicle.Id, 5000, true
        );
    }

    private static Invoicee__c getInvoice() {
        return [
            SELECT Id, Invoice_Status__c, Total_Amount__c,
                   Amount_Paid__c, Balance_Due__c
            FROM Invoicee__c
            LIMIT 1
        ];
    }

    // ─────────────────────────────────────────────────────────────
    // Partial payment → status = Partially Paid
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testPartialPaymentSetsPartiallyPaid() {
        Invoicee__c invoice = getInvoice();

        Test.startTest();
        TestDataFactory.createPayment(invoice.Id, 2000, 'Completed', true);
        Test.stopTest();

        Invoicee__c updated = [
            SELECT Invoice_Status__c, Amount_Paid__c
            FROM Invoicee__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            'Partially Paid',
            updated.Invoice_Status__c,
            'Invoice should be Partially Paid after a partial payment.'
        );

        System.assertEquals(
            2000,
            updated.Amount_Paid__c,
            'Amount Paid should reflect the completed payment.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Full payment → status = Paid
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testFullPaymentSetsPaid() {
        Invoicee__c invoice = getInvoice();

        Test.startTest();
        TestDataFactory.createPayment(invoice.Id, 5000, 'Completed', true);
        Test.stopTest();

        Invoicee__c updated = [
            SELECT Invoice_Status__c, Amount_Paid__c
            FROM Invoicee__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            'Paid',
            updated.Invoice_Status__c,
            'Invoice should be Paid after full payment.'
        );

        System.assertEquals(
            5000,
            updated.Amount_Paid__c,
            'Amount Paid should match total amount.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Overpayment is blocked
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testOverpaymentIsBlocked() {
        Invoicee__c invoice = getInvoice();

        Test.startTest();
        try {
            TestDataFactory.createPayment(invoice.Id, 6000, 'Completed', true);
            System.assert(false, 'Should have thrown for overpayment.');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('exceed the invoice total') ||
                e.getMessage().contains('exceed'),
                'Error should indicate overpayment. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // Failed/Pending/Refunded/Cancelled payments do NOT count
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testNonCompletedPaymentsDoNotCountTowardBalance() {
        Invoicee__c invoice = getInvoice();

        Test.startTest();
        // Pending payment
        TestDataFactory.createPayment(invoice.Id, 2000, 'Pending', true);
        // Failed payment
        TestDataFactory.createPayment(invoice.Id, 1000, 'Failed', true);
        Test.stopTest();

        Invoicee__c updated = [
            SELECT Invoice_Status__c, Amount_Paid__c
            FROM Invoicee__c
            WHERE Id = :invoice.Id
        ];

        // Status should not change to Partially Paid since none are Completed
        System.assertNotEquals(
            'Partially Paid',
            updated.Invoice_Status__c,
            'Non-completed payments should not change invoice status.'
        );

        System.assertEquals(
            0,
            updated.Amount_Paid__c == null ? 0 : updated.Amount_Paid__c,
            'Amount Paid should not include non-completed payments.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Cancelled invoice cannot receive payment
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testCancelledInvoiceBlocksPayment() {
        Invoicee__c invoice = getInvoice();

        // Cancel the invoice first
        invoice.Invoice_Status__c = 'Cancelled';
        update invoice;

        Test.startTest();
        try {
            TestDataFactory.createPayment(invoice.Id, 1000, 'Completed', true);
            System.assert(false, 'Should have thrown for cancelled invoice.');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('cancelled invoice'),
                'Error should mention cancelled invoice. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // Two partial payments together reach full payment
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testTwoPartialPaymentsCompleteFull() {
        Invoicee__c invoice = getInvoice();

        TestDataFactory.createPayment(invoice.Id, 3000, 'Completed', true);

        Test.startTest();
        TestDataFactory.createPayment(invoice.Id, 2000, 'Completed', true);
        Test.stopTest();

        Invoicee__c updated = [
            SELECT Invoice_Status__c, Amount_Paid__c
            FROM Invoicee__c
            WHERE Id = :invoice.Id
        ];

        System.assertEquals(
            'Paid',
            updated.Invoice_Status__c,
            'Invoice should be Paid when two payments together cover the total.'
        );

        System.assertEquals(
            5000,
            updated.Amount_Paid__c,
            'Amount paid should be the sum of both completed payments.'
        );
    }

    // ─────────────────────────────────────────────────────────────
    // Refunded payment: notes required (validation rule)
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testRefundedPaymentRequiresNotes() {
        Invoicee__c invoice = getInvoice();

        Paymentt__c payment = new Paymentt__c(
            Invoicee__c        = invoice.Id,
            Payment_Date__c    = Date.today(),
            Payment_Amount__c  = 1000,
            Payment_Method__c  = 'Cash',
            Payment_Status__c  = 'Refunded'
            // Notes__c deliberately omitted
        );

        Test.startTest();
        try {
            insert payment;
            System.assert(false, 'Should have required notes for refunded payment.');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Notes') ||
                e.getMessage().contains('refunded'),
                'Error should require notes. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────
    // Bulk payments on separate invoices
    // ─────────────────────────────────────────────────────────────
    @IsTest
    static void testBulkPayments() {
        Customerr__c customer = [SELECT Id FROM Customerr__c LIMIT 1];
        Vehiclee__c  vehicle  = [SELECT Id FROM Vehiclee__c  LIMIT 1];

        // Create 3 service orders and invoices
        List<Service_Orderr__c> orders = new List<Service_Orderr__c>();
        for (Integer i = 0; i < 3; i++) {
            orders.add(new Service_Orderr__c(
                Vehiclee__c              = vehicle.Id,
                Customerr__c             = customer.Id,
                Service_Date__c          = Date.today().addDays(i),
                Expected_Completion_Date__c = Date.today().addDays(i + 2),
                Service_Status__c        = 'Completed',
                Priority__c              = 'Normal',
                Service_Advisor__c       = UserInfo.getUserId(),
                Problem_Description__c   = 'Bulk test ' + i,
                Customer_Approval__c     = 'Pending',
                Service_Mileage__c       = 25000 + i
            ));
        }
        insert orders;

        List<Invoicee__c> invoices = new List<Invoicee__c>();
        for (Service_Orderr__c o : orders) {
            invoices.add(new Invoicee__c(
                Service_Orderr__c = o.Id,
                Customerr__c      = customer.Id,
                Vehiclee__c       = vehicle.Id,
                Invoice_Date__c   = Date.today(),
                Due_Date__c       = Date.today().addDays(7),
                Invoice_Status__c = 'Issued',
                Payment_Terms__c  = '7 Days',
                Total_Amount__c   = 1000,
                Amount_Paid__c    = 0
            ));
        }
        insert invoices;

        // Build bulk payment list
        List<Paymentt__c> payments = new List<Paymentt__c>();
        for (Invoicee__c inv : invoices) {
            payments.add(new Paymentt__c(
                Invoicee__c       = inv.Id,
                Payment_Date__c   = Date.today(),
                Payment_Amount__c = 1000,
                Payment_Method__c = 'Cash',
                Payment_Status__c = 'Completed'
            ));
        }

        Test.startTest();
        insert payments;
        Test.stopTest();

        List<Invoicee__c> updated = [
            SELECT Invoice_Status__c
            FROM Invoicee__c
            WHERE Id IN :invoices
        ];

        for (Invoicee__c inv : updated) {
            System.assertEquals(
                'Paid',
                inv.Invoice_Status__c,
                'Each invoice should be Paid after full bulk payment.'
            );
        }
    }
}
