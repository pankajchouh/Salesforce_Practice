import { LightningElement } from 'lwc';
import fetchAccountsByIndustry from '@salesforce/apex/AccountController.fetchAccountsByIndustry';

export default class AccountConditionalExample extends LightningElement {

    selectedIndustry;
    accounts;
    isLoading = false;
    showNoData = false;

    // 👶 Dropdown options
    industryOptions = [
        { label: 'IT', value: 'IT' },
        { label: 'Finance', value: 'Finance' },
        { label: 'Healthcare', value: 'Healthcare' }
    ];

    // Jab user industry select kare
    handleIndustryChange(event) {
        this.selectedIndustry = event.target.value;
    }

    // Button click
    handleSearch() {
        this.isLoading = true;
        this.showNoData = false;

        fetchAccountsByIndustry({ industry: this.selectedIndustry })
            .then(result => {
                this.accounts = result;
                this.isLoading = false;

                // 👶 Agar data nahi mila
                if (result.length === 0) {
                    this.showNoData = true;
                }
            })
            .catch(error => {
                this.isLoading = false;
                console.error(error);
            });
    }

    // 👶 Button tabhi enable jab industry select ho
    get isButtonDisabled() {
        return !this.selectedIndustry;
    }
}
