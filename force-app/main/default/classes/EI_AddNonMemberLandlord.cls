public without sharing class EI_AddNonMemberLandlord {
    // Public entry points preserved
    @AuraEnabled
    public static List<Contact> savelandlord(
        String branchId,
        String salutation,
        String firstname,
        String lastname,
        String email,
        String phoneCode,
        String phone,
        String companyName,
        String companyPhoneCode,
        String companyPhone,
        Boolean isOrguser,
        String street,
        String city,
        String postcode,
        String country,
        String county,
        String propertyRecId,
        String landRegNumber,
        String landRegStatus
    ) {
        // Normalize inputs
        String normFirst = normalize(firstname);
        String normLast = normalize(lastname);
        String normEmail = normalize(email);
        String normPhoneCode = normalize(phoneCode);
        String normPhone = normalize(phone);
        String normCompanyName = normalize(companyName);
        String normCompanyPhoneCode = normalize(companyPhoneCode);
        String normCompanyPhone = normalize(companyPhone);
        String normStreet = normalize(street);
        String normCity = normalize(city);
        String normPostcode = normalize(postcode);
        String normCountry = normalize(country);
        String normCounty = normalize(county);
        String normBranchId = normalize(branchId);
        String normPropertyId = normalize(propertyRecId);
        String normLandRegNumber = normalize(landRegNumber);
        String normLandRegStatus = normalize(landRegStatus);

        // ISD-40293: enforce max lengths
        if (!String.isBlank(normCity)) {
            normCity = normCity.length() > 40 ? normCity.substring(0, 40) : normCity;
        }
        if (!String.isBlank(normPostcode)) {
            normPostcode = normPostcode.length() > 20 ? normPostcode.substring(0, 20) : normPostcode;
        }

        // Adjust name fallbacks
        NameParts nameParts = normalizeNames(normFirst, normLast, normCompanyName);
        normFirst = nameParts.firstName;
        normLast = nameParts.lastName;

        UserContext uc = getUserContext();
        if (Test.isRunningTest()) {
            // keep your test hook (no change to behavior)
            String testPropNumber = getPropertyRegNumber(normPropertyId, normLandRegNumber);
        }

        String fullNameForSearch = buildFullName(normFirst, normLast);

        try {
            List<Contact> existingMatches = findExistingLandlords(
                fullNameForSearch, normEmail, uc, true
            );

            // SOSL test substitute also added if running test (original behavior kept)
            if (Test.isRunningTest()) {
                List<Contact> conListTest = [
                    SELECT Id, RecordType.Name, Name, Email, EI_Non_Member_Landlord__c,
                           Landlord_Registration_Number__c, Account.RecordType.Name
                    FROM Contact
                    WHERE Email = :normEmail
                    AND EI_Non_Member_Landlord__c = true
                ];
                if (conListTest != null && !conListTest.isEmpty()) {
                    existingMatches.addAll(conListTest);
                }
            }

            // If we found existing contacts, check reg number match and property allocation duplication
            if (!existingMatches.isEmpty()) {
                Boolean regNumMatch = hasAnyRegNumberMatch(existingMatches, normLandRegNumber);

                // Prevent duplicate property allocation
                if (!String.isBlank(normPropertyId)) {
                    if (!hasDuplicatePropertyAllocation(existingMatches, normPropertyId)) {
                        if (regNumMatch) {
                            // allocate first match
                            createPropertyAllocation(existingMatches[0].Id, normPropertyId, normLandRegNumber, normLandRegStatus);
                        } else {
                            // no reg num match: fall through to create new landlord
                            return createNewLandlordAndMaybeAllocate(
                                isOrguser,
                                uc,
                                normCompanyName,
                                normCompanyPhoneCode,
                                normCompanyPhone,
                                normEmail,
                                salutation,
                                normFirst,
                                normLast,
                                normPhoneCode,
                                normPhone,
                                normStreet,
                                normCity,
                                normPostcode,
                                normCountry,
                                normCounty,
                                normBranchId,
                                normPropertyId,
                                normLandRegNumber,
                                normLandRegStatus
                            );
                        }
                    }
                }
                return existingMatches;
            } else {
                // Nothing found: create fresh landlord/contact
                return createNewLandlordAndMaybeAllocate(
                    isOrguser,
                    uc,
                    normCompanyName,
                    normCompanyPhoneCode,
                    normCompanyPhone,
                    normEmail,
                    salutation,
                    normFirst,
                    normLast,
                    normPhoneCode,
                    normPhone,
                    normStreet,
                    normCity,
                    normPostcode,
                    normCountry,
                    normCounty,
                    normBranchId,
                    normPropertyId,
                    normLandRegNumber,
                    normLandRegStatus
                );
            }
        } catch (Exception e) {
            // Preserve original behavior returning null on exception
            return null;
        }
    }

    // Helper: encapsulate user context
    private class UserContext {
        Id userId;
        Id accountId;
        Id accountOwnerId;
    }
    private static UserContext getUserContext() {
        User u = [
            SELECT Id, AccountId, Account.OwnerId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        UserContext uc = new UserContext();
        uc.userId = u.Id;
        uc.accountId = u.AccountId;
        uc.accountOwnerId = u.Account.OwnerId;
        return uc;
    }

    // Helper: build full name
    private static String buildFullName(String firstName, String lastName) {
        String f = String.isBlank(firstName) ? '' : firstName.trim();
        String l = String.isBlank(lastName) ? '' : lastName.trim();
        return (f + ' ' + l).trim();
    }

    // Helper: normalize string
    private static String normalize(String s) {
        if (s == null) return '';
        if (s == 'undefined') return '';
        return s.trim();
    }

    // Helper: decide first/last based on inputs/company fallback
    private class NameParts {
        String firstName;
        String lastName;
    }
    private static NameParts normalizeNames(String firstName, String lastName, String companyName) {
        NameParts np = new NameParts();
        String f = normalize(firstName);
        String l = normalize(lastName);
        String c = normalize(companyName);

        if (!String.isBlank(f) && !String.isBlank(l)) {
            np.firstName = f;
            np.lastName = l;
            return np;
        }
        if (!String.isBlank(f) && String.isBlank(l)) {
            np.lastName = f;
            np.firstName = '';
            return np;
        }
        if (String.isBlank(f) && String.isBlank(l)) {
            np.lastName = c;
            np.firstName = '';
            return np;
        }
        // default
        np.firstName = f;
        np.lastName = l;
        return np;
    }

    // Helper: find existing non-member landlords by name/email and creation context
    private static List<Contact> findExistingLandlords(String fullNameForSearch, String email, UserContext uc, Boolean filterByRtAndFlag) {
        List<Contact> results = new List<Contact>();
        if (String.isBlank(email)) {
            return results;
        }

        // SOSL for fast name/email search
        List<List<SObject>> searchNameList = [
            FIND :fullNameForSearch IN ALL FIELDS
            RETURNING Contact(
                Id, FirstName, LastName, Name, Landlord_Registration_Number__c
                WHERE Email = :email
                AND (CreatedById = :uc.userId OR Account.Parent_person_account__c = :uc.accountId)
                AND (
                    (Account.RecordType.Name = 'Individual Landlord' OR Account.RecordType.Name = 'Corporate Landlord')
                )
                AND EI_Non_Member_Landlord__c = true
            )
        ];

        if (searchNameList != null && !searchNameList.isEmpty() && searchNameList[0] != null && !searchNameList[0].isEmpty()) {
            for (SObject sob : searchNameList[0]) {
                results.add((Contact)sob);
            }
        }
        return results;
    }

    // Helper: check if any registration number overlaps
    private static Boolean hasAnyRegNumberMatch(List<Contact> cons, String inputRegNumber) {
        if (String.isBlank(inputRegNumber)) return false;
        for (Contact c : cons) {
            if (!String.isBlank(c.Landlord_Registration_Number__c)) {
                String existing = c.Landlord_Registration_Number__c;
                if (existing.contains(inputRegNumber) || inputRegNumber.contains(existing)) {
                    return true;
                }
            }
        }
        return false;
    }

    // Helper: property allocation duplication check
    private static Boolean hasDuplicatePropertyAllocation(List<Contact> cons, String propertyId) {
        if (String.isBlank(propertyId) || cons.isEmpty()) return false;
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : cons) contactIds.add(c.Id);

        List<Property_Allocation__c> allocs = [
            SELECT Id, Contact__c, Property__c
            FROM Property_Allocation__c
            WHERE Property__c = :propertyId
            AND Contact__c IN :contactIds
            LIMIT 1
        ];
        return !allocs.isEmpty();
    }

    // Helper: create a property allocation record
    private static void createPropertyAllocation(Id contactId, String propertyId, String landRegNumber, String landRegStatus) {
        if (contactId == null || String.isBlank(propertyId)) return;
        Property_Allocation__c pall = new Property_Allocation__c(
            Contact__c = contactId,
            Property__c = propertyId,
            Landlord_Registration_Number__c = landRegNumber,
            Landlord_Registrataion_Status__c = landRegStatus
        );
        insert pall;
    }

    // Helper: create new landlord Account (+Contact if corporate), return the created contact
    private static List<Contact> createNewLandlordAndMaybeAllocate(
        Boolean isOrgUser,
        UserContext uc,
        String companyName,
        String companyPhoneCode,
        String companyPhone,
        String email,
        String salutation,
        String firstName,
        String lastName,
        String phoneCode,
        String phone,
        String street,
        String city,
        String postcode,
        String country,
        String county,
        String branchId,
        String propertyId,
        String landRegNumber,
        String landRegStatus
    ) {
        List<Contact> out = new List<Contact>();
        Account acc;
        if (isOrgUser == true) {
            // Corporate Landlord
            Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Corporate_Landlord').getRecordTypeId();
            acc = new Account(
                Name = companyName,
                Phone_Code__c = companyPhoneCode,
                Phone = companyPhone,
                RecordTypeId = rtId,
                Email__c = email,
                Parent_person_account__c = uc.accountId,
                OwnerId = uc.accountOwnerId,
                BillingStreet = street,
                BillingCity = city,
                BillingPostalCode = postcode,
                BillingCountry = country,
                BillingState = county
            );
            insert acc;

            Contact con = new Contact(
                AccountId = acc.Id,
                EI_Non_Member_Landlord__c = true,
                Salutation = salutation,
                FirstName = firstName,
                LastName = lastName,
                Email = email,
                Phone_Code__c = phoneCode,
                Phone = phone,
                MailingStreet = street,
                MailingCity = city,
                MailingPostalCode = postcode,
                MailingCountry = country,
                MailingState = county,
                LandLord_Registration_Number__c = landRegNumber,
                LandLord_Registration_Status__c = landRegStatus,
                Branch__c = branchId,
                Account_Status__c = 'Active'
            );
            insert con;

            out.add(queryContactByAccount(acc.Id));
            if (!String.isBlank(propertyId)) {
                createPropertyAllocation(con.Id, propertyId, landRegNumber, landRegStatus);
            }
        } else {
            // Individual Landlord (Person Account)
            Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Individual_Landlord').getRecordTypeId();
            acc = new Account();
            acc.RecordTypeId = rtId;
            acc.OwnerId = uc.accountOwnerId;
            acc.Parent_person_account__c = uc.accountId;

            acc.FirstName = firstName;
            acc.LastName = lastName;
            acc.Salutation = salutation;
            acc.PersonEmail = email;
            acc.Email__c = email;
            acc.PersonHomePhone = phone;
            acc.Phone_Code__pc = phoneCode;
            acc.Phone = phone;

            acc.BillingStreet = street;
            acc.BillingCity = city;
            acc.BillingPostalCode = postcode;
            acc.BillingCountry = country;
            acc.BillingState = county;

            acc.PersonMailingStreet = street;
            acc.PersonMailingCity = city;
            acc.PersonMailingPostalCode = postcode;
            acc.PersonMailingCountry = country;
            acc.PersonMailingState = county;

            acc.LandLord_Registration_Number__pc = landRegNumber;
            acc.LandLord_Registration_Status__pc = landRegStatus;
            acc.EI_Non_Member_Landlord__pc = true;
            acc.Account_Status__pc = 'Active';
            acc.Branch__pc = branchId;

            insert acc;

            // Query the person contact
            Contact personCon = queryContactByAccount(acc.Id);
            out.add(personCon);

            if (!String.isBlank(propertyId)) {
                createPropertyAllocation(personCon.Id, propertyId, landRegNumber, landRegStatus);
            }
        }
        return out;
    }

    private static Contact queryContactByAccount(Id accountId) {
        return [
            SELECT Id, Branch__c, Account.Name, AccountId, FirstName, MailingStreet, MailingCity, MailingCountry,
                   MailingState, MailingPostalCode, Phone, Email, LastName
            FROM Contact
            WHERE AccountId = :accountId
            LIMIT 1
        ];
    }

    // Kept your existing helper methods with small cleanups only where safe

    public static String getPropertyRegNumber(String propertyId, String allLandlordRegNumber) {
        String propertyRegNumber = '';
        if (String.isBlank(propertyId)) return propertyRegNumber;

        Property__c propRecord = [
            SELECT Id, Name, Local_Authority_Area__c, Postal_Code__c, City__c, County__c
            FROM Property__c
            WHERE Id = :propertyId
            LIMIT 1
        ];

        List<Area_Code_For_Landlord__mdt> metadataList = [
            SELECT Id, MasterLabel, Local_Authority_Area__c, Postal_Code__c, Identifying_Code__c
            FROM Area_Code_For_Landlord__mdt
        ];
        Map<String, String> metadataMapLabel = new Map<String, String>();
        Map<String, String> metadataMapAdminArea = new Map<String, String>();
        for (Area_Code_For_Landlord__mdt mdt : metadataList) {
            metadataMapLabel.put(mdt.MasterLabel, mdt.Identifying_Code__c);
            metadataMapAdminArea.put(mdt.Local_Authority_Area__c, mdt.Identifying_Code__c);
        }

        if (String.isBlank(allLandlordRegNumber)) {
            return propertyRegNumber;
        } else {
            String identificationCode = '';
            if (metadataMapAdminArea.containsKey(propRecord.Local_Authority_Area__c)) {
                identificationCode = String.valueOf(metadataMapAdminArea.get(propRecord.Local_Authority_Area__c));
            } else if (metadataMapLabel.containsKey(propRecord.Local_Authority_Area__c)) {
                identificationCode = String.valueOf(metadataMapLabel.get(propRecord.Local_Authority_Area__c));
            } else if (metadataMapAdminArea.containsKey(propRecord.City__c)) {
                identificationCode = String.valueOf(metadataMapAdminArea.get(propRecord.City__c));
            } else if (metadataMapLabel.containsKey(propRecord.City__c)) {
                identificationCode = String.valueOf(metadataMapLabel.get(propRecord.City__c));
            }

            if (String.isBlank(identificationCode)) {
                propertyRegNumber = '';
            } else {
                List<String> landRegList = allLandlordRegNumber.split(',');
                for (String s : landRegList) {
                    if (s != null && s.contains(identificationCode)) {
                        propertyRegNumber = s;
                    }
                }
            }
        }
        return propertyRegNumber;
    }

    @AuraEnabled
    public static Property__c getPropertyDetails(String propertyId) {
        if (String.isBlank(propertyId)) return null;

        List<Property__c> oldpropertyRec = [
            SELECT Id, (SELECT Id FROM Property_Allocations__r), Local_authority_registration_details__c,
                   House_No__c, City__c, Country__c, County__c, District__c, State__c,
                   Street__c, Town__c, Name, Postal_Code__c
            FROM Property__c
            WHERE Id = :propertyId
            LIMIT 1
        ];
        if (oldpropertyRec.isEmpty()) return null;

        Property__c base = oldpropertyRec[0];
        if (base.Property_Allocations__r != null && base.Property_Allocations__r.size() > 0) {
            base.Local_authority_registration_details__c = '';
            update base;

            List<Property__c> toUpdate = new List<Property__c>();
            for (Property_Allocation__c prc : [
                SELECT Id, Landlord_Registration_Number__c,
                       Property__r.Id, Property__r.Local_authority_registration_details__c,
                       Property__r.House_No__c, Property__r.City__c, Property__r.Country__c,
                       Property__r.County__c, Property__r.District__c, Property__r.State__c,
                       Property__r.Street__c, Property__r.Town__c, Property__r.Name, Property__r.Postal_Code__c
                FROM Property_Allocation__c
                WHERE Property__r.Id = :propertyId
            ]) {
                if (prc.Property__r.Local_authority_registration_details__c == null) {
                    prc.Property__r.Local_authority_registration_details__c = prc.Landlord_Registration_Number__c;
                } else {
                    prc.Property__r.Local_authority_registration_details__c =
                        prc.Property__r.Local_authority_registration_details__c + ', ' + prc.Landlord_Registration_Number__c;
                }
                toUpdate.add(prc.Property__r);
            }
            if (!toUpdate.isEmpty()) {
                // Update only once (take first is consistent with original code)
                update toUpdate[0];
                return toUpdate[0];
            }
            return base;
        } else {
            return base;
        }
    }

    @AuraEnabled
    public static List<Property_Allocation__c> landlordList(String propertyId) {
        return [
            SELECT Id, Contact__c, Contact__r.FirstName, Contact__r.LastName,
                   Contact__r.Email, Contact__r.Phone, Contact__r.LandLord_Registration_Number__c,
                   Landlord_Registration_Number__c
            FROM Property_Allocation__c
            WHERE Property__c = :propertyId
        ];
    }

    @AuraEnabled
    public static Map<String, String> landlordRegistrationStatusList() {
        Map<String, String> lanRegStatusList = new Map<String, String>();
        Schema.DescribeFieldResult fieldResultRegStatus = Account.LandLord_Registration_Status__pc.getDescribe();
        for (Schema.PicklistEntry p : fieldResultRegStatus.getPicklistValues()) {
            lanRegStatusList.put(p.getValue(), p.getLabel());
        }
        return lanRegStatusList;
    }

    @AuraEnabled
    public static Map<String, SObject> checkDuplicateRecord(String email, String firstname, String surname) {
        Map<String, SObject> returnVal = new Map<String, SObject>();

        String normEmail = normalize(email);
        String fullNameForSearch = buildFullName(normalize(firstname), normalize(surname));

        List<User> userlistEmail = [
            SELECT Id, Username, ContactId, Profile.UserLicense.Name, Phone, Email, Name, IsActive
            FROM User
            WHERE Profile.UserLicense.Name = 'Customer Community Login'
            AND (Email = :normEmail OR Username = :normEmail)
        ];

        List<List<SObject>> searchNameList = [
            FIND :fullNameForSearch IN ALL FIELDS
            RETURNING Contact(
                Id, Name
                WHERE Email = :normEmail
                AND CreatedById = :UserInfo.getUserId()
                AND (Account.RecordType.Name = 'Individual Landlord' OR Account.RecordType.Name = 'Corporate Landlord')
            )
        ];

        if (!searchNameList.isEmpty() && !searchNameList[0].isEmpty()) {
            returnVal.put('Duplicate Name', searchNameList[0][0]);
            return returnVal;
        } else {
            // Preserve original behavior: put a dummy user object if none
            User obj = new User();
            returnVal.put('No duplicate', obj);
            return returnVal;
        }
    }

    @AuraEnabled
    public static List<String> getPhoneCodePiclistValues() {
        try {
            Schema.DescribeFieldResult fieldDescription = Contact.Phone_Code__c.getDescribe();
            List<String> countryCodes = new List<String>();
            for (Schema.PicklistEntry cc : fieldDescription.getPicklistValues()) {
                if (cc.isActive()) {
                    countryCodes.add(cc.getValue());
                }
            }
            return countryCodes;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // TGK-1831
    @AuraEnabled
    public static Account getcareofLlddetails() {
        try {
            List<Account> getDetails = [
                SELECT Id, C_o_Landlord_Address__c, C_o_Postcode__c, Transfer_deposit_preference__c,
                       C_o_Landlord_Country__c, C_o_City__c, C_o_Phone_Code__c, C_o_Postal_Code__c,
                       C_o_Landlord_Email_Address__c, C_o_Landlord_Telephone__c
                FROM Account
                WHERE Id IN (SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId())
                LIMIT 1
            ];
            if (!getDetails.isEmpty()) {
                return getDetails[0];
            } else {
                return null;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<England_Postcodes__mdt> getEnglandWalesPostCode(String postalCode) {
        // Preserved original behavior (returns full list)
        return [
            SELECT Id, Label, QualifiedApiName, DeveloperName, MasterLabel
            FROM England_Postcodes__mdt
        ];
    }

    // TGK-1831 - verify postal code belongs to England or Wales
    @AuraEnabled
    public static String getEnglandWalesCountrys(String postalCode) {
        String baseCountry = '';
        if (!String.isBlank(postalCode) && postalCode.contains(' ')) {
            String shortPostalCode = postalCode.substringBefore(' ').trim();
            List<England_Postcodes__mdt> ewcEnglandPostcodeList = [
                SELECT Id, Label FROM England_Postcodes__mdt WHERE Label = :shortPostalCode
            ];
            List<Wales_Postcodes__mdt> ewcWalesPostcodeList = [
                SELECT Id, Label FROM Wales_Postcodes__mdt WHERE Label = :shortPostalCode
            ];
            if (!ewcEnglandPostcodeList.isEmpty()) {
                baseCountry = 'England';
            } else if (!ewcWalesPostcodeList.isEmpty()) {
                baseCountry = 'Wales';
            }
        }
        return baseCountry;
    }
}
