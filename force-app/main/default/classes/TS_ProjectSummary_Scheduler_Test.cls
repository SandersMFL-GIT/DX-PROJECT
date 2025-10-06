@IsTest
private class TS_ProjectSummary_Scheduler_Test {

    // --- 1. ADD a Mock Callout Class ---
    // This inner class will be used to provide a fake API response during the test.
    private class ProjectSummaryMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // We don't need real data, just a successful response
            // to prevent the callout error and allow the job to run.
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody('{ "ProjectSummaries": [] }'); // Empty list is fine
            return res;
        }
    }
    
   

    @IsTest
    static void test_scheduler_enqueues_queueable_job() {
        
         Account opposing = new Account(Name = 'Charles Brewster');
        insert opposing;

        MFL_Office__c office = new MFL_Office__c(Name = 'Main Office');
        insert office;
        // --- 2. SETUP Test Data ---
        Matters__c matter = new Matters__c(
            Name = 'Test Matter',
            Status__c = 'Open',
            MFL_Office__c     = office.Id,              
            Opposing_Party_a__c = opposing.Id,            
            Case_Type__c      = 'Divorce w/out Children'
        );
        insert matter;

        // --- 3. SET the Mock Before the Job Runs ---
        Test.setMock(HttpCalloutMock.class, new ProjectSummaryMock());

        Test.startTest();

        // --- 4. Schedule the Job ---
        String jobName = 'Test Project Summary Sync';
        String cronExp = '0 0 2 * * ?';
        
        System.schedule(jobName, cronExp, new TS_ProjectSummary_Scheduler());

        Test.stopTest();

        // --- 5. Verify ---
        List<AsyncApexJob> queueableJobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
              AND ApexClass.Name = 'TS_ProjectSummary_Queueable'
        ];

        System.assertEquals(1, queueableJobs.size(), 'The scheduler should have started exactly one Queueable job.');
    }
}