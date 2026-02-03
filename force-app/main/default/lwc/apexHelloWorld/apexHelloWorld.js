import { LightningElement, track, wire } from 'lwc';
import getHelloWorldMessage from '@salesforce/apex/HelloWorldLWCController.getHelloWorldMessage';
import getServerInfo from '@salesforce/apex/HelloWorldLWCController.getServerInfo';

export default class ApexHelloWorld extends LightningElement {
    @track greetingMessage = 'Loading...';
    @track serverTime = '';
    @track userName = '';
    @track orgName = '';
    @track inputName = '';
    @track isLoading = true;
    @track error = null;
    
    // Wire method से data fetch करें
    @wire(getHelloWorldMessage)
    wiredHelloMessage({ error, data }) {
        this.isLoading = false;
        
        if (data) {
            this.greetingMessage = data.message;
            this.serverTime = data.timestamp;
            this.userName = data.user;
            this.orgName = data.orgName;
            this.error = null;
        } else if (error) {
            this.error = error.body.message;
            console.error('Error fetching data:', error);
        }
    }
    
    // Server info fetch करें
    connectedCallback() {
        this.fetchServerInfo();
    }
    
    fetchServerInfo() {
        getServerInfo()
            .then(result => {
                console.log('Server Info:', result);
            })
            .catch(error => {
                console.error('Error fetching server info:', error);
            });
    }
    
    handleNameChange(event) {
        this.inputName = event.target.value;
    }
    
    callApexMethod() {
        this.isLoading = true;
        this.error = null;
        
        // यहाँ आप custom Apex method call कर सकते हैं
        setTimeout(() => {
            if (this.inputName) {
                this.greetingMessage = `Hello ${this.inputName}! Welcome to Salesforce.`;
            } else {
                this.greetingMessage = 'Hello Guest! Please enter your name.';
            }
            this.isLoading = false;
        }, 500);
    }
}