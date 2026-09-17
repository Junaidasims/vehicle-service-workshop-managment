# Vehicle Service Workshop Management System

A professional **Salesforce Developer portfolio project** built on Salesforce DX that demonstrates a complete automobile service/workshop management system.

## Business Scenario

This application represents a real-world car service centre workflow:

```
Customer → Vehicle → Service Order → Service Items → Inventory
                                  ↓
                               Invoice → Payments
```

A customer brings in their vehicle. A service order is raised, work items and spare parts are tracked, inventory is automatically deducted when parts are used, an invoice is auto-generated when the job is complete, and payments are collected and tracked.

---

## Custom Objects

| Object | API Name | Description |
|---|---|---|
| Customerr | `Customerr__c` | Vehicle owners registered at the workshop |
| Vehiclee | `Vehiclee__c` | Vehicles belonging to customers |
| Service Orderr | `Service_Orderr__c` | A job card / work order for a vehicle visit |
| Service Itemm | `Service_Itemm__c` | Individual line items (labour or parts) on a service order |
| Inventory Itemm | `Inventory_Itemm__c` | Spare parts stockroom catalogue |
| Invoicee | `Invoicee__c` | Bill generated when a service order is completed |
| Paymentt | `Paymentt__c` | Payments collected against an invoice |

---

## Salesforce Features Demonstrated

### Configuration
- Custom Objects with Auto Number record names
- Custom Fields (Text, Number, Currency, Date, Picklist, Formula, Lookup, Master-Detail)
- **Roll-Up Summary Fields** — Service Order totals roll up from Service Items; Invoice payment totals roll up from Payments
- **Formula Fields** — Subtotal, Discount Amount, Tax Amount, Total Amount, Balance Due
- **Validation Rules** — 30+ rules across all objects enforcing business logic
- **Record-Triggered Flows** — Customer auto-sync on Service Order, Last Service Date update on Vehicle

### Apex Development
- **Trigger → Handler pattern** on Service Itemm, Service Orderr, Invoicee, Paymentt
- **Bulkification** — all triggers handle 200-record batches, no SOQL or DML inside loops
- **Governor limit awareness** — Set/Map/List collections, aggregate SOQL
- **SOQL** — Basic, relationship (child-to-parent, parent-to-child), aggregate (COUNT, SUM, GROUP BY)
- **DML** — insert, update with collection-based operations
- **Exception handling** — meaningful `addError()` messages surfaced to users
- **Recursion guard** — prevents re-entrant trigger execution
- **FOR UPDATE** — pessimistic locking on inventory records during stock deduction

### Apex Test Classes
- 3 test classes, 25 test methods
- `@TestSetup`, `Test.startTest()`, `Test.stopTest()`
- Positive, negative, bulk, and edge case coverage
- `TestDataFactory` utility class for reusable test data

---

## Key Business Logic

### Inventory Stock Management (Service Itemm Trigger)
When a Part-type Service Item is marked **Completed**:
- Stock is automatically deducted from the linked Inventory Itemm
- Changing the quantity on a completed item adjusts the delta correctly
- Changing the inventory item on a completed item restores old stock and deducts from the new item
- Moving status from Completed → In Progress restores the stock
- Insufficient stock is blocked before save
- Inactive inventory items are blocked

### Service Order Completion (Service Orderr Trigger)
- `Actual_Completion_Date__c` auto-populated when status → Completed
- Duplicate active orders for the same vehicle are blocked
- An **Invoice is automatically generated** when the order completes

### Invoice & Payment Processing (Paymentt Trigger)
- Overpayment is blocked — cannot pay more than the invoice total
- Cancelled invoices cannot receive payments
- `Invoice_Status__c` auto-transitions: Issued → Partially Paid → Paid
- Only **Completed** payments count toward the total — Failed/Refunded/Pending are ignored
- Roll-up summary on Invoice uses a filter for `Payment_Status__c = Completed`

### Flows
- **Service Orderr Customer Sync** — when a Vehicle is selected on a Service Order, the Customer is auto-populated from the Vehicle record
- **Vehiclee Last Service Date Update** — when a Service Order is completed, the Vehicle's `Last_Service_Date__c` is updated only if the new date is more recent

---

## Project Structure

```
force-app/main/default/
├── classes/              # Apex classes and test classes
├── objects/              # Custom object definitions, fields, validation rules
├── triggers/             # Apex triggers
├── flows/                # Record-triggered flows
└── permissionsets/       # Workshop User permission set
```

---

## Apex Test Results

```
Tests Run:    25
Passed:       25
Failed:       0
Pass Rate:    100%
```

---

## Setup

1. Authenticate to your Salesforce org:
   ```bash
   sf org login web --alias my-org
   ```

2. Deploy the project:
   ```bash
   sf project deploy start --source-dir force-app --wait 15
   ```

3. Run tests:
   ```bash
   sf apex run test --class-names ServiceItemmTriggerHandlerTest,ServiceOrderrTriggerHandlerTest,PaymenttTriggerHandlerTest --result-format human --wait 15
   ```

---

## Tech Stack
- Salesforce Platform (API v67.0)
- Apex
- SOQL
- Record-Triggered Flows
- Salesforce CLI (SF CLI)
- Salesforce DX project structure
