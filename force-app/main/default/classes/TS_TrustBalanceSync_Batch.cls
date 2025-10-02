// Run with: Database.executeBatch(new TS_TrustBalanceSync_Batch(), 100);
public with sharing class TS_TrustBalanceSync_Batch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,
                   Matter_ID_Full__c,
                   Timesolv_Trust_Account_Id__c
            FROM Matters__c
            WHERE Timesolv_Trust_Account_Id__c != null
              AND Matter_ID_Full__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Matters__c> matters) {
        List<TS_Finance_Widget__c> rows = new List<TS_Finance_Widget__c>();

        String baseUrl = timesolvIntegrationTokenUtil.getTimesolvBaseUrl();
        String bearer  = timesolvIntegrationTokenUtil.getBearerToken();

        for (Matters__c m : matters) {
            if ((Limits.getCallouts() + 1) > Limits.getLimitCallouts()) break;

            try {
                HttpRequest req = new HttpRequest();
                String q = EncodingUtil.urlEncode(String.valueOf(m.Timesolv_Trust_Account_Id__c), 'UTF-8');
                req.setEndpoint(baseUrl + '/trustAccountBalance?TrustAccountId=' + q);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + bearer);
                req.setTimeout(120000);

                HttpResponse res;
                try { res = new Http().send(req); } catch (System.CalloutException ce) { continue; }

                String key = normKey(m.Matter_ID_Full__c);
TS_Finance_Widget__c wid = new TS_Finance_Widget__c();
wid.Matter_Id__c = key;        // <-- External ID
wid.Matter__c    = m.Id;                // lookup

                if (res.getStatusCode() == 200 && res.getBody() != null) {
                    Map<String, Object> payload   = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    Map<String, Object> trustData = (Map<String, Object>) payload.get('TrustAccountBalance');
                    if (trustData != null) {
                        if (trustData.containsKey('Balance'))
                            wid.Timesolv_Trust_Balance__c = (Decimal) trustData.get('Balance');
                        if (trustData.containsKey('ReplenishBelow'))
                            wid.Timesolv_Trust_Replenish_Below__c = (Decimal) trustData.get('ReplenishBelow');
                        if (trustData.containsKey('ReplenishTo'))
                            wid.Timesolv_Trust_Replenish_To__c = (Decimal) trustData.get('ReplenishTo');
                    }
                }

                rows.add(wid);

            } catch (Exception ignore) { /* intentionally quiet */ }
        }

        if (!rows.isEmpty()) {
            try {
                Database.upsert(rows, TS_Finance_Widget__c.Fields.Matter_Id__c, false);
            } catch (Exception ignore) { /* intentionally quiet */ }
        }
    }

    public void finish(Database.BatchableContext bc) { /* no-op */ }
    
private static String normKey(String s) {
    return String.isBlank(s) ? null : s.replace(' ', '').trim().toUpperCase();
}

}