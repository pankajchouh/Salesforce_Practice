import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AccountForm extends LightningElement {
    @api recordId; // when provided => edit mode
    @track showToastPlaceholder = false;

    get hasRecordId() {
        return !!this.recordId;
    }

    handleSuccess(event) {
        const recId = event?.detail?.id || this.recordId;
        this.dispatchEvent(
            new ShowToastEvent({
                title: this.hasRecordId ? 'Account updated' : 'Account created',
                message: recId ? `Record Id: ${recId}` : 'Operation successful',
                variant: 'success'
            })
        );

        // Bubble up change so parent can react (optional)
        this.dispatchEvent(
            new CustomEvent('formsuccess', {
                detail: { recordId: recId, mode: this.hasRecordId ? 'edit' : 'create' },
                bubbles: true,
                composed: true
            })
        );

        // Reset form in create mode for quick entry
        if (!this.hasRecordId) {
            const form = this.template.querySelector('lightning-record-edit-form');
            if (form) {
                // lightning-record-edit-form has reset() via native form semantics
                const resetBtn = this.template.querySelector('lightning-button[type="reset"]');
                if (resetBtn) {
                    resetBtn.click();
                }
            }
        }
    }

    handleError(event) {
        const message =
            event?.detail?.message ||
            (event?.detail?.output && event.detail.output.errors?.[0]?.message) ||
            'An error occurred';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );

        this.dispatchEvent(
            new CustomEvent('formerror', {
                detail: { message },
                bubbles: true,
                composed: true
            })
        );

        // If running in local preview without app container for toasts
        // keep a placeholder so users know where toast would render
        this.showToastPlaceholder = true;
    }
}
