trigger PaymenttTrigger on Paymentt__c (before insert, before update, after insert, after update) {
    PaymenttTriggerHandler.handle();
}
