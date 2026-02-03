import { LightningElement, track } from 'lwc';

import createRecord from '@salesforce/apex/RecordController.createRecord';

import deleteRecord from '@salesforce/apex/RecordController.deleteRecord';

export default class AddButtonDelete extends LightningElement {

    @track records = [];

    connectedCallback() {

        this.handleAdd(); // Add default row

    }

   get  isDeleteDisabled(){

    return this.records.length === 1;
    }
    handleAdd() {

        createRecord()

            .then(result => {

                this.records = [...this.records, result];

            });

    }

    handleDelete(event) {

        const id = event.target.dataset.id;

        deleteRecord({ recordId: id })

            .then(() => {

                this.records = this.records.filter(r => r.Id !== id);

            });

    }

    handleChange(event) {

        const id = event.target.dataset.id;

        const field = event.target.label.toLowerCase();

        const value = event.target.value;

        this.records = this.records.map(rec => {

            if (rec.Id === id) rec[field] = value;

            return rec;

        });

    }

}