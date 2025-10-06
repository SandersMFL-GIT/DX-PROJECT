/**
 * TS_ProjectSummary_Queueable
 *
 * This Queueable class syncs project summary data from TimeSolv into the TS_Finance_Widget__c object.
 * It uses a chained-job architecture, where each job processes one page of API results,
 * making it robust against governor limits.
 *
 * USAGE:
 * To start the sync process, execute the following from an Anonymous Apex window:
 * TS_ProjectSummary_Queueable.startJob();
 */
public with sharing class TS_ProjectSummary_Queueable implements Queueable, Database.AllowsCallouts {

    // --- State passed between chained jobs ---
    private final Map<String, Id> matterByKey;
    private final Integer pageNum;
    private final Integer totalProcessedSoFar; 

    // --- Hardcoded request controls ---
    private static final String  ORDER_BY   = '';
    private static final Boolean SORT_ASC   = false;
    private static final Integer PAGE_SIZE  = 200;

    /**
     * Constructor to carry state from one job to the next.
     */
    public TS_ProjectSummary_Queueable(Map<String, Id> matterMap, Integer pageNumber, Integer totalProcessed) {
        this.matterByKey = matterMap;
        this.pageNum = pageNumber;
        this.totalProcessedSoFar = totalProcessed;
    }

    /**
     * Main entry point to kick off the entire job chain.
     */
     public static void startJob() {
        Map<String, Id> initialMatterMap = new Map<String, Id>();
        for (Matters__c m : [
            SELECT Id, Matter_ID_Full__c
            FROM Matters__c
            WHERE Matter_ID_Full__c != null AND Status__c != 'Closed'
        ]) {
            initialMatterMap.put(norm(m.Matter_ID_Full__c), m.Id);
        }
        startJob(initialMatterMap); 
    }

    // This new @TestVisible method allows our test to bypass the SOQL query above
    
    @TestVisible
    private static void startJob(Map<String, Id> mattersToProcess) {
        if (!mattersToProcess.isEmpty()) {
            System.enqueueJob(new TS_ProjectSummary_Queueable(mattersToProcess, 1, 0));
        }
    }
    /**
     * Core logic. Executes for one page of API results.
     */
    public void execute(QueueableContext context) {
        String payload = '{'
            + '"OrderBy":"' + ORDER_BY + '",'
            + '"SortOrderAscending":' + String.valueOf(SORT_ASC) + ','
            + '"PageSize":' + String.valueOf(PAGE_SIZE) + ','
            + '"PageNumber":' + this.pageNum + ','
            + '"Criteria":[{"FieldName":"LastUpdatedDate","Operator":"IS NOT NULL"}]}';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(timesolvIntegrationTokenUtil.getTimesolvBaseUrl() + '/projectSummary');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + timesolvIntegrationTokenUtil.getBearerToken());
        req.setTimeout(120000);
        req.setBody(payload);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (System.CalloutException e) {
            System.debug(LoggingLevel.ERROR, 'Callout failed for page ' + this.pageNum + ': ' + e.getMessage());
            return;
        }

        if (res.getStatusCode() != 200) {
            System.debug('❌ Call-out failed page ' + this.pageNum + ': ' + res.getStatusCode() + ' – ' + res.getBody());
            return;
        }

        Map<String,Object> wrap = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> projects = (List<Object>) wrap.get('ProjectSummaries');
        System.debug('[EXECUTE] Page ' + this.pageNum + ' returned ' + projects.size() + ' summaries');
        
        if (projects == null || projects.isEmpty()) {
            System.debug('[FINISH] No more summaries returned. Sync complete.');
            System.debug('[FINISH] Total Matters Processed across all jobs: ' + this.totalProcessedSoFar);
            return;
        }

        Map<String, TS_Finance_Widget__c> widgetsToUpsertMap = new Map<String, TS_Finance_Widget__c>();
        for (Object o : projects) {
            Map<String,Object> ps = (Map<String,Object>) o;
            String matterIdFull = (String) ps.get('ClientProjectId');
            String key = norm(matterIdFull);
            Id mId = this.matterByKey.get(key);

            if (mId == null) {
                System.debug('[SKIPPED] No Salesforce match for API Project ID: "' + matterIdFull + '"');
                continue;
            }

            TS_Finance_Widget__c wid = new TS_Finance_Widget__c();
            wid.Matter_Id__c                   = key;
            wid.Matter__c                      = mId;
            wid.Timesolv_Project_Id__c         = (String)  ps.get('ProjectId');
            wid.Timesolv_Id__c                 = String.valueOf(ps.get('Id'));
            wid.Timesolv_Total_WIP_Fees__c     = (Decimal) ps.get('TotalWIPFees');
            wid.Timesolv_Total_Fees__c           = (Decimal) ps.get('TotalFees');
            wid.Timesolv_Total_Worked_Hours__c   = (Decimal) ps.get('TotalHours');
            wid.Timesolv_Total_Billable_Hours__c = (Decimal) ps.get('TotalBillableHours');
            wid.Timesolv_Total_Expenses__c       = (Decimal) ps.get('TotalExpenses');
            wid.Timesolv_Total_WIP_Hours__c      = (Decimal) ps.get('TotalWIPHours');
            wid.Timesolv_Total_WIP_Expenses__c   = (Decimal) ps.get('TotalWIPExpenses');
            
            widgetsToUpsertMap.put(key, wid);
        }

        List<TS_Finance_Widget__c> widgetsToUpsert = widgetsToUpsertMap.values();
        Integer processedInThisJob = widgetsToUpsert.size();
        Integer newTotal = this.totalProcessedSoFar + processedInThisJob;
        System.debug('[EXECUTE] Processed ' + processedInThisJob + ' records in this job. Running total: ' + newTotal);

        if (!widgetsToUpsert.isEmpty()) {
            Database.UpsertResult[] upsertResults = Database.upsert(widgetsToUpsert, TS_Finance_Widget__c.Fields.Matter_Id__c, false);
            logDmlErrors(upsertResults, widgetsToUpsert);
        }

        if (projects.size() >= PAGE_SIZE) {
            System.enqueueJob(new TS_ProjectSummary_Queueable(this.matterByKey, this.pageNum + 1, newTotal));
        } else {
            System.debug('[FINISH] Final page processed. Sync complete.');
            System.debug('[FINISH] Total Matters Processed across all jobs: ' + newTotal);
        }
    }
    
    private static String norm(String s) {
        return (s == null) ? null : s.replace(' ', '').trim().toUpperCase();
    }
    
    private static void logDmlErrors(Database.UpsertResult[] urList, List<TS_Finance_Widget__c> originalRecords) {
        for (Integer i = 0; i < urList.size(); i++) {
            if (!urList[i].isSuccess()) {
                Database.Error err = urList[i].getErrors()[0];
                TS_Finance_Widget__c failedRecord = originalRecords[i];
                System.debug(LoggingLevel.ERROR, 'DML Error on TS_Finance_Widget__c with Matter_Id__c: ' + failedRecord.Matter_Id__c);
                System.debug(LoggingLevel.ERROR, '  >> Error: ' + err.getMessage() + ' (' + err.getStatusCode() + ')');
            }
        }
    }
}