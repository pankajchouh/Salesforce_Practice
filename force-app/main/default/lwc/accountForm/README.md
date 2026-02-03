# accountForm LWC

A Lightning Web Component to create or edit Account records using lightning-record-edit-form with fields: Name, Phone, Website.

## Features
- Create mode when no recordId is provided
- Edit mode when recordId is provided
- Success and Error toast handling
- Emits custom events: `formsuccess` and `formerror`
- Exposed to App Builder (Record/App/Home/Tab), Utility Bar, Flow Screen, and Record Action

## Usage

### In App Builder (Record Page)
1. Open a Lightning Record Page for Account.
2. Drag the Account Form component onto the layout.
3. For edit mode, set `recordId` via page context or a formula.
4. Save and activate.

### In a Parent LWC
```html
<c-account-form record-id={recordId} onformsuccess={handleFormSuccess} onformerror={handleFormError}></c-account-form>
```

```js
handleFormSuccess(event) {
  const { recordId, mode } = event.detail;
  // e.g., navigate, refresh, or show custom toast
}

handleFormError(event) {
  const { message } = event.detail;
  // custom error handling
}
```

### In Flow Screen
- Add the component in a Flow Screen element.
- Provide `recordId` input if editing an existing Account.

## Component API

Inputs:
- recordId (String, optional): When provided, the form is in edit mode. Leave empty for create mode.

Events:
- formsuccess: `{ recordId: string, mode: 'create' | 'edit' }`
- formerror: `{ message: string }`

## Files
- accountForm.html
- accountForm.js
- accountForm.js-meta.xml

## Notes
- Relies on standard base components and LDS; no Apex is required.
- Ensure users have FLS/CRUD permissions for Account and fields Name, Phone, Website.
