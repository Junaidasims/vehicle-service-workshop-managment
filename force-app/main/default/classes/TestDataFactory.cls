/**
 * TestDataFactory
 *
 * Centralised test data factory for all test classes.
 * Ensures consistent, reusable test records across the project.
 */
@IsTest
public class TestDataFactory {

    // ─── Customer ───────────────────────────────────────────────
    public static Customerr__c createCustomer(Boolean doInsert) {
        Customerr__c c = new Customerr__c(
            Customer_Status__c = 'Active',
            Customer_Type__c   = 'Individual',
            Phone__c           = '9876543210',
            Email__c           = 'testcustomer@example.com'
        );
        if (doInsert) insert c;
        return c;
    }

    // ─── Vehicle ─────────────────────────────────────────────────
    public static Vehiclee__c createVehicle(Id customerId, Boolean doInsert) {
        Vehiclee__c v = new Vehiclee__c(
            Customerr__c            = customerId,
            Registration_Number__c  = 'TS09TEST01',
            VIN__c                  = 'TESTVIN12345678A',
            Make__c                 = 'Toyota',
            Model__c                = 'Innova',
            Manufacturing_Year__c   = 2022,
            Vehicle_Type__c         = 'MUV',
            Fuel_Type__c            = 'Diesel',
            Current_Mileage__c      = 25000,
            Vehicle_Status__c       = 'Active'
        );
        if (doInsert) insert v;
        return v;
    }

    // ─── Service Order ───────────────────────────────────────────
    public static Service_Orderr__c createServiceOrder(
        Id customerId,
        Id vehicleId,
        String status,
        Boolean doInsert
    ) {
        Service_Orderr__c so = new Service_Orderr__c(
            Vehiclee__c                 = vehicleId,
            Customerr__c                = customerId,
            Service_Date__c             = Date.today(),
            Expected_Completion_Date__c = Date.today().addDays(2),
            Service_Status__c           = status,
            Priority__c                 = 'Normal',
            Service_Advisor__c          = UserInfo.getUserId(),
            Problem_Description__c      = 'Routine vehicle service',
            Customer_Approval__c        = 'Pending',
            Service_Mileage__c          = 25000
        );
        if (doInsert) insert so;
        return so;
    }

    // ─── Inventory Item ──────────────────────────────────────────
    public static Inventory_Itemm__c createInventoryItem(
        String partNumber,
        Integer stockQty,
        Boolean doInsert
    ) {
        Inventory_Itemm__c inv = new Inventory_Itemm__c(
            Part_Name__c        = 'Test Part ' + partNumber,
            Part_Category__c    = 'Brakes',
            Part_Number__c      = partNumber,
            Unit_Cost__c        = 1000,
            Selling_Price__c    = 1500,
            Stock_Quantity__c   = stockQty,
            Reorder_Level__c    = 3,
            Inventory_Status__c = 'Active'
        );
        if (doInsert) insert inv;
        return inv;
    }

    // ─── Service Item (Part) ─────────────────────────────────────
    public static Service_Itemm__c createPartItem(
        Id serviceOrderId,
        Id inventoryId,
        Integer qty,
        String status,
        Boolean doInsert
    ) {
        Service_Itemm__c si = new Service_Itemm__c(
            Service_Orderr__c  = serviceOrderId,
            Item_Type__c       = 'Part',
            Item_Name__c       = 'Brake Pad',
            Quantity__c        = qty,
            Unit_Price__c      = 1500,
            Inventory_Itemm__c = inventoryId,
            Item_Status__c     = status
        );
        if (doInsert) insert si;
        return si;
    }

    // ─── Service Item (Service) ──────────────────────────────────
    public static Service_Itemm__c createServiceItem(
        Id serviceOrderId,
        String status,
        Boolean doInsert
    ) {
        Service_Itemm__c si = new Service_Itemm__c(
            Service_Orderr__c = serviceOrderId,
            Item_Type__c      = 'Service',
            Item_Name__c      = 'Engine Oil Change',
            Quantity__c       = 1,
            Unit_Price__c     = 800,
            Item_Status__c    = status
        );
        if (doInsert) insert si;
        return si;
    }

    // ─── Invoicee ────────────────────────────────────────────────
    public static Invoicee__c createInvoice(
        Id serviceOrderId,
        Id customerId,
        Id vehicleId,
        Decimal total,
        Boolean doInsert
    ) {
        Invoicee__c inv = new Invoicee__c(
            Service_Orderr__c = serviceOrderId,
            Customerr__c      = customerId,
            Vehiclee__c       = vehicleId,
            Invoice_Date__c   = Date.today(),
            Due_Date__c       = Date.today().addDays(7),
            Invoice_Status__c = 'Issued',
            Payment_Terms__c  = '7 Days',
            Subtotal__c       = total,
            Total_Amount__c   = total,
            Amount_Paid__c    = 0
        );
        if (doInsert) insert inv;
        return inv;
    }

    // ─── Payment ─────────────────────────────────────────────────
    public static Paymentt__c createPayment(
        Id invoiceId,
        Decimal amount,
        String status,
        Boolean doInsert
    ) {
        Paymentt__c pmt = new Paymentt__c(
            Invoicee__c        = invoiceId,
            Payment_Date__c    = Date.today(),
            Payment_Amount__c  = amount,
            Payment_Method__c  = 'Cash',
            Payment_Status__c  = status
        );
        if (doInsert) insert pmt;
        return pmt;
    }
}
