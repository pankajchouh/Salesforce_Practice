import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AccountRecordForm extends LightningElement {
    // Public API to accept recordId from parent or App Builder
    @api recordId;

    // Local UI state
    @track mode = 'view'; // 'view' | 'edit'

    // Computed flags
    get isViewMode() {
        return this.mode === 'view';
    }
    get isEditMode() {
        return this.mode === 'edit';
    }
    get hasRecordId() {
        return !!this.recordId;
    }

    // Button variants to reflect active state
    get viewButtonVariant() {
        return this.isViewMode ? 'brand' : 'neutral';
    }
    get editButtonVariant() {
        return this.isEditMode ? 'brand' : 'neutral';
    }

    // Handlers to toggle modes
    handleView() {
        this.mode = 'view';
    }
    handleEdit() {
        if (!this.hasRecordId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No recordId',
                    message: 'Please provide a recordId to edit an Account.',
                    variant: 'error'
                })
            );
            return;
        }
        this.mode = 'edit';
    }

    // Edit form events
    handleSuccess(event) {
        // Record saved successfully; switch back to view
        this.mode = 'view';
        const recordId = event?.detail?.id || this.recordId;
        if (recordId && !this.recordId) {
            this.recordId = recordId;
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Account was saved successfully.',
                variant: 'success'
            })
        );
    }

    handleError(event) {
        const message =
            event?.detail?.message ||
            'An unexpected error occurred while saving the Account.';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
    }

    handleCancel() {
        // Revert to view mode without saving
        this.mode = 'view';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Canceled',
                message: 'Edit canceled.',
                variant: 'info'
            })
        );
    }
}
