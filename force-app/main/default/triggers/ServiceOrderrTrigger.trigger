trigger ServiceOrderrTrigger on Service_Orderr__c (before insert, before update, after insert, after update) {
    ServiceOrderrTriggerHandler.handle();
}
