@IsTest
private class TS_TrustBalanceSync_Batch_Test {

    private class TrustBalanceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            Map<String, Object> body = new Map<String, Object>{
                'TrustAccountBalance' => new Map<String, Object>{
                    'Balance'        => 123.45,
                    'ReplenishBelow' => 100,
                    'ReplenishTo'    => 500
                }
            };
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(body));
            return res;
        }
    }

    @IsTest
    static void test_Execute_Upserts_Unique_Widget_Row() {
        Account client = new Account(
            RecordTypeId = '0124N000000X9ZgQAK',
            LastName     = 'Test Client',
            PersonEmail  = 'client@example.com'
        );
        insert client;

        Contact c = [SELECT Id, Email FROM Contact WHERE AccountId = :client.Id LIMIT 1];
        if (String.isBlank(c.Email)) { c.Email = 'client@example.com'; update c; }

        Account opposing = new Account(Name = 'Opposing Party (Test)');
        insert opposing;

        MFL_Office__c office = new MFL_Office__c();
        insert office;

        Matters__c matter = new Matters__c(
            Name              = 'Trust Batch Test Matter',
            Status__c         = 'Open',
            Account__c        = client.Id,
            MFL_Office__c     = office.Id,
            Opposing_Party_a__c = opposing.Id,
            Case_Type__c      = 'Divorce w/out Children'
        );
        insert matter;

        String uniqueKey = ('TB-' + matter.Id).replace(' ', '').trim().toUpperCase();
        String stubJson  =
            '{"attributes":{"type":"Matters__c"},'
          + '"Id":"' + matter.Id + '",'
          + '"Matter_ID_Full__c":"' + uniqueKey + '",'
          + '"Timesolv_Trust_Account_Id__c":"TA-001"}';
        Matters__c scopeStub = (Matters__c) JSON.deserialize(stubJson, Matters__c.class);

        System.assertEquals(0, [SELECT COUNT() FROM TS_Finance_Widget__c WHERE Matter__c = :matter.Id]);

        Test.setMock(HttpCalloutMock.class, new TrustBalanceMock());

        Test.startTest();
        new TS_TrustBalanceSync_Batch()
            .execute(null, new List<Matters__c>{ scopeStub });
        Test.stopTest();

        TS_Finance_Widget__c wid = [
            SELECT Matter__c, Matter_Id__c,
                   Timesolv_Trust_Balance__c,
                   Timesolv_Trust_Replenish_Below__c,
                   Timesolv_Trust_Replenish_To__c
            FROM TS_Finance_Widget__c
            WHERE Matter__c = :matter.Id
            LIMIT 1
        ];

        System.assertEquals(matter.Id, wid.Matter__c, 'Widget should reference the correct Matter');
        System.assertEquals(uniqueKey,  wid.Matter_Id__c, 'Widget should use the unique normalized key');

        System.assertEquals(123.45, wid.Timesolv_Trust_Balance__c);
        System.assertEquals(100,    wid.Timesolv_Trust_Replenish_Below__c);
        System.assertEquals(500,    wid.Timesolv_Trust_Replenish_To__c);
    }
}