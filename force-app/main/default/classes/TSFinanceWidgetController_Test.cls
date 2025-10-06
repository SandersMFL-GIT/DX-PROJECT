@IsTest
private class TSFinanceWidgetController_Test {
    @TestSetup
    static void setupData() {
        // Create a fake Matter record to relate the widget to.
        // Replace 'Matter__c' fields with real required fields in your org if different.
        // Using minimal fields to keep test data generic and non-sensitive.
        SObject matter = (SObject)Schema.getGlobalDescribe().get('Matter__c').newSObject();
        // If Matter__c has required fields, set them here safely.
        // Example placeholders (uncomment and adjust if needed):
        // matter.put('Name', 'Test Matter');
        insert matter;

        // Create two widgets to validate ORDER BY LastModifiedDate DESC LIMIT 1 behavior
        TS_Finance_Widget__c widget1 = new TS_Finance_Widget__c(
            Matter__c = (Id)matter.get('Id'),
            Timesolv_Id__c = 'TS-001',
            Timesolv_Project_Id__c = 'PRJ-001',
            Timesolv_Total_WIP_Fees__c = 100,
            Timesolv_Total_WIP_Expenses__c = 10,
            Timesolv_Total_Fees__c = 500,
            Timesolv_Total_Expenses__c = 50,
            Timesolv_Total_WIP_Hours__c = 5,
            Timesolv_Total_Worked_Hours__c = 50,
            Timesolv_Total_Billable_Hours__c = 45,
            Timesolv_Trust_Balance__c = 1000,
            Timesolv_Trust_Replenish_Below__c = 250,
            Timesolv_Trust_Replenish_To__c = 750
        );
        insert widget1;

        // Second widget with different values to ensure it is the most recent
        // We'll update it after insert to ensure LastModifiedDate is greater
        TS_Finance_Widget__c widget2 = new TS_Finance_Widget__c(
            Matter__c = (Id)matter.get('Id'),
            Timesolv_Id__c = 'TS-002',
            Timesolv_Project_Id__c = 'PRJ-002',
            Timesolv_Total_WIP_Fees__c = 200,
            Timesolv_Total_WIP_Expenses__c = 20,
            Timesolv_Total_Fees__c = 800,
            Timesolv_Total_Expenses__c = 80,
            Timesolv_Total_WIP_Hours__c = 8,
            Timesolv_Total_Worked_Hours__c = 80,
            Timesolv_Total_Billable_Hours__c = 72,
            Timesolv_Trust_Balance__c = 2000,
            Timesolv_Trust_Replenish_Below__c = 300,
            Timesolv_Trust_Replenish_To__c = 1000
        );
        insert widget2;

        // Touch widget2 to bump LastModifiedDate (DML will do)
        widget2.Timesolv_Total_WIP_Fees__c = 201;
        update widget2;
    }

    @IsTest
    static void test_getWidgetForMatter_returnsLatestRecord() {
        // Arrange
        TS_Finance_Widget__c anyWidget = [SELECT Matter__c FROM TS_Finance_Widget__c LIMIT 1];
        Id matterId = anyWidget.Matter__c;

        Test.startTest();
        TS_Finance_Widget__c result = TSFinanceWidgetController.getWidgetForMatter(matterId);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected a widget to be returned');

        // The latest is the one we updated in @TestSetup (Timesolv_Id__c = TS-002 with WIP Fees 201)
        System.assertEquals('TS-002', result.Timesolv_Id__c, 'Should return latest widget for matter');
        System.assertEquals(201, result.Timesolv_Total_WIP_Fees__c, 'Should reflect updated value on latest widget');

        // Spot-check a few selected fields included in the SOQL
        System.assertEquals('PRJ-002', result.Timesolv_Project_Id__c);
        System.assertEquals(2000, result.Timesolv_Trust_Balance__c);
        System.assertEquals(72, result.Timesolv_Total_Billable_Hours__c);
    }

    @IsTest
    static void test_getWidgetForMatter_noMatchThrowsQueryException() {
        // Call with an Id that doesn't match any TS_Finance_Widget__c.Matter__c.
        // Using a fake Id with same prefix length as a custom object (15/18 length still fine).
        // The method uses a non-optional query (no try/catch), so it should throw a QueryException.
        Id nonExistingMatterId = 'a00' + String.valueOf(Crypto.getRandomInteger()).leftPad(12, '0');

        Test.startTest();
        Boolean threw = false;
        try {
            TSFinanceWidgetController.getWidgetForMatter(nonExistingMatterId);
        } catch (QueryException qe) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected a QueryException when no widget exists for the given matter');
    }

    @IsTest
    static void test_getWidgetForMatter_withNullId_behavesAsPlatform() {
        // Passing null should also result in a QueryException due to the SOQL bind.
        Test.startTest();
        Boolean threw = false;
        try {
            TSFinanceWidgetController.getWidgetForMatter(null);
        } catch (Exception e) {
            // Platform throws QueryException; catching as Exception keeps test robust to minor changes.
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected an exception when passing null Id');
    }
}
