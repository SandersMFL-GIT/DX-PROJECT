@IsTest
private class TS_TrustBalanceSync_Scheduler_Test {

    @IsTest
    static void test_scheduler_executes_batch_job() {
        // --- 1. Setup ---
        // (No data setup is needed since we're only testing that the
        // batch job is started, not the full execution of the batch itself.)

        Test.startTest();

        // --- 2. Schedule the Job ---
        // We schedule the job to run in the future. The exact time doesn't
        // matter because Test.stopTest() will force it to run immediately.
        String jobName = 'Test Trust Balance Sync';
        String cronExp = '0 0 1 * * ?'; // Run at 1 AM every day
        
        System.schedule(jobName, cronExp, new TS_TrustBalanceSync_Scheduler());

        Test.stopTest();

        // --- 3. Verify ---
        // After Test.stopTest(), the scheduled job has run. We now verify
        // that it did its job, which was to start the batch process.
        List<AsyncApexJob> batchJobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
              AND ApexClass.Name = 'TS_TrustBalanceSync_Batch'
        ];

        // Assert that exactly one batch job was started by the scheduler.
        System.assertEquals(1, batchJobs.size(), 'The scheduler should have started exactly one batch job.');
    }
}