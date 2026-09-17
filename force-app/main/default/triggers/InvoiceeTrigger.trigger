trigger InvoiceeTrigger on Invoicee__c (before insert, before update, after insert, after update) {
    InvoiceeTriggerHandler.handle();
}
