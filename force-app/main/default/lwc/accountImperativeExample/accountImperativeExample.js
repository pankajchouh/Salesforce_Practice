import { LightningElement } from 'lwc';
import fetchAccounts from '@salesforce/apex/AccountController.fetchAccounts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AccountImperativeExample extends LightningElement {

    accounts;
    limitValue = 5;
    isLoading = false;

    handleLimitChange(event) {
        this.limitValue = event.target.value;
    }

    handleClick() {

        // 🔴 STEP 1: VALIDATION (MOST IMPORTANT)
        if (this.limitValue < 1 || this.limitValue > 5) {
            this.accounts = null; // data clear

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Invalid Input',
                    message: 'Please enter a number between 1 and 5 only',
                    variant: 'error'
                })
            );
            return; // ❌ Apex call stop
        }

        // 🔴 STEP 2: LOADING START
        this.isLoading = true;

        // 🔴 STEP 3: APEX CALL
        fetchAccounts({ limitSize: this.limitValue })
            .then(result => {
                this.accounts = result;
                this.isLoading = false;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: `${result.length} Accounts loaded successfully`,
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.isLoading = false;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'Something went wrong',
                        variant: 'error'
                    })
                );
            });
    }
}
