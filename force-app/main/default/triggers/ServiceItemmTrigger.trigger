trigger ServiceItemmTrigger on Service_Itemm__c (before insert, before update, after insert, after update) {
    ServiceItemmTriggerHandler.handle();
}