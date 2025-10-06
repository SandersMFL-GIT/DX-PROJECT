public with sharing class TS_ProjectSummary_Scheduler implements Schedulable {

   
    public void execute(SchedulableContext sc) {
        TS_ProjectSummary_Queueable.startJob();
    }
}