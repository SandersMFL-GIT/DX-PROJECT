/**
 * TS_TrustBalanceSync_Batch
 *
 * Synchronizes trust balance information from TimeSolv into the TS_Finance_Widget__c object.
 *
 * NOTE: This class makes one API call per record, which can be slow for large data volumes.
 *
 * Usage:
 * Database.executeBatch(new TS_TrustBalanceSync_Batch(), 100);
 */
public with sharing class TS_TrustBalanceSync_Batch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    // --- Stateful counters for final summary ---
    private Integer totalSuccess = 0;
    private Integer totalErrors = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Matter_ID_Full__c, Timesolv_Trust_Account_Id__c
            FROM Matters__c
            WHERE Timesolv_Trust_Account_Id__c != null
              AND Matter_ID_Full__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Matters__c> matters) {
        List<TS_Finance_Widget__c> widgetsToUpsert = new List<TS_Finance_Widget__c>();
        String baseUrl = timesolvIntegrationTokenUtil.getTimesolvBaseUrl();
        String bearer  = timesolvIntegrationTokenUtil.getBearerToken();

        for (Matters__c m : matters) {
            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                System.debug(LoggingLevel.WARN, 'Callout limit reached. Breaking loop to process remaining records in the next batch.');
                break;
            }

            try {
                HttpRequest req = new HttpRequest();
                String q = EncodingUtil.urlEncode(String.valueOf(m.Timesolv_Trust_Account_Id__c), 'UTF-8');
                req.setEndpoint(baseUrl + '/trustAccountBalance?TrustAccountId=' + q);
                req.setMethod('GET');
                req.setHeader('Authorization', 'Bearer ' + bearer);
                req.setTimeout(120000);

                HttpResponse res = new Http().send(req);

                if (res.getStatusCode() == 200 && res.getBody() != null) {
                    Map<String, Object> payload   = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    Map<String, Object> trustData = (Map<String, Object>) payload.get('TrustAccountBalance');
                    
                    if (trustData != null) {
                        TS_Finance_Widget__c wid = new TS_Finance_Widget__c();
                        wid.Matter_Id__c = normKey(m.Matter_ID_Full__c);
                        wid.Matter__c    = m.Id;
                        wid.Timesolv_Trust_Balance__c = (Decimal) trustData.get('Balance');
                        wid.Timesolv_Trust_Replenish_Below__c = (Decimal) trustData.get('ReplenishBelow');
                        wid.Timesolv_Trust_Replenish_To__c = (Decimal) trustData.get('ReplenishTo');
                        
                        widgetsToUpsert.add(wid);
                    }
                } else {
                    System.debug(LoggingLevel.ERROR, 'API call failed for Matter ID ' + m.Id +
                                 '. Status: ' + res.getStatusCode() + '. Body: ' + res.getBody());
                    totalErrors++;
                }

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'An unexpected error occurred for Matter ID ' + m.Id +
                             '. Error: ' + e.getTypeName() + ' - ' + e.getMessage());
                totalErrors++;
            }
        }

        if (!widgetsToUpsert.isEmpty()) {
            totalSuccess += widgetsToUpsert.size(); // Increment success count before DML
            Database.UpsertResult[] upsertResults = Database.upsert(widgetsToUpsert, TS_Finance_Widget__c.Fields.Matter_Id__c, false);
            
            for (Integer i = 0; i < upsertResults.size(); i++) {
                if (!upsertResults[i].isSuccess()) {
                    Database.Error err = upsertResults[i].getErrors()[0];
                    System.debug(LoggingLevel.ERROR, 'DML Error on Matter_Id__c ' + widgetsToUpsert[i].Matter_Id__c + 
                                 ': ' + err.getMessage() + ' (' + err.getStatusCode() + ')');
                    totalSuccess--; 
                    totalErrors++;  
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('--- TS_TrustBalanceSync_Batch FINISHED ---');
        System.debug('Total records successfully processed: ' + totalSuccess);
        System.debug('Total records with errors: ' + totalErrors);
        System.debug('------------------------------------------');
    }
    
    private static String normKey(String s) {
        return String.isBlank(s) ? null : s.replace(' ', '').trim().toUpperCase();
    }
}