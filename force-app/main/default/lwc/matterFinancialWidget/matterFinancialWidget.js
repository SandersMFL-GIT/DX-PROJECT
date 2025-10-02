import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

// Matter fields
import ACCOUNT_ID_FIELD                from '@salesforce/schema/Matters__c.Account__c';
import TIMESOLV_WIP_FEES_FIELD         from '@salesforce/schema/Matters__c.Timesolv_Total_WIP_Fees__c';
import TIMESOLV_WIP_EXP_FIELD          from '@salesforce/schema/Matters__c.Timesolv_Total_WIP_Expenses__c';
import TIMESOLV_FEES_FIELD             from '@salesforce/schema/Matters__c.Timesolv_Total_Fees__c';
import TIMESOLV_EXP_FIELD              from '@salesforce/schema/Matters__c.Timesolv_Total_Expenses__c';
import TIMESOLV_TRUST_BAL_FIELD        from '@salesforce/schema/Matters__c.Timesolv_Trust_Balance__c';
import RETAINER_AMOUNT_FIELD           from '@salesforce/schema/Matters__c.Retainer_Amount__c';

const MATTER_FIELDS = [
    ACCOUNT_ID_FIELD,
    TIMESOLV_WIP_FEES_FIELD,
    TIMESOLV_WIP_EXP_FIELD,
    TIMESOLV_FEES_FIELD,
    TIMESOLV_EXP_FIELD,
    TIMESOLV_TRUST_BAL_FIELD,
    RETAINER_AMOUNT_FIELD
];

export default class MatterFinancialWidget extends LightningElement {
    @api recordId;

    matter;
    debugAccountId;
    isLoading = false;
    hasError = false;
    errorMessage = '';

    @wire(getRecord, { recordId: '$recordId', fields: MATTER_FIELDS })
    wiredMatter({ data, error }) {
        this.isLoading = true;
        this.hasError = false;
        this.errorMessage = '';

        if (error) {
            this.hasError = true;
            this.errorMessage = 'Error loading Matter: ' + JSON.stringify(error);
            this.matter = undefined;
            console.error('wiredMatter error', error);
        } else if (data) {
            this.matter = data;
            this.debugAccountId = getFieldValue(data, ACCOUNT_ID_FIELD);
        }
        this.isLoading = false;
    }

    // ---- Raw values ----
    get trustBalance()   { return Number(getFieldValue(this.matter, TIMESOLV_TRUST_BAL_FIELD) || 0); }
    get retainerAmount() { return Number(getFieldValue(this.matter, RETAINER_AMOUNT_FIELD) || 0); }
    get wip() {
        const fees = Number(getFieldValue(this.matter, TIMESOLV_WIP_FEES_FIELD) || 0);
        const exp  = Number(getFieldValue(this.matter, TIMESOLV_WIP_EXP_FIELD)  || 0);
        return fees + exp;
    }
    get worked() {
        const fees = Number(getFieldValue(this.matter, TIMESOLV_FEES_FIELD) || 0);
        const exp  = Number(getFieldValue(this.matter, TIMESOLV_EXP_FIELD)  || 0);
        return fees + exp;
    }
    get billed() { return this.worked - this.wip; }

    // ---- Balance/Credit logic ----
    get chargesToCoverNow() { return this.wip; }

    // If Trust < Retainer, the shortfall is due
    get retainerShortfall() {
        const diff = this.retainerAmount - this.trustBalance;
        return diff > 0 ? diff : 0;
    }

    // === Action bar values ===
    get payToMaintainRetainer() {
        // Just the shortfall (retainer amount – trust balance)
        return this.retainerShortfall;
    }

    // Total Balance Due = WIP + shortfall (original formula)
    get totalBalanceDue() { 
        return this.chargesToCoverNow + this.retainerShortfall; 
    }

    // Credit Available only when retainer fully funded and Trust exceeds charges
    get creditAvailable() {
        if (this.trustBalance >= this.retainerAmount) {
            const extra = this.trustBalance - this.chargesToCoverNow;
            return extra > 0 ? extra : 0;
        }
        return 0;
    }

    // ---- Action bar bindings ----
    get hasCredit() { 
        return this.creditAvailable > 0; 
    }
    get payToMaintainRetainerFormatted() { 
        return this.formatCurrency(this.payToMaintainRetainer); 
    }
    get totalCreditAvailableFormatted() { 
        return this.formatCurrency(this.creditAvailable); 
    }
    get formattedTotalBalanceDue() {
        return this.formatCurrency(this.totalBalanceDue);
    }

    // ---- Summary box bindings (existing) ----
    get trustVsWipLabel() {
        return this.creditAvailable > 0 ? 'Total Credit Available' : 'Total Balance Due';
    }
    get formattedTrustVsWip() {
        const v = this.creditAvailable > 0 ? this.creditAvailable : this.totalBalanceDue;
        return this.formatCurrency(v);
    }

    // ---- Formatting ----
    formatCurrency(v) {
        return `$${Number(v || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    }
    get formattedRetainerAmount()  { return this.formatCurrency(this.retainerAmount); }
    get formattedTrustBalance()    { return this.formatCurrency(this.trustBalance); }
    get formattedWip()             { return this.formatCurrency(this.wip); }
    get formattedWorked()          { return this.formatCurrency(this.worked); }
    get formattedBilled()          { return this.formatCurrency(this.billed); }

    // Debug (optional)
    get debugAccountIdValue() { return this.debugAccountId; }
}