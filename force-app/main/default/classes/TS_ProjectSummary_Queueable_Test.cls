@IsTest
private class TS_ProjectSummary_Queueable_Test {

    private class ProjectSummaryMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> row = new Map<String, Object>();
            row.put('ClientProjectId',    '12345-001');
            row.put('ProjectId',          'P001');
            row.put('Id',                 111);
            row.put('TotalWIPFees',       111.11);
            row.put('TotalFees',          222.22);
            row.put('TotalHours',         33.33);
            row.put('TotalBillableHours', 22.22);
            row.put('TotalExpenses',      44.44);
            row.put('TotalWIPHours',      55.55);
            row.put('TotalWIPExpenses',   66.66);

            Map<String, Object> wrapper = new Map<String, Object>{
                'ProjectSummaries' => new List<Object>{ row }
            };

            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(wrapper));
            return res;
        }
    }

    @IsTest
    static void test_Queueable_Upserts_Widget_From_ProjectSummary() {
        // --- 1. Setup Test Data ---
        Account client = new Account(
            RecordTypeId = SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccount').getRecordTypeId(),
            LastName     = 'Yanez',
            PersonEmail  = 'client@example.com'
        );
        insert client;

        Account opposing = new Account(Name = 'Charles Brewster');
        insert opposing;

        MFL_Office__c office = new MFL_Office__c(Name = 'Main Office');
        insert office;

        // Create the Matter record.
        Matters__c matter = new Matters__c(
            Name              = 'IRM Yanez, Hilary',    
            Status__c         = 'Open',
            Account__c        = client.Id,              
            MFL_Office__c     = office.Id,              
            Opposing_Party_a__c = opposing.Id,            
            Case_Type__c      = 'Divorce w/out Children'  
        );
        insert matter;

        System.assertEquals(0, [SELECT COUNT() FROM TS_Finance_Widget__c]);

        Test.setMock(HttpCalloutMock.class, new ProjectSummaryMock());

        // --- 2. Manually Prepare the Data Map ---
        String normKey = '12345-001';
        Map<String, Id> matterMap = new Map<String, Id>{
            normKey => matter.Id
        };

        // --- 3. Execute the Job ---
        Test.startTest();
        // Call the special @TestVisible method with our prepared map.
        TS_ProjectSummary_Queueable.startJob(matterMap);
        Test.stopTest();

        // --- 4. Verify Widget was Upserted with Correct Data ---
        TS_Finance_Widget__c wid = [
            SELECT Matter__c, Matter_Id__c, Timesolv_Project_Id__c, Timesolv_Id__c,
                   Timesolv_Total_WIP_Fees__c, Timesolv_Total_Fees__c,
                   Timesolv_Total_Worked_Hours__c, Timesolv_Total_Billable_Hours__c,
                   Timesolv_Total_Expenses__c, Timesolv_Total_WIP_Hours__c, Timesolv_Total_WIP_Expenses__c
            FROM TS_Finance_Widget__c
            WHERE Matter__c = :matter.Id
            LIMIT 1
        ];

        System.assertEquals(matter.Id, wid.Matter__c, 'Widget should link to the Matter');
        System.assertEquals(normKey,   wid.Matter_Id__c, 'Normalized key should be used');
        System.assertEquals('P001',    wid.Timesolv_Project_Id__c);
        System.assertEquals('111',     wid.Timesolv_Id__c);
        System.assertEquals(111.11,    wid.Timesolv_Total_WIP_Fees__c);
        System.assertEquals(222.22,    wid.Timesolv_Total_Fees__c);
        System.assertEquals(33.33,     wid.Timesolv_Total_Worked_Hours__c);
        System.assertEquals(22.22,     wid.Timesolv_Total_Billable_Hours__c);
        System.assertEquals(44.44,     wid.Timesolv_Total_Expenses__c);
        System.assertEquals(55.55,     wid.Timesolv_Total_WIP_Hours__c);
        System.assertEquals(66.66,     wid.Timesolv_Total_WIP_Expenses__c);
    }
}