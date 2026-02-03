/**
 * @Apex Class Name     : EI_EWC_createLandlord
 * @Created Date        : 02-07-2023
 * @Description         : Creating Landlord, used in ei_EWC_addNewLandlord LWC component
 * @Author              : Kamal Kant
 * @Last Modified Date  : 12-03-2025
 * @Last Modified By    : Agentforce Refactor
 * @Ver                 : 1.1 (Refactor)
 * @Modifications       : Refactored for readability, null-safety, and consistency
**/
public without sharing class EI_EWC_createLandlord {

    // Data Transfer Object for initial load (kept internal)
    public class CreateLandlordDTO {
        @AuraEnabled public List<Error_Message__mdt> errorMessageList;
        @AuraEnabled public List<England_Postcodes__mdt> ewcPostcodeList;
        @AuraEnabled public List<String> countryPhoneCodeList;
        @AuraEnabled public Map<String, String> salutationMap;

        public CreateLandlordDTO(
            List<Error_Message__mdt> errorMessageList,
            List<England_Postcodes__mdt> ewcPostcodeList,
            List<String> countryPhoneCodeList,
            Map<String, String> salutationMap
        ) {
            this.errorMessageList = errorMessageList;
            this.ewcPostcodeList = ewcPostcodeList;
            this.countryPhoneCodeList = countryPhoneCodeList;
            this.salutationMap = salutationMap;
        }
    }

    // Preserve original method name and return shape to avoid LWC breakage:
    // Returning a single DTO wrapped in a List (original code returned 0/1 element list)
    @AuraEnabled(cacheable=true)
    public static List<CreateLandlordDTO> createLandlordWrapper() {
        try {
            List<Error_Message__mdt> errorMessageList = [
                SELECT Id, Label, QualifiedApiName, DeveloperName, Error_Message__c, MasterLabel
                FROM Error_Message__mdt
            ];

            List<England_Postcodes__mdt> ewcPostcodeList = [
                SELECT Id, Label, QualifiedApiName, DeveloperName, MasterLabel
                FROM England_Postcodes__mdt
            ];

            List<String> countryPhoneCodeList = getActivePicklistValues(Contact.Phone_Code__c);
            Map<String, String> salutationMap = getPicklistValueLabelMap(Contact.Salutation);

            CreateLandlordDTO dto = new CreateLandlordDTO(errorMessageList, ewcPostcodeList, countryPhoneCodeList, salutationMap);
            return new List<CreateLandlordDTO>{ dto };
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load initial data: ' + e.getMessage());
        }
    }

    // to check for email duplicate and is currently not in use (kept behavior, hardened)
    @AuraEnabled
    public static String checkDuplicateEmail (String email,String firstname, String surname){
        String safeEmail = safeTrim(email);
        String first = safeTrim(firstname);
        String last = safeTrim(surname);

        if (String.isBlank(safeEmail) || (String.isBlank(first) && String.isBlank(last))) {
            return 'No Duplicate';
        }
        String fullNameForSearch = (first + ' ' + last).trim();

        try {
            List<List<SObject>> searchNameList = [FIND :fullNameForSearch IN ALL FIELDS 
                RETURNING Contact(Id, Name WHERE Email = :safeEmail
                    AND CreatedById = :UserInfo.getUserId() 
                    AND (Account.RecordType.Name = 'EWC Landlord')
                )
            ];
            if (!searchNameList.isEmpty() && !searchNameList[0].isEmpty()){
                return 'Duplicate Email';
            }
        } catch (Exception e) {
            // ignore and fall-through
        }
        return 'No Duplicate';
    }
    
    @AuraEnabled
    public static Map<String, Contact> savelandlord(String receivedParams) {
        Map<String, Contact> returnVal = new Map<String, Contact>();
        try {
            Map<String, Object> paramMap = (Map<String, Object>) JSON.deserializeUntyped(receivedParams);

            String branchId    = safeValue(paramMap, 'branchId');
            Boolean isOrguser  = safeBoolean(paramMap, 'isCompanySelect');
            String companyName = safeValue(paramMap, 'companyName');
            String salutation  = safeValue(paramMap, 'title');
            String firstname   = safeValue(paramMap, 'firstName');
            String lastname    = safeValue(paramMap, 'lastName');
            String email       = safeEmail(paramMap, 'email');
            String phoneCode   = safeValue(paramMap, 'phoneCode');
            String phone       = safeValue(paramMap, 'phone');

            String street   = safeValue(paramMap, 'landlordAddressStreet');
            String city     = safeValue(paramMap, 'landlordAddressCity');
            String postcode = safeValue(paramMap, 'landlordAddressPostcode');
            String county   = safeValue(paramMap, 'landlordAddressCounty');
            String country  = safeValue(paramMap, 'landlordAddressCountry');

            String corresStreet  = safeValue(paramMap, 'landlordCorrStreet');
            String corresCity    = safeValue(paramMap, 'landlordCorrCity');
            String corresPost    = safeValue(paramMap, 'landlordCorrPostcode');
            // accept both corrected and legacy misspelled key
            String corresCounty  = safeValue(paramMap, 'landlordCorrCounty');
            if (String.isBlank(corresCounty)) {
                corresCounty = safeValue(paramMap, 'andlordCorrCounty');
            }
            String corresCountry = safeValue(paramMap, 'landlordCorrCountry');
            String landlordRef   = safeValue(paramMap, 'landlordRef');

            // Normalize names
            NamePair namePair = normalizeNames(firstname, lastname, companyName);
            firstname = namePair.firstName;
            lastname  = namePair.lastName;

            // Base country
            String baseCountryVal = String.isBlank(postcode) ? '' : getEnglandWalesCountrys(postcode);

            // Trigger bypass flags preserved
            EI_EWC_AccountTriggerHandler.hasToBeValidated = false;
            EI_EWC_ContactTriggerHandler.hasToBeValidated = false;

            User u = [
                SELECT Id, AccountId, Account.OwnerId
                FROM User
                WHERE Id = :UserInfo.getUserId()
            ];

            Id contactRecordTypeId = Schema.SObjectType.Contact
                .getRecordTypeInfosByDeveloperName()
                .get('EWC_Non_Member_Landlord')
                .getRecordTypeId();

            // Duplicate check when email present
            if (!String.isBlank(email)) {
                List<Contact> duplicateContact = [
                    SELECT Id, AccountId, Salutation, FirstName, LastName, Name, Email, Phone, Landlord_reference__c
                    FROM Contact
                    WHERE Email = :email
                    AND FirstName = :firstname
                    AND LastName = :lastname
                    AND AccountId = :u.AccountId
                    LIMIT 1
                ];
                if(!duplicateContact.isEmpty()){
                    returnVal.put('duplicateLandlord', duplicateContact[0]);
                    return returnVal;
                }
            }

            Contact con = new Contact(
                AccountId = u.AccountId,
                RecordTypeId = contactRecordTypeId,
                IsAutomationBypassed__c = true,
                Salutation = salutation,
                FirstName = firstname,
                LastName = lastname,
                Account_Status__c = 'Active',
                Email = email,
                Phone_Code__c = phoneCode,
                Phone = phone,
                MailingStreet = street,
                MailingCity = city,
                MailingPostalCode = postcode,
                MailingCountry = country,
                MailingState = county,
                Correspondence_Street__c = corresStreet,
                Correspondence_City__c = corresCity,
                Correspondence_Postal_Code__c = corresPost,
                Correspondence_State__c = corresCounty,
                Correspondence_Country__c = corresCountry,
                Landlord_reference__c = landlordRef,
                Base_Country__c = baseCountryVal
            );
            if (!String.isBlank(branchId)) {
                con.Branch__c = branchId;
            }
            con.Is_Organization__c = isOrguser;

            insert con;

            String propertyRecId = safeValue(paramMap, 'propertyRecId');
            if (!String.isBlank(propertyRecId)) {
                Property_Allocation__c pall = new Property_Allocation__c(Contact__c = con.Id, Property__c = propertyRecId);
                insert pall;
            }

            returnVal.put('landlordCreated', con);
            return returnVal;
        } catch (Exception e){ 
            System.debug('savelandlord error: ' + e.getMessage());
            return null;
        }
    }

    //for EN-50 deposit summary
    @AuraEnabled
    public static Map<String, Contact> savelandlordDepositSummary(String receivedParams, String depositId) {
        Map<String, Contact> returnVal = new Map<String, Contact>();
        try {
            Map<String, Object> paramMap = (Map<String, Object>) JSON.deserializeUntyped(receivedParams);

            String branchId    = safeValue(paramMap, 'branchId'); // unused but accepted
            Boolean isOrguser  = safeBoolean(paramMap, 'isCompanySelect');
            String companyName = safeValue(paramMap, 'companyName');
            String salutation  = safeValue(paramMap, 'title');
            String firstname   = safeValue(paramMap, 'firstName');
            String lastname    = safeValue(paramMap, 'lastName');
            String email       = safeEmail(paramMap, 'email');
            String phoneCode   = safeValue(paramMap, 'phoneCode');
            String phone       = safeValue(paramMap, 'phone');

            String street   = safeValue(paramMap, 'landlordAddressStreet');
            String city     = safeValue(paramMap, 'landlordAddressCity');
            String postcode = safeValue(paramMap, 'landlordAddressPostcode');
            String county   = safeValue(paramMap, 'landlordAddressCounty');
            String country  = safeValue(paramMap, 'landlordAddressCountry');

            String corresStreet  = safeValue(paramMap, 'landlordCorrStreet');
            String corresCity    = safeValue(paramMap, 'landlordCorrCity');
            String corresPost    = safeValue(paramMap, 'landlordCorrPostcode');
            String corresCounty  = safeValue(paramMap, 'landlordCorrCounty');
            if (String.isBlank(corresCounty)) {
                corresCounty = safeValue(paramMap, 'andlordCorrCounty');
            }
            String corresCountry = safeValue(paramMap, 'landlordCorrCountry');
            String landlordRef   = safeValue(paramMap, 'landlordRef');

            NamePair namePair = normalizeNames(firstname, lastname, companyName);
            firstname = namePair.firstName;
            lastname  = namePair.lastName;

            EI_EWC_AccountTriggerHandler.hasToBeValidated = false;
            EI_EWC_ContactTriggerHandler.hasToBeValidated = false;

            User u = [
                SELECT Id, AccountId, Account.OwnerId
                FROM User
                WHERE Id = :UserInfo.getUserId()
            ];

            Id contactRecordTypeId = Schema.SObjectType.Contact
                .getRecordTypeInfosByDeveloperName()
                .get('EWC_Non_Member_Landlord')
                .getRecordTypeId();

            if (!String.isBlank(email)) {
                List<Contact> duplicateContact = [
                    SELECT Id, AccountId, Salutation, FirstName, LastName, Name, Email, Phone, Landlord_reference__c
                    FROM Contact
                    WHERE Email = :email
                    AND FirstName = :firstname
                    AND LastName = :lastname
                    AND AccountId = :u.AccountId
                    LIMIT 1
                ];
                if(!duplicateContact.isEmpty()){
                    returnVal.put('duplicateLandlord', duplicateContact[0]);
                    return returnVal;
                }
            }

            Contact con = new Contact(
                AccountId = u.AccountId,
                RecordTypeId = contactRecordTypeId,
                IsAutomationBypassed__c = true,
                Salutation = salutation,
                FirstName = firstname,
                LastName = lastname,
                Account_Status__c = 'Active',
                Email = email,
                Phone_Code__c = phoneCode,
                Phone = phone,
                MailingStreet = street,
                MailingCity = city,
                MailingPostalCode = postcode,
                MailingCountry = country,
                MailingState = county,
                Correspondence_Street__c = corresStreet,
                Correspondence_City__c = corresCity,
                Correspondence_Postal_Code__c = corresPost,
                Correspondence_State__c = corresCounty,
                Correspondence_Country__c = corresCountry,
                Landlord_reference__c = landlordRef
            );
            con.Is_Organization__c = isOrguser;
            insert con;

            Deposit__c depositRec = [SELECT Id, Property__c FROM Deposit__c WHERE Id = :depositId];

            Property__c currentProperty = [
                SELECT Id, Property_Owner__c, Property_status__c, 
                        Standardized_Postal_Code__c, Street__c, Town__c, City__c, County__c, State__c, 
                        Postal_Code__c, Country__c, District__c, House_No__c, Local_Authority_Area__c, Primary_Landlord__c, 
                        (SELECT Id, Property__c, Contact__c, Relation_to_Property__c, Landlord_Registrataion_Status__c, 
                                Landlord_Registration_Number__c, Reg__c FROM Property_Allocations__r) 
                FROM Property__c 
                WHERE Id = :depositRec.Property__c
            ];

            List<Deposit__c> otherDeposites = [
                SELECT Id, Property__c FROM Deposit__c 
                WHERE Property__c = :currentProperty.Id AND Id != :depositId
            ];

            // clone property core fields
            Property__c newProperty = new Property__c();
            newProperty.Property_Owner__c       = currentProperty.Property_Owner__c;
            newProperty.Property_status__c      = currentProperty.Property_status__c;
            newProperty.Street__c               = currentProperty.Street__c;
            newProperty.Town__c                 = currentProperty.Town__c;
            newProperty.City__c                 = currentProperty.City__c;
            newProperty.County__c               = currentProperty.County__c;
            newProperty.State__c                = currentProperty.State__c;
            newProperty.Postal_Code__c          = currentProperty.Postal_Code__c;
            newProperty.Country__c              = currentProperty.Country__c;
            newProperty.District__c             = currentProperty.District__c;
            newProperty.House_No__c             = currentProperty.House_No__c;
            newProperty.Local_Authority_Area__c = currentProperty.Local_Authority_Area__c;
            newProperty.Primary_Landlord__c     = currentProperty.Primary_Landlord__c;
            insert newProperty;

            // clone allocations
            List<Property_Allocation__c> newPropertyAllocations = new List<Property_Allocation__c>();
            if (currentProperty.Property_Allocations__r != null) {
                for (Property_Allocation__c paRec : currentProperty.Property_Allocations__r) {
                    Property_Allocation__c newPropertyAllocation = new Property_Allocation__c();
                    newPropertyAllocation.Property__c = newProperty.Id;
                    newPropertyAllocation.Contact__c = paRec.Contact__c;
                    newPropertyAllocation.Relation_to_Property__c = paRec.Relation_to_Property__c;
                    newPropertyAllocation.Landlord_Registrataion_Status__c = paRec.Landlord_Registrataion_Status__c;
                    newPropertyAllocation.Landlord_Registration_Number__c = paRec.Landlord_Registration_Number__c;
                    newPropertyAllocations.add(newPropertyAllocation);
                }
            }
            // add new landlord as Joint Landlord
            newPropertyAllocations.add(new Property_Allocation__c(
                Property__c = newProperty.Id,
                Contact__c = con.Id,
                Relation_to_Property__c = 'Joint Landlord'
            ));
            insert newPropertyAllocations;

            // move deposits
            List<Deposit__c> depositesToUpdate = new List<Deposit__c>();
            depositRec.Property__c = newProperty.Id;
            depositesToUpdate.add(depositRec);
            for (Deposit__c deposit : otherDeposites) {
                deposit.Property__c = newProperty.Id;
                depositesToUpdate.add(deposit);
            }
            update depositesToUpdate;

            // delete original property
            delete currentProperty;

            returnVal.put('landlordCreated', con);
            return returnVal;
        } catch (Exception e){ 
            System.debug('savelandlordDepositSummary error: ' + e.getMessage());
            return null;
        }
    }
    
    //Added by Vijay- To verify the postal code belongs to England or Wales     
    public static String getEnglandWalesCountrys(String PostalCode) {
        String shortPostalCode = safeTrim(PostalCode);
        if (String.isBlank(shortPostalCode)) return '';
        try {
            List<England_Postcodes__mdt> ewcEnglandPostcodeList = [
                SELECT Id FROM England_Postcodes__mdt WHERE Label = :shortPostalCode LIMIT 1
            ];
            if(!ewcEnglandPostcodeList.isEmpty()){
                return 'England';
            }
            List<Wales_Postcodes__mdt> ewcWalesPostcodeList = [
                SELECT Id FROM Wales_Postcodes__mdt WHERE Label = :shortPostalCode LIMIT 1
            ];
            if(!ewcWalesPostcodeList.isEmpty()){
                return 'Wales';
            }
        } catch (Exception e) {
            // swallow and return empty
        }
        return '';
    }

    // Helpers

    private static List<String> getActivePicklistValues(Schema.SObjectField fieldApi) {
        List<String> values = new List<String>();
        Schema.DescribeFieldResult dfr = fieldApi.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) values.add(pe.getValue());
        }
        return values;
    }

    private static Map<String, String> getPicklistValueLabelMap(Schema.SObjectField fieldApi) {
        Map<String, String> mapVal = new Map<String, String>();
        Schema.DescribeFieldResult dfr = fieldApi.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            mapVal.put(pe.getValue(), pe.getLabel());
        }
        return mapVal;
    }

    private static String safeTrim(String s) {
        return (s == null) ? '' : s.trim();
    }

    private static String safeValue(Map<String, Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) return '';
        String v = String.valueOf(m.get(key));
        if (v == null) return '';
        v = v.trim();
        return (v.equalsIgnoreCase('undefined')) ? '' : v;
    }

    private static Boolean safeBoolean(Map<String, Object> m, String key) {
        if (m == null || !m.containsKey(key) || m.get(key) == null) return false;
        Object val = m.get(key);
        if (val instanceof Boolean) return (Boolean) val;
        String s = String.valueOf(val).toLowerCase();
        return 'true'.equals(s) || '1'.equals(s) || 'yes'.equals(s);
    }

    private static String safeEmail(Map<String, Object> m, String key) {
        return safeTrim(safeValue(m, key));
    }

    private class NamePair {
        String firstName;
        String lastName;
    }

    // Name normalization logic:
    // 1) If both provided -> keep both
    // 2) If only first provided -> move to lastName
    // 3) If both blank -> lastName = companyName
    private static NamePair normalizeNames(String first, String last, String company) {
        NamePair np = new NamePair();
        String f = safeTrim(first);
        String l = safeTrim(last);
        String c = safeTrim(company);

        if (!String.isBlank(f) && !String.isBlank(l)) {
            np.firstName = f;
            np.lastName = l;
            return np;
        }
        if (!String.isBlank(f) && String.isBlank(l)) {
            np.firstName = '';
            np.lastName = f;
            return np;
        }
        if (String.isBlank(f) && String.isBlank(l)) {
            np.firstName = '';
            np.lastName = c;
            return np;
        }
        // Only last provided
        np.firstName = '';
        np.lastName = l;
        return np;
    }
}
