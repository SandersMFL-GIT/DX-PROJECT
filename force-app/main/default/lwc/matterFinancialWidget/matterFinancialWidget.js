import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

// Matter fields (still needed for Retainer + Account)
import ACCOUNT_ID_FIELD         from '@salesforce/schema/Matters__c.Account__c';
import RETAINER_AMOUNT_FIELD    from '@salesforce/schema/Matters__c.Retainer_Amount__c';

// Apex: fetch the TS_Finance_Widget__c row for this Matter
import getWidgetForMatter from '@salesforce/apex/TSFinanceWidgetController.getWidgetForMatter';

const MATTER_FIELDS = [ACCOUNT_ID_FIELD, RETAINER_AMOUNT_FIELD];

export default class MatterFinancialWidget extends LightningElement {
    @api recordId; // Matter Id

    // sources
    matter;
    widget;

    // ui state
    debugAccountId;
    isLoading = false;
    hasError = false;
    errorMessage = '';

    /* ------------------ Matter (for Retainer + Account) ------------------ */
    @wire(getRecord, { recordId: '$recordId', fields: MATTER_FIELDS })
    wiredMatter({ data, error }) {
        this.isLoading = true;
        this.hasError = false;
        this.errorMessage = '';

        if (error) {
            this.hasError = true;
            this.errorMessage = 'Error loading Matter: ' + JSON.stringify(error);
            this.matter = undefined;
            // eslint-disable-next-line no-console
            console.error('wiredMatter error', error);
        } else if (data) {
            this.matter = data;
            this.debugAccountId = getFieldValue(data, ACCOUNT_ID_FIELD);
        }
        this.isLoading = false;
    }

    /* ------------------ Widget (TimeSolv totals + Trust) ------------------ */
    @wire(getWidgetForMatter, { matterId: '$recordId' })
    wiredWidget({ data, error }) {
        this.isLoading = true;

        if (error) {
            this.hasError = true;
            this.errorMessage = 'Error loading TS Finance Widget: ' + JSON.stringify(error);
            this.widget = undefined;
            // eslint-disable-next-line no-console
            console.error('wiredWidget error', error);
        } else if (data) {
            this.widget = data;
        }
        this.isLoading = false;
    }

    /* ------------------ Raw values ------------------ */
    // Widget fields
    get trustBalance() {
        return Number(this.widget?.Timesolv_Trust_Balance__c || 0);
    }

    get wip() {
        const fees = Number(this.widget?.Timesolv_Total_WIP_Fees__c || 0);
        const exp  = Number(this.widget?.Timesolv_Total_WIP_Expenses__c || 0);
        return fees + exp;
    }

    get worked() {
        const fees = Number(this.widget?.Timesolv_Total_Fees__c || 0);
        const exp  = Number(this.widget?.Timesolv_Total_Expenses__c || 0);
        return fees + exp;
    }

    get billed() {
        return this.worked - this.wip;
    }

    // Matter field
    get retainerAmount() {
        return Number(getFieldValue(this.matter, RETAINER_AMOUNT_FIELD) || 0);
    }

    /* ------------------ Balance/Credit logic ------------------ */
    get chargesToCoverNow() { return this.wip; }

    get retainerShortfall() {
        const diff = this.retainerAmount - this.trustBalance;
        return diff > 0 ? diff : 0;
    }

    // === Action bar values ===
    get payToMaintainRetainer() { return this.retainerShortfall; }

    // Total Balance Due = WIP + shortfall
    get totalBalanceDue() { 
        return this.chargesToCoverNow + this.retainerShortfall; 
    }

    // Credit when retainer fully funded and Trust exceeds charges
    get creditAvailable() {
        if (this.trustBalance >= this.retainerAmount) {
            const extra = this.trustBalance - this.chargesToCoverNow;
            return extra > 0 ? extra : 0;
        }
        return 0;
    }

    /* ------------------ Action bar bindings ------------------ */
    get hasCredit() { return this.creditAvailable > 0; }
    get payToMaintainRetainerFormatted() { return this.formatCurrency(this.payToMaintainRetainer); }
    get totalCreditAvailableFormatted() { return this.formatCurrency(this.creditAvailable); }
    get formattedTotalBalanceDue() { return this.formatCurrency(this.totalBalanceDue); }

    /* ------------------ Summary box bindings ------------------ */
    get trustVsWipLabel() {
        return this.hasCredit ? 'Total Credit Available' : 'Total Balance Due';
    }
    get formattedTrustVsWip() {
        const v = this.hasCredit ? this.creditAvailable : this.totalBalanceDue;
        return this.formatCurrency(v);
    }

    /* ------------------ Formatting ------------------ */
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
