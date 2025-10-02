/**
 * TS_ProjectSummary_Batchable
 * Writes project totals into TS_Finance_Widget__c (same record keyed by Matter_Id__c).
 * Usage: Database.executeBatch(new TS_ProjectSummary_Batchable());
 */
public with sharing class TS_ProjectSummary_Batchable
    implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {

    // Matter_ID_Full__c (normalized) → Matter Id
    private Map<String, Id> matterByKey = new Map<String, Id>();

    // buffer for widget rows
    private List<TS_Finance_Widget__c> toUpsert = new List<TS_Finance_Widget__c>();

    // chunked upsert
    private static void flushInChunks(List<TS_Finance_Widget__c> rows, Integer chunkSize) {
        if (rows == null || rows.isEmpty()) return;
        Integer i = 0, n = rows.size();
        while (i < n) {
            List<TS_Finance_Widget__c> chunk = new List<TS_Finance_Widget__c>();
            Integer c = 0;
            while (c < chunkSize && i < n) { chunk.add(rows[i]); i++; c++; }
            Database.upsert(chunk, TS_Finance_Widget__c.Fields.Matter_Id__c, false);
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        for (Matters__c m : [
            SELECT Id, Matter_ID_Full__c
            FROM Matters__c
            WHERE Matter_ID_Full__c != null
              AND Status__c != 'Closed'
        ]) {
            matterByKey.put(norm(m.Matter_ID_Full__c), m.Id);
        }
        return Database.getQueryLocator([SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]);
    }

    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        // Hardcoded request controls (no custom settings)
        final String orderBy  = 'Id';
        final Boolean sortAsc = false;
        final Integer pageSize = 200;

        Integer pageNum = 1;

        while (true) {
            if ((Limits.getCallouts() + 2) >= Limits.getLimitCallouts()) break;

            String payload = '{'
                + '"OrderBy":"' + orderBy + '",'
                + '"SortOrderAscending":' + String.valueOf(sortAsc) + ','
                + '"PageSize":' + String.valueOf(pageSize) + ','
                + '"PageNumber":' + pageNum + ','
                + '"Criteria":[{"FieldName":"LastUpdatedDate","Operator":"IS NOT NULL"}]}';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(timesolvIntegrationTokenUtil.getTimesolvBaseUrl() + '/projectSummary');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + timesolvIntegrationTokenUtil.getBearerToken());
            req.setTimeout(120000);
            req.setBody(payload);

            HttpResponse res;
            try { res = new Http().send(req); } catch (System.CalloutException e) { break; }
            if (res.getStatusCode() != 200) break;

            Map<String,Object> wrap = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> projects = (List<Object>) wrap.get('ProjectSummaries');
            if (projects == null) projects = new List<Object>();
            if (pageNum == 1 && projects.isEmpty()) break;

            for (Object o : projects) {
                Map<String,Object> ps = (Map<String,Object>) o;

                // ClientProjectId should equal Matter_ID_Full__c
                String matterIdFull = (String) ps.get('ClientProjectId');
                String key = norm(matterIdFull);
                Id mId = matterByKey.get(key);
                if (mId == null) continue;

                TS_Finance_Widget__c wid = new TS_Finance_Widget__c();
                wid.Matter_Id__c                     = key;   // External ID (Text, Unique)
                wid.Matter__c                        = mId;

                wid.Timesolv_Project_Id__c           = (String)  ps.get('ProjectId');
                wid.Timesolv_Id__c                   = String.valueOf(ps.get('Id'));
                wid.Timesolv_Total_WIP_Fees__c       = (Decimal) ps.get('TotalWIPFees');
                wid.Timesolv_Total_Fees__c           = (Decimal) ps.get('TotalFees');
                wid.Timesolv_Total_Worked_Hours__c   = (Decimal) ps.get('TotalHours');
                wid.Timesolv_Total_Billable_Hours__c = (Decimal) ps.get('TotalBillableHours');
                wid.Timesolv_Total_Expenses__c       = (Decimal) ps.get('TotalExpenses');
                wid.Timesolv_Total_WIP_Hours__c      = (Decimal) ps.get('TotalWIPHours');
                wid.Timesolv_Total_WIP_Expenses__c   = (Decimal) ps.get('TotalWIPExpenses');

                toUpsert.add(wid);

                if (toUpsert.size() >= 1000) {
                    flushInChunks(toUpsert, 500);
                    toUpsert.clear();
                }
            }

            if (projects.size() < pageSize) break;
            pageNum++;
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!toUpsert.isEmpty()) flushInChunks(toUpsert, 500);

        System.debug(LoggingLevel.INFO,
            'TS_ProjectSummary_Batchable: Job ' + bc.getJobId()
            + ' completed. Upserted TS_Finance_Widget__c rows.');
    }

    private static String norm(String s) {
        return (s == null) ? null : s.replace(' ', '').trim().toUpperCase();
    }
}