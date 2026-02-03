import { LightningElement ,track} from 'lwc';

export default class Test_MyAccount extends LightningElement {
    @track message = 'Welcome to Salesforce LWC!';
    
    handleClick() {
        this.message = 'Button Clicked! Hello from Salesforce!';
        
        // Show a toast notification
        this.showToast('Success', 'Button was clicked successfully!', 'success');
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
}