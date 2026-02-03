public without sharing class EI_SDS_CareofLandlord {

    // Common select fragments to avoid duplication
    private static final String DEPOSIT_SELECT_PRIMARY_LL_FIELDS =
        ' Id, Name, Landlord_Address__c, Property__r.Primary_Landlord__c,' +
        ' Property__r.Primary_Landlord__r.Name,' +
        ' Property__r.Primary_Landlord__r.Phone,' +
        ' Property__r.Primary_Landlord__r.Email,' +
        ' Property__r.Primary_Landlord__r.AddressFormula__c,' +
        ' Customer__r.Transfer_deposit_preference__c ';

    private static final String DEPOSIT_SELECT_FOR_WRAPPER_COMMON =
        ' Id, Name, Actual_Protected_Amount__c, Property_Address__c,' +
        ' Customer__r.C_o_City__c, Customer__r.C_o_Postal_Code__c,' +
        ' Property__r.Property_Owner__r.Name, Status__c, Property_Address_Without_Country__c, Format(LastModifiedDate),' +
        ' Property__r.Property_Owner__r.AddressFinal__c, Property__r.Property_Owner__r.Phone, Customer__c, Transfer_verified__c,' +
        ' Property__r.Property_Owner__r.Email__c, Property__r.Property_Owner__r.PersonEmail,' +
        ' Customer__r.C_o_Landlord_Country__c, Property__r.Property_Owner__c, Deposit_Transferred_to_Account__c,' +
        ' Property__r.Property_Owner__r.PersonMailingCountry ';

    private static final Set<String> VALID_STATUSES = new Set<String>{
        'Deposits held by scheme',
        'Tenant changeover cancelled',
        'Tenant changeover accepted',
        'Tenant changeover completed',
        'Repayment requested cancelled',
        'No response from agent/landlord – chasing agent/landlord response to request',
        'Repayment requested - no response from tenant',
        'Repayment disputed - self-resolution',
        'Self-resolution - awaiting review',
        'Evidence gathering – agent/landlord',
        'Evidence Gathering - tenant',
        'Awaiting evidence review'
    };

    @AuraEnabled
    public static List<Deposit__c> getDepositInformation1(List<Id> depositIds) {
        if (depositIds == null || depositIds.isEmpty()) {
            return new List<Deposit__c>();
        }
        List<Deposit__c> results = [
            SELECT
                Id, Name, Landlord_Address__c,
                Property__r.Primary_Landlord__c,
                Property__r.Primary_Landlord__r.Name,
                Property__r.Primary_Landlord__r.Phone,
                Property__r.Primary_Landlord__r.Email,
                Property__r.Primary_Landlord__r.AddressFormula__c,
                Customer__r.Transfer_deposit_preference__c
            FROM Deposit__c
            WHERE Id IN :depositIds
        ];
        return results;
    }

    @AuraEnabled
    public static List<depositListWrapper> getDepositInformation2(List<Id> depositIds) {
        List<depositListWrapper> wrappers = new List<depositListWrapper>();
        if (depositIds == null || depositIds.isEmpty()) {
            return wrappers;
        }
        for (Deposit__c d : [
            SELECT Id, Name, Landlord_Address__c, Property_Address__c,
                   Property__r.Primary_Landlord__c,
                   Property__r.Primary_Landlord__r.Name,
                   Property__r.Primary_Landlord__r.Phone,
                   Property__r.Primary_Landlord__r.Email,
                   Property__r.Primary_Landlord__r.AccountId,
                   Property__r.Primary_Landlord__r.AddressFormula__c,
                   Property__r.Primary_Landlord__r.MailingPostalCode,
                   Property__r.Primary_Landlord__r.MailingState,
                   Property__r.Primary_Landlord__r.MailingStreet,
                   Property__r.Primary_Landlord__r.MailingCity,
                   Property__r.Primary_Landlord__r.MailingCountry,
                   Customer__r.Transfer_deposit_preference__c
            FROM Deposit__c
            WHERE Id IN :depositIds
        ]) {
            wrappers.add(new depositListWrapper(false, false, false, false, d));
        }
        return wrappers;
    }

    @AuraEnabled
    public static List<depositListWrapper> getDepositInformation(String branchId) {
        List<depositListWrapper> wrappers = new List<depositListWrapper>();
        // Narrow time window, as designed
        Datetime fiveSecondsAgo = Datetime.now().addSeconds(-5);

        // Build query dynamically only for the additional branch filter
        String baseQuery =
            ' SELECT ' + DEPOSIT_SELECT_FOR_WRAPPER_COMMON +
            ' FROM Deposit__c ' +
            ' WHERE Deposit_Transferred_to_Account__c = null' +
            ' AND LastModifiedDate >= :fiveSecondsAgo' +
            ' AND Transfer_verified__c = false' +
            ' AND Deposit_Transferred__c = false' +
            ' AND Status__c IN :VALID_STATUSES';

        try {
            if (String.isBlank(branchId)) {
                for (Deposit__c d : Database.query(baseQuery)) {
                    wrappers.add(new depositListWrapper(false, false, false, false, d));
                }
            } else {
                String q = baseQuery + ' AND branch__c = :branchId';
                for (Deposit__c d : Database.query(q)) {
                    wrappers.add(new depositListWrapper(false, false, false, false, d));
                }
            }
        } catch (Exception e) {
            // Intentionally return what we have so far
        }
        return wrappers;
    }

    @AuraEnabled
    public static List<depositListWrapper> getdeposits(String accountId) {
        List<depositListWrapper> wrappers = new List<depositListWrapper>();
        if (String.isBlank(accountId)) {
            return wrappers;
        }
        try {
            Id devRecordTypeId = Schema.SObjectType.Deposit__c.getRecordTypeInfosByName().get('SDS Deposit').getRecordTypeId();
            for (Deposit__c d : [
                SELECT Id, Name, Actual_Protected_Amount__c, Property_Address__c,
                       Customer__r.C_o_City__c, Customer__r.C_o_Postal_Code__c,
                       Landlord_Address__c,
                       Property__r.Primary_Landlord__c,
                       Property__r.Primary_Landlord__r.Name,
                       Property__r.Primary_Landlord__r.Phone,
                       Property__r.Primary_Landlord__r.MailingPostalCode,
                       Property__r.Primary_Landlord__r.MailingState,
                       Property__r.Primary_Landlord__r.MailingStreet,
                       Property__r.Primary_Landlord__r.MailingCity,
                       Property__r.Primary_Landlord__r.MailingCountry,
                       Property__r.Primary_Landlord__r.Email,
                       Property__r.Primary_Landlord__r.AddressFormula__c
                FROM Deposit__c
                WHERE Customer__c = :accountId
                AND RecordTypeId = :devRecordTypeId
            ]) {
                wrappers.add(new depositListWrapper(false, false, false, false, d));
            }
        } catch (Exception e) {
            // return empty/default list
        }
        return wrappers;
    }

    @AuraEnabled
    public static String manualUpdateLandlord(List<Contact> selectedContacts, List<String> depositIds) {
        // Return empty string or 'error' as per existing behavior
        String result = '';
        if (selectedContacts == null || selectedContacts.isEmpty() || depositIds == null || depositIds.isEmpty()) {
            return result;
        }

        // Remove duplicates by Contact.Id
        Map<Id, Contact> uniqueContacts = new Map<Id, Contact>();
        for (Contact c : selectedContacts) {
            if (c != null && c.Id != null && !uniqueContacts.containsKey(c.Id)) {
                uniqueContacts.put(c.Id, c);
            }
        }
        if (uniqueContacts.isEmpty()) {
            return result;
        }

        User currentUser = [
            SELECT Id, Account.OwnerId, Contact.AccountId, AccountId, Profile.Name, ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Id accountRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Individual_Landlord').getRecordTypeId();

        // Fetch properties involved for these deposits and where those contacts are the primary landlord
        List<Property__c> properties = [
            SELECT Id,
                   Primary_Landlord__c,
                   Primary_Landlord__r.FirstName,
                   Primary_Landlord__r.LastName,
                   (SELECT Id, Relation_to_Property__c, Contact__c, Property__c
                    FROM Property_Allocations__r
                    WHERE Relation_to_Property__c = 'Primary Landlord')
            FROM Property__c
            WHERE Primary_Landlord__c IN :uniqueContacts.keySet()
              AND Id IN (SELECT Property__c FROM Deposit__c WHERE Id IN :depositIds)
        ];

        // Build reverse map: ContactId -> PropertyIds
        Map<Id, List<Id>> contactToPropertyIds = new Map<Id, List<Id>>();
        Map<Id, String> contactIdToFirst = new Map<Id, String>();
        Map<Id, String> contactIdToLast = new Map<Id, String>();
        List<Property_Allocation__c> propAllocsToUpdate = new List<Property_Allocation__c>();

        for (Property__c p : properties) {
            if (p.Primary_Landlord__c == null) continue;

            contactToPropertyIds.putIfAbsent(p.Primary_Landlord__c, new List<Id>());
            contactToPropertyIds.get(p.Primary_Landlord__c).add(p.Id);

            contactIdToFirst.put(p.Primary_Landlord__c, p.Primary_Landlord__r != null ? p.Primary_Landlord__r.FirstName : null);
            contactIdToLast.put(p.Primary_Landlord__c, p.Primary_Landlord__r != null ? p.Primary_Landlord__r.LastName : null);

            if (p.Property_Allocations__r != null) {
                propAllocsToUpdate.addAll(p.Property_Allocations__r);
            }
        }

        // Build Account upserts mapped by PropertyId
        Map<Id, Account> propertyIdToUpdatedAccount = new Map<Id, Account>();
        Map<Id, Account> accountsToUpdateById = new Map<Id, Account>();

        for (Contact con : uniqueContacts.values()) {
            if (con == null) continue;

            Account accUpdate = new Account();
            accUpdate.Id = con.AccountId;
            accUpdate.RecordTypeId = accountRtId;
            accUpdate.PersonEmail = con.Email;
            accUpdate.Phone = con.Phone;
            accUpdate.PersonMailingStreet = con.MailingStreet;
            accUpdate.PersonMailingCity = con.MailingCity;
            accUpdate.PersonMailingState = con.MailingState;
            accUpdate.PersonMailingPostalCode = con.MailingPostalCode;
            accUpdate.PersonMailingCountry = con.MailingCountry;
            accUpdate.FirstName = contactIdToFirst.get(con.Id);
            accUpdate.LastName = contactIdToLast.get(con.Id);
            accUpdate.BillingStreet = con.MailingStreet;
            accUpdate.BillingCity = con.MailingCity;
            accUpdate.BillingState = con.MailingState;
            accUpdate.BillingPostalCode = con.MailingPostalCode;
            accUpdate.BillingCountry = con.MailingCountry;
            accUpdate.Email__c = con.Email;
            accUpdate.OwnerId = (currentUser != null && currentUser.Account != null) ? currentUser.Account.OwnerId : null;
            accUpdate.EI_Non_Member_Landlord__pc = true;
            accUpdate.Account_Status__pc = 'Active';

            if (con.Id != null && contactToPropertyIds.containsKey(con.Id)) {
                for (Id propId : contactToPropertyIds.get(con.Id)) {
                    propertyIdToUpdatedAccount.put(propId, accUpdate);
                }
            }
            if (accUpdate.Id != null) {
                accountsToUpdateById.put(accUpdate.Id, accUpdate);
            }
        }

        if (accountsToUpdateById.isEmpty() || propertyIdToUpdatedAccount.isEmpty()) {
            return result;
        }

        try {
            update accountsToUpdateById.values();

            // Refresh Accounts to get PersonContactId
            List<Account> refreshed = [
                SELECT Id, PersonContactId, Parent_person_account__c
                FROM Account
                WHERE Id IN :accountsToUpdateById.keySet()
            ];
            Map<Id, Account> refreshedById = new Map<Id, Account>(refreshed);

            // Prepare Property and Allocation updates
            List<Property__c> propsToUpdate = new List<Property__c>();
            for (Id propId : propertyIdToUpdatedAccount.keySet()) {
                Account stub = propertyIdToUpdatedAccount.get(propId);
                Account full = refreshedById.get(stub.Id);
                if (full == null) continue;

                Property__c pUpd = new Property__c(Id = propId, Primary_Landlord__c = full.PersonContactId);
                propsToUpdate.add(pUpd);
            }
            // NOTE: original code had updates commented out. Respect that by leaving them commented; uncomment to activate.
            // if (!propsToUpdate.isEmpty()) update propsToUpdate;

            for (Property_Allocation__c pa : propAllocsToUpdate) {
                if (pa.Relation_to_Property__c == 'Primary Landlord') {
                    Account acc = propertyIdToUpdatedAccount.get(pa.Property__c);
                    if (acc != null) {
                        Account full = refreshedById.get(acc.Id);
                        if (full != null) {
                            pa.Contact__c = full.PersonContactId;
                        }
                    }
                }
            }
            // if (!propAllocsToUpdate.isEmpty()) update propAllocsToUpdate;

        } catch (Exception e) {
            result = 'error';
        }
        return result;
    }

    @AuraEnabled
    public static String overridecareoflandlord(List<Id> depositIds) {
        String result = '';
        if (depositIds == null || depositIds.isEmpty()) {
            return result;
        }

        List<Deposit__c> deposits = [
            SELECT Id, Name, Actual_Protected_Amount__c, Landlord_Address__c,
                   Property__r.Primary_Landlord__r.AccountId,
                   Property__r.Primary_Landlord__r.FirstName,
                   Property__r.Primary_Landlord__r.LastName,
                   Property__r.Primary_Landlord__r.Phone,
                   Property__r.Primary_Landlord__r.Email,
                   Property__r.Primary_Landlord__r.AddressFormula__c,
                   Property__r.Primary_Landlord__c,
                   Property_Address__c,
                   Customer__r.C_o_Phone_Code__c,
                   Customer__r.C_o_Landlord_Telephone__c,
                   Customer__r.C_o_Landlord_Email_Address__c,
                   Property__r.Property_Owner__r.Base_Country__c,
                   Customer__r.C_o_Postal_Code__c,
                   Property__r.Property_Owner__r.Name,
                   Status__c,
                   Property_Address_Without_Country__c,
                   Customer__r.C_o_Landlord_Address__c,
                   Property__c,
                   Customer__r.C_o_City__c,
                   Customer__r.C_o_Landlord_Country__c,
                   Property__r.Property_Owner__r.AddressFinal__c,
                   Property__r.Property_Owner__r.Phone,
                   Customer__r.OwnerId,
                   Customer__c,
                   Property__r.Country__c,
                   Property__r.Base_Country__c,
                   Customer__r.C_o_Postcode__c,
                   Property__r.Property_Owner__r.Email__c,
                   Property__r.Property_Owner__r.PersonEmail,
                   Property__r.Property_Owner__r.PersonMailingCountry,
                   Property__r.Property_Owner__c,
                   Deposit_Transferred_to_Account__c
            FROM Deposit__c
            WHERE Id IN :depositIds
        ];

        // Map of propertyId -> Account(update) and AccountId -> Account(update)
        Map<Id, Account> propertyToAccountUpdate = new Map<Id, Account>();
        Map<Id, Account> accountsUpdateById = new Map<Id, Account>();

        for (Deposit__c d : deposits) {
            String email = d.Customer__r != null ? d.Customer__r.C_o_Landlord_Email_Address__c : null;
            String phone = d.Customer__r != null ? d.Customer__r.C_o_Landlord_Telephone__c : null;

            if (String.isBlank(email) && String.isBlank(phone)) {
                result = 'Error';
                continue;
            }
            Account a = new Account();
            a.Id = (d.Property__r != null && d.Property__r.Primary_Landlord__r != null) ? d.Property__r.Primary_Landlord__r.AccountId : null;

            if (a.Id == null) {
                // Skip if we don't have the Account Id to update
                result = String.isBlank(result) ? 'Error' : result;
                continue;
            }
            a.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Individual_Landlord').getRecordTypeId();

            a.PersonEmail = email;
            a.Phone = phone;

            // Map C/O address to Person and Billing
            a.PersonMailingStreet = d.Customer__r.C_o_Landlord_Address__c;
            a.PersonMailingCity = d.Customer__r.C_o_City__c;
            a.PersonMailingState = d.Customer__r.C_o_Postal_Code__c;
            a.PersonMailingPostalCode = d.Customer__r.C_o_Postcode__c;
            a.PersonMailingCountry = d.Customer__r.C_o_Landlord_Country__c;

            a.FirstName = (d.Property__r != null && d.Property__r.Primary_Landlord__r != null) ? d.Property__r.Primary_Landlord__r.FirstName : null;
            a.LastName = (d.Property__r != null && d.Property__r.Primary_Landlord__r != null) ? d.Property__r.Primary_Landlord__r.LastName : null;

            a.BillingStreet = d.Customer__r.C_o_Landlord_Address__c;
            a.BillingCity = d.Customer__r.C_o_City__c;
            a.BillingState = d.Customer__r.C_o_Postal_Code__c;
            a.BillingPostalCode = d.Customer__r.C_o_Postcode__c;
            a.BillingCountry = d.Customer__r.C_o_Landlord_Country__c;

            a.Email__c = email;

            propertyToAccountUpdate.put(d.Property__c, a);
            accountsUpdateById.put(a.Id, a);
        }

        if (accountsUpdateById.isEmpty() || propertyToAccountUpdate.isEmpty()) {
            return result;
        }

        Boolean hadError = false;
        try {
            update accountsUpdateById.values();

            // Refresh Accounts for PersonContactId
            List<Account> refreshed = [
                SELECT Id, PersonContactId, Parent_person_account__c
                FROM Account
                WHERE Id IN :accountsUpdateById.keySet()
            ];
            Map<Id, Account> refreshedById = new Map<Id, Account>(refreshed);

            // Update properties
            List<Property__c> propsToUpdate = new List<Property__c>();
            for (Id propId : propertyToAccountUpdate.keySet()) {
                Account a = propertyToAccountUpdate.get(propId);
                Account full = refreshedById.get(a.Id);
                if (full == null) continue;
                propsToUpdate.add(new Property__c(Id = propId, Primary_Landlord__c = full.PersonContactId));
            }
            if (!propsToUpdate.isEmpty()) {
                update propsToUpdate;
            }

            // Update allocations
            List<Property_Allocation__c> allocs = [
                SELECT Id, Relation_to_Property__c, Contact__c, Property__c
                FROM Property_Allocation__c
                WHERE Property__c IN :propertyToAccountUpdate.keySet()
            ];
            for (Property_Allocation__c pa : allocs) {
                if (pa.Relation_to_Property__c == 'Primary Landlord') {
                    Account a = propertyToAccountUpdate.get(pa.Property__c);
                    Account full = (a != null) ? refreshedById.get(a.Id) : null;
                    if (full != null) {
                        pa.Contact__c = full.PersonContactId;
                    }
                }
            }
            if (!allocs.isEmpty()) {
                update allocs;
            }
            result = 'careoftransfer';
        } catch (Exception e) {
            hadError = true;
        }
        return result;
    }

    @AuraEnabled
    public static void updateAccount(String preferenceValue) {
        if (preferenceValue == null) return;

        Id accountId = [SELECT Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId()].Contact.AccountId;
        if (accountId == null) return;

        Account acc = new Account(Id = accountId, Transfer_deposit_preference__c = preferenceValue);
        update acc;
    }

    @AuraEnabled
    public static AsyncApexJob GetConcurrentBulkBatchJob(String jobId) {
        if (String.isBlank(jobId)) {
            return [
                SELECT Id, JobType, ApexClass.Name, Status, JobItemsProcessed, TotalJobItems
                FROM AsyncApexJob
                WHERE JobType = 'BatchApex'
                  AND ApexClass.Name = 'EI_SDS_BulkTransferAcceptDepositCls'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }
        return [
            SELECT Id, JobType, ApexClass.Name, Status, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
    }

    /* Wrapper class for checkbox with deposit */
    public class depositListWrapper {
        @AuraEnabled public Boolean isChecked { get; set; }
        @AuraEnabled public Boolean ischeckaccept { get; set; }
        @AuraEnabled public Boolean ischeckcareoflld { get; set; }
        @AuraEnabled public Boolean ischeckmanuallychange { get; set; }
        @AuraEnabled public Deposit__c objDeposit { get; set; }
        public depositListWrapper(Boolean isChecked, Boolean ischeckaccept, Boolean ischeckcareoflld, Boolean ischeckmanuallychange, Deposit__c objDeposit) {
            this.isChecked = isChecked;
            this.ischeckaccept = ischeckaccept;
            this.ischeckcareoflld = ischeckcareoflld;
            this.ischeckmanuallychange = ischeckmanuallychange;
            this.objDeposit = objDeposit;
        }
    }
}
