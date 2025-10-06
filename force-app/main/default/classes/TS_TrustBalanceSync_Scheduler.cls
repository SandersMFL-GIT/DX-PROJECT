public with sharing class TS_TrustBalanceSync_Scheduler implements Schedulable {

    
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new TS_TrustBalanceSync_Batch(), 100);
    }
}