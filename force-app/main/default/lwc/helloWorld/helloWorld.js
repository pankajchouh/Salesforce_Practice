import { LightningElement, track } from 'lwc';

export default class HelloWorld extends LightningElement {
    @track message = 'Welcome to Salesforce LWC! Pankaj ';
    
    handleClick() {
        this.message = 'Button Clicked! Hello from Salesforce! Pankaj';
        
        // Show a toast notification
        this.showToast('Success', 'Button was clicked successfully! Pankaj', 'success');
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