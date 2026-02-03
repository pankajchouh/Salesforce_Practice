/**
 * @Apex Class Name     : EI_EWC_ManageProperties
 * @Created Date        : 02-07-2023
 * @Description         : Creating Properties and used in EI_EWC_AddProperty LWC Component
 * @Author              : Kamal Kant
 * @Last Modified Date  : 2025-12-03
 * @Last Modified By    : Refactor
 * @Ver                 : 1.1
 * @Modifications       : Refactor for readability, governor safety, error handling, and hygiene
**/
public without sharing class EI_EWC_ManageProperties {

    // Constants
    private static final String REL_PRIMARY = 'Primary Landlord';
    private static final String REL_JOINT   = 'Joint Landlord';
    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_INACTIVE = 'Inactive';
    private static final String USER_LICENSE_COMMUNITY_LOGIN = 'Customer Community Login';
    private static final String RT_PROPERTY_EWC = 'EWC Property';

    // Cached describes per-transaction
    private static Map<String, String> cacheAccountRegStatuses;
    private static Map<String, String> cacheAllocationRegStatuses;
    private static List<String> cacheContactPhoneCodePicklist;

    /* Wrapper class */
    public class managePropertiesWrapper {
        @AuraEnabled public User userData { get; set; }
        @AuraEnabled public List<String> permissionList { get; set; }
        public managePropertiesWrapper(User userData, List<String> permissionList) {
            this.userData = userData;
            this.permissionList = permissionList;
        }
    }

    // Utility: current user with common fields
    private static User getCurrentUserBasic() {
        return [
            SELECT Id, AccountId, ContactId, Name, Profile.Name, User_Type__c,
                   Contact.Job_role__c, Contact.Additional_Permission__c, Contact.AccountId,
                   Account.Parent_person_account__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    private static Id getPropertyRecordTypeId() {
        return Schema.SObjectType.Property__c.getRecordTypeInfosByName().get(RT_PROPERTY_EWC).getRecordTypeId();
    }

    private static void throwAura(Exception ex) {
        throw new AuraHandledException(ex.getMessage());
    }

    @AuraEnabled(cacheable=true)
    public static List<managePropertiesWrapper> getManagePropertiesWrapper(String branchId) {
        try {
            User userRecord = getCurrentUserBasic();
            List<String> permList = EI_EWC_DepositSummaryApx.getUserRolesAndPermissions(userRecord, branchId);
            return new List<managePropertiesWrapper>{ new managePropertiesWrapper(userRecord, permList) };
        } catch (Exception ex) {
            throwAura(ex);
            return null;
        }
    }

    @AuraEnabled
    public static List<Contact> serachlandlord(String searchField, String propertyId, String branchId) {
        Set<Id> currentLandlordsIds = new Set<Id>();
        for (Property_Allocation__c pa : [
            SELECT Contact__c
            FROM Property_Allocation__c
            WHERE Property__c = :propertyId
        ]) {
            if (pa.Contact__c != null) currentLandlordsIds.add(pa.Contact__c);
        }

        String searchKey = '%' + searchField + '%';
        User u = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        if (String.isNotBlank(branchId)) {
            return [
                SELECT Id, Title, FirstName, LastName, Name, Email, Phone, Landlord_reference__c
                FROM Contact
                WHERE Branch__c = :branchId
                  AND RecordType.Name LIKE '%Landlord%'
                  AND Name LIKE :searchKey
                  AND Id NOT IN :currentLandlordsIds
            ];
        }

        return [
            SELECT Id, Title, FirstName, LastName, Name, Email, Phone, Landlord_reference__c
            FROM Contact
            WHERE AccountId = :u.AccountId
              AND RecordType.Name LIKE '%Landlord%'
              AND Name LIKE :searchKey
              AND Id NOT IN :currentLandlordsIds
        ];
    }

    @AuraEnabled
    public static Contact archieveLandlord(Contact landlordRec, String status) {
        Contact con = [
            SELECT Id, Account_Status__c
            FROM Contact
            WHERE Id = :landlordRec.Id
            LIMIT 1
        ];
        if (status != null && status.contains(STATUS_INACTIVE)) {
            con.Account_Status__c = STATUS_INACTIVE;
        } else if (status != null && status.contains(STATUS_ACTIVE)) {
            con.Account_Status__c = STATUS_ACTIVE;
        }
        update con;
        return con;
    }

    @AuraEnabled
    public static String replacePrimeLandlord(Property__c propRec, Contact conRec, Boolean status) {
        try {
            Property_Allocation__c primary = [
                SELECT Id, Contact__c
                FROM Property_Allocation__c
                WHERE Property__c = :propRec.Id AND Relation_to_Property__c = :REL_PRIMARY
                LIMIT 1
            ];
            primary.Contact__c = conRec.Id;

            if (status == true) {
                List<Property_Allocation__c> delList = [
                    SELECT Id
                    FROM Property_Allocation__c
                    WHERE Contact__c = :conRec.Id
                      AND Relation_to_Property__c != :REL_PRIMARY
                ];
                if (!delList.isEmpty()) delete delList;
            }
            update primary;
            return 'Success';
        } catch (Exception ex) {
            throwAura(ex);
            return null;
        }
    }

    @AuraEnabled
    public static Property_Allocation__c getJointLand(Property__c propRec) {
        List<Property_Allocation__c> conList = [
            SELECT Id, Relation_to_Property__c, Contact__r.Name, Contact__c
            FROM Property_Allocation__c
            WHERE Property__c = :propRec.Id
              AND Relation_to_Property__c != :REL_PRIMARY
            LIMIT 1
        ];
        return conList.isEmpty() ? null : conList[0];
    }

    @AuraEnabled
    public static List<Property_Allocation__c> removeLand(String propAllocationid, String relation, String jointLandlordId) {
        List<Property_Allocation__c> prop = [
            SELECT Id, Relation_to_Property__c, Property__c, Contact__c
            FROM Property_Allocation__c
            WHERE Id = :propAllocationid
            LIMIT 1
        ];
        if (prop.isEmpty()) return new List<Property_Allocation__c>();

        Property_Allocation__c pa = prop[0];

        if (relation == REL_JOINT) {
            delete prop;
        } else if (relation == REL_PRIMARY) {
            List<Property_Allocation__c> delProp = [
                SELECT Id
                FROM Property_Allocation__c
                WHERE Contact__c = :jointLandlordId
                  AND Relation_to_Property__c != :REL_PRIMARY
                  AND Property__c = :pa.Property__c
            ];
            if (!delProp.isEmpty()) delete delProp;

            if (String.isNotBlank(jointLandlordId)) {
                pa.Contact__c = jointLandlordId;
                update pa;
            }
        }

        return [
            SELECT Id, Property_Address__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                   Contact__r.Email, Contact__r.Phone, Contact__r.Phone_Code__c, Landlord_Registration_Number__c,
                   Relation_to_Property__c, Property__r.Property_Owner__c
            FROM Property_Allocation__c
            WHERE Property__c = :pa.Property__c
        ];
    }

    @AuraEnabled
    public static List<Contact> searchlandlord(String searchField, Property__c propRec, Boolean status) {
        User u = [
            SELECT Id, AccountId, ContactId, Account.Parent_person_account__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        User uParentUser;
        if (u.Account != null && u.Account.Parent_person_account__c != null) {
            uParentUser = [
                SELECT Id
                FROM User
                WHERE AccountId = :u.Account.Parent_person_account__c
                LIMIT 1
            ];
        }

        Set<Id> excludeIds = new Set<Id>();
        if (status == false) {
            for (Property_Allocation__c pa : [
                SELECT Contact__c FROM Property_Allocation__c WHERE Property__c = :propRec.Id
            ]) if (pa.Contact__c != null) excludeIds.add(pa.Contact__c);
        } else {
            for (Property_Allocation__c pa : [
                SELECT Contact__c FROM Property_Allocation__c
                WHERE Property__c = :propRec.Id AND Relation_to_Property__c = :REL_PRIMARY
            ]) if (pa.Contact__c != null) excludeIds.add(pa.Contact__c);
        }

        String likeKey = '%' + searchField + '%';
        Id parentUserId = (uParentUser == null) ? null : uParentUser.Id;

        return [
            SELECT Id, Title, FirstName, LastName, Email, Phone, Landlord_reference__c
            FROM Contact
            WHERE Id NOT IN :excludeIds
              AND (Account.RecordType.Name = 'EWC Landlord' OR Account.RecordType.Name = 'EWC Agent')
              AND (AccountId = :u.AccountId OR CreatedById = :parentUserId)
              AND (Name LIKE :likeKey OR FirstName LIKE :likeKey OR LastName LIKE :likeKey OR Email LIKE :likeKey)
        ];
    }

    @AuraEnabled
    public static Map<String, SObject> saveLandlord(Contact landlordRec, String street, String city, String postalCode, String email, String phoneCode, String phone, String reference, String corrStreet, String corrCity, String corrPostalcode) {
        Map<String, SObject> ret = new Map<String, SObject>();
        try {
            Contact con = [
                SELECT Id, Email, Phone_Code__c, Phone, Landlord_reference__c,
                       MailingStreet, MailingCity, MailingPostalCode,
                       Correspondence_Street__c, Correspondence_City__c, Correspondence_Postal_Code__c
                FROM Contact
                WHERE Id = :landlordRec.Id
                LIMIT 1
            ];

            if (con.Email != email) {
                List<User> userlistEmail = [
                    SELECT Id, Username, ContactId, Profile.UserLicense.Name, Phone, Email, Name, IsActive
                    FROM User
                    WHERE Profile.UserLicense.Name = :USER_LICENSE_COMMUNITY_LOGIN
                      AND (Email = :email.trim() OR Username = :email.trim())
                    LIMIT 1
                ];
                if (!userlistEmail.isEmpty()) {
                    ret.put('Duplicate Email', userlistEmail[0]);
                    return ret;
                }
            }

            if (con.Email != email || Test.isRunningTest()) {
                List<List<SObject>> searchNameList = [
                    FIND :con.Name IN ALL FIELDS
                    RETURNING Contact(Id, Name WHERE Email = :landlordRec.Email.trim()
                        AND CreatedById = :UserInfo.getUserId()
                        AND (Account.RecordType.Name = 'EWC Landlord' OR Account.RecordType.Name = 'EWC Agent'))
                ];
                // Original duplicate-name check was commented out; keeping behavior
            }

            con.MailingStreet = street;
            con.MailingCity = city;
            con.MailingPostalCode = postalCode;
            con.Phone_Code__c = phoneCode;
            con.Phone = phone;
            con.Email = email;
            con.Landlord_reference__c = reference;
            if (corrStreet != null) con.Correspondence_Street__c = corrStreet;
            if (corrCity != null) con.Correspondence_City__c = corrCity;
            if (corrPostalcode != null) con.Correspondence_Postal_Code__c = corrPostalcode;

            update con;

            ret.put('updated', con);
            return ret;
        } catch (Exception ex) {
            ret.put(ex.getMessage(), new User());
            return ret;
        }
    }

    @AuraEnabled
    public static Property__c updatePropDetails(Property__c updtProperty) {
        update updtProperty;
        return [
            SELECT Id, NoOfDeposit__c, Property_status__c, House_No__c, City__c, Country__c, County__c, District__c, State__c,
                   Street__c, Town__c, Name, Postal_Code__c,
                   (SELECT Id, Property_Address__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                           Contact__r.Email, Contact__r.Phone, Contact__r.Phone_Code__c, Landlord_Registration_Number__c,
                           Relation_to_Property__c
                    FROM Property_Allocations__r)
            FROM Property__c
            WHERE Id = :updtProperty.Id
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static List<String> getEnglandPostCodes() {
        try {
            List<String> out = new List<String>();
            for (England_Postcodes__mdt m : [SELECT Label FROM England_Postcodes__mdt]) out.add(m.Label);
            return out.isEmpty() ? null : out;
        } catch (Exception ex) {
            throwAura(ex);
            return null;
        }
    }

    @AuraEnabled
    public static List<String> getWalesPostCodes() {
        try {
            List<String> out = new List<String>();
            for (Wales_Postcodes__mdt m : [SELECT Label FROM Wales_Postcodes__mdt]) out.add(m.Label);
            return out.isEmpty() ? null : out;
        } catch (Exception ex) {
            throwAura(ex);
            return null;
        }
    }

    @AuraEnabled
    public static List<Contact> myLandlordList(String searchVar, String status, String branchId) {
        QueryLimits__c limits = QueryLimits__c.getValues('All Limits');
        Integer noOfLandlord = limits == null || limits.LandlordLimit__c == null
            ? 200
            : Integer.valueOf(limits.LandlordLimit__c);

        User u = [
            SELECT Id, AccountId, Name, ContactId, Account.Parent_person_account__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        String searchTxt = '%' + (searchVar == null ? '' : searchVar) + '%';

        if (String.isNotBlank(searchVar)) {
            List<Contact> conList1;
            if (String.isBlank(branchId)) {
                conList1 = [
                    SELECT Id, AccountId, RecordTypeId, Salutation, Landlord_reference__c, Registered_Company_Name__c,
                           Is_Organization__c, RecordType_Name__c, Title, Correspondence_Address__c, Number_of_properties__c,
                           FirstName, LastName, Account_Status__c, Phone, Email, LandLord_Registration_Number__c,
                           LandLord_Registration_Status__c, AddressFormula__c, Account.Deposit_Protections__c,
                           Account.Number_of_Properties__c, Account.Total_Deposits__c
                    FROM Contact
                    WHERE Account_Status__c = :status
                      AND (CreatedById = :UserInfo.getUserId() OR AccountId = :u.AccountId)
                      AND RecordType.Name LIKE '%Landlord%'
                      AND Id != :u.ContactId
                    LIMIT :noOfLandlord
                ];
            } else {
                conList1 = [
                    SELECT Id, AccountId, Branch__c, Salutation, Number_of_Deposits__c, Landlord_reference__c,
                           Registered_Company_Name__c, Is_Organization__c, RecordType_Name__c, Title, Correspondence_Address__c,
                           Number_of_properties__c, FirstName, LastName, Account_Status__c, Phone, Email,
                           LandLord_Registration_Number__c, LandLord_Registration_Status__c, AddressFormula__c,
                           Account.Deposit_Protections__c, Account.Number_of_Properties__c
                    FROM Contact
                    WHERE Account_Status__c = :status
                      AND Branch__c = :branchId
                      AND (CreatedById = :UserInfo.getUserId() OR AccountId = :u.AccountId)
                      AND RecordType.Name LIKE '%Landlord%'
                      AND Id != :u.ContactId
                    LIMIT :noOfLandlord
                ];
            }

            List<Contact> direct = new List<Contact>();
            for (Contact c : conList1) {
                if (c.LandLord_Registration_Number__c != null && c.LandLord_Registration_Number__c.contains(searchVar)) {
                    direct.add(c);
                }
            }
            if (!direct.isEmpty()) return direct;

            List<Contact> conList2;
            if (String.isBlank(branchId)) {
                conList2 = [
                    SELECT Id, AccountId, RecordTypeId, Salutation, Number_of_Deposits__c, Landlord_reference__c,
                           Is_Organization__c, RecordType_Name__c, Registered_Company_Name__c, Title,
                           Correspondence_Address__c, Number_of_properties__c, FirstName, LastName, Account_Status__c,
                           Phone, Email, AddressFormula__c, Account.Deposit_Protections__c, Account.Number_of_Properties__c,
                           Account.Total_Deposits__c
                    FROM Contact
                    WHERE Account_Status__c = :status
                      AND (Name LIKE :searchTxt OR FirstName LIKE :searchTxt OR LastName LIKE :searchTxt
                           OR Email LIKE :searchTxt OR AddressFormula__c LIKE :searchTxt
                           OR Phone LIKE :searchTxt OR Landlord_reference__c LIKE :searchTxt)
                      AND (CreatedById = :UserInfo.getUserId() OR AccountId = :u.AccountId)
                      AND RecordType.Name LIKE '%Landlord%'
                      AND Id != :u.ContactId
                    LIMIT :noOfLandlord
                ];
            } else {
                conList2 = [
                    SELECT Id, AccountId, Salutation, Number_of_Deposits__c, Landlord_reference__c,
                           Is_Organization__c, RecordType_Name__c, Registered_Company_Name__c, Title,
                           Correspondence_Address__c, Number_of_properties__c, FirstName, LastName, Account_Status__c,
                           Phone, Email, LandLord_Registration_Number__c, LandLord_Registration_Status__c,
                           AddressFormula__c, Account.Deposit_Protections__c, Account.Number_of_Properties__c
                    FROM Contact
                    WHERE Account_Status__c = :status
                      AND (Name LIKE :searchTxt OR Email LIKE :searchTxt OR AddressFormula__c LIKE :searchTxt
                           OR Phone LIKE :searchTxt OR Landlord_reference__c LIKE :searchTxt)
                      AND Branch__c = :branchId
                      AND (CreatedById = :UserInfo.getUserId() OR AccountId = :u.AccountId)
                      AND RecordType.Name LIKE '%Landlord%'
                      AND Id != :u.ContactId
                    LIMIT :noOfLandlord
                ];
            }
            return conList2;
        }

        List<Contact> conList3;
        if (String.isBlank(branchId)) {
            conList3 = [
                SELECT Id, AccountId, RecordTypeId, Is_Organization__c,
                       (SELECT Id, Property__r.NoOfDeposit__c FROM Property_Allocations__r)
                FROM Contact
                WHERE (CreatedById = :UserInfo.getUserId() OR AccountId = :u.AccountId)
                  AND RecordType.Name LIKE '%Landlord%'
                  AND Id != :u.ContactId
                LIMIT :noOfLandlord
            ];
        } else {
            conList3 = [
                SELECT Id, AccountId, RecordTypeId, Is_Organization__c, Branch__c,
                       (SELECT Id, Property__r.NoOfDeposit__c FROM Property_Allocations__r)
                FROM Contact
                WHERE Branch__c = :branchId
                  AND (CreatedById = :UserInfo.getUserId() OR AccountId = :u.AccountId)
                  AND RecordType.Name LIKE '%Landlord%'
                  AND Id != :u.ContactId
                LIMIT :noOfLandlord
            ];
        }

        List<Contact> shadowToUpdate = new List<Contact>();
        for (Contact c : conList3) {
            Integer propCount = (c.Property_Allocations__r == null) ? 0 : c.Property_Allocations__r.size();
            Integer depCount = 0;
            if (c.Property_Allocations__r != null) {
                for (Property_Allocation__c pa : c.Property_Allocations__r) {
                    if (pa.Property__r != null && pa.Property__r.NoOfDeposit__c != null) {
                        depCount += Integer.valueOf(pa.Property__r.NoOfDeposit__c);
                    }
                }
            }
            shadowToUpdate.add(new Contact(
                Id = c.Id,
                Number_of_properties__c = String.valueOf(propCount),
                Number_of_Deposits__c = String.valueOf(depCount)
            ));
        }
        if (!shadowToUpdate.isEmpty()) update shadowToUpdate;

        List<Contact> finalList = [
            SELECT Id, AccountId, Is_Organization__c, Landlord_reference__c, Number_of_properties__c, Number_of_Deposits__c,
                   Salutation, FirstName, LastName, Account_Status__c, Phone, Email, LandLord_Registration_Number__c,
                   LandLord_Registration_Status__c, AddressFormula__c, Account.Deposit_Protections__c,
                   Account.Number_of_Properties__c, Account.Total_Deposits__c
            FROM Contact
            WHERE Id IN :conList3
              AND Account_Status__c = :status
        ];
        return finalList.isEmpty() ? null : finalList;
    }

    public class userInformation {
        @AuraEnabled public Contact con { get; set; }
    }

    @AuraEnabled
    public static List<Property_Allocation__c> fetchPropertylist(String status, String branchId) {
        try {
            QueryLimits__c limits = QueryLimits__c.getValues('All Limits');
            Integer noOfProp = limits == null || limits.PropertiesLimit__c == null
                ? 500
                : Integer.valueOf(limits.PropertiesLimit__c);

            User u = getCurrentUserBasic();

            List<Property_Allocation__c> out = new List<Property_Allocation__c>();
            List<Property__c> props;
            if (String.isNotBlank(branchId)) {
                props = [
                    SELECT Id, Property_Owner__c, NoOfDeposit__c, House_No__c, Street__c, City__c, County__c,
                           Postal_Code__c, Country__c, Base_Country__c, Property_status__c,
                           (SELECT Id, Property__r.House_No__c, Property__r.Street__c, Property__r.City__c, Property__r.County__c,
                                   Property__r.Postal_Code__c, Property__r.Country__c, Property__r.Base_Country__c,
                                   Property__c, Relation_to_Property__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                                   Property_Address__c, Property__r.NoOfDeposit__c
                            FROM Property_Allocations__r
                            WHERE Relation_to_Property__c IN ('Primary Landlord','Joint Landlord'))
                    FROM Property__c
                    WHERE Property_status__c = :status
                      AND Branch__c = :branchId
                      AND (CreatedById = :UserInfo.getUserId() OR Property_Owner__c = :u.AccountId)
                    LIMIT :noOfProp
                ];
            } else {
                props = [
                    SELECT Id, Property_Owner__c, NoOfDeposit__c, House_No__c, Street__c, City__c, County__c,
                           Postal_Code__c, Country__c, Base_Country__c, Property_status__c,
                           (SELECT Id, Property__r.House_No__c, Property__r.Street__c, Property__r.City__c, Property__r.County__c,
                                   Property__r.Postal_Code__c, Property__r.Country__c, Property__r.Base_Country__c,
                                   Property__c, Relation_to_Property__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                                   Property_Address__c, Property__r.NoOfDeposit__c
                            FROM Property_Allocations__r
                            WHERE Relation_to_Property__c IN ('Primary Landlord','Joint Landlord'))
                    FROM Property__c
                    WHERE Property_status__c = :status
                      AND (CreatedById = :UserInfo.getUserId() OR Property_Owner__c = :u.AccountId)
                    LIMIT :noOfProp
                ];
            }

            for (Property__c p : props) {
                Property_Allocation__c primary;
                Property_Allocation__c joint;
                if (p.Property_Allocations__r != null) {
                    for (Property_Allocation__c a : p.Property_Allocations__r) {
                        if (a.Relation_to_Property__c == REL_PRIMARY) { primary = a; break; }
                        if (a.Relation_to_Property__c == REL_JOINT) { joint = a; }
                    }
                }
                if (primary != null) out.add(primary);
                else if (joint != null) out.add(joint);
            }
            return out;
        } catch (Exception e) {
            System.debug(e.getMessage());
            return null;
        }
    }

    @AuraEnabled
    public static List<Property_Allocation__c> searchpropertylist(String searchtext, String status, String branchId) {
        if (String.isBlank(searchtext)) return new List<Property_Allocation__c>();

        String search = '%' + searchtext + '%';
        User u = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        List<Property__c> props;
        if (String.isNotBlank(branchId)) {
            props = [
                SELECT Id,
                       (SELECT Id, Property__r.House_No__c, Property__r.Street__c, Property__r.City__c,
                               Property__r.County__c, Property__r.Postal_Code__c, Property__r.Country__c,
                               Property__r.Base_Country__c, Property__r.NoOfDeposit__c, Relation_to_Property__c,
                               Property__c, Contact__r.Name, Property_Address__c
                        FROM Property_Allocations__r
                        WHERE Relation_to_Property__c = 'Primary Landlord' AND
                              (Contact__r.Name LIKE :search OR
                               Property__r.House_No__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.County__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Street__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Property_Owner__r.Name LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Postal_Code__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Base_Country__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Town__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.EI_Property_Address_Formula__c LIKE :String.escapeSingleQuotes(search)))
                FROM Property__c
                WHERE Branch__c = :branchId
                  AND Property_status__c = :status
                  AND (Property_Owner__c = :u.AccountId OR CreatedById = :u.Id)
                LIMIT 500
            ];
        } else {
            props = [
                SELECT Id,
                       (SELECT Id, Property__r.House_No__c, Property__r.Street__c, Property__r.City__c,
                               Property__r.County__c, Property__r.Postal_Code__c, Property__r.Country__c,
                               Property__r.Base_Country__c, Property__r.NoOfDeposit__c, Relation_to_Property__c,
                               Property__c, Contact__r.Name, Property_Address__c
                        FROM Property_Allocations__r
                        WHERE Relation_to_Property__c = 'Primary Landlord' AND
                              (Contact__r.Name LIKE :search OR
                               Property__r.House_No__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.County__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Street__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Property_Owner__r.Name LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Postal_Code__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Base_Country__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.Town__c LIKE :String.escapeSingleQuotes(search) OR
                               Property__r.EI_Property_Address_Formula__c LIKE :String.escapeSingleQuotes(search)))
                FROM Property__c
                WHERE Property_status__c = :status
                  AND (Property_Owner__c = :u.AccountId OR CreatedById = :u.Id)
                LIMIT 500
            ];
        }

        List<Property_Allocation__c> out = new List<Property_Allocation__c>();
        for (Property__c p : props) if (p.Property_Allocations__r != null) out.addAll(p.Property_Allocations__r);
        return out;
    }

    @AuraEnabled
    public static Void delproperty(List<Id> dellist) {
        if (dellist == null || dellist.isEmpty()) return null;
        List<Property__c> toDelete = [SELECT Id FROM Property__c WHERE Id IN :dellist];
        if (!toDelete.isEmpty()) delete toDelete;
        return null;
    }

    @AuraEnabled
    public static Map<String, String> landlordRegistrationStatusList() {
        if (cacheAccountRegStatuses != null) return cacheAccountRegStatuses;
        Map<String, String> mapVals = new Map<String, String>();
        Schema.DescribeFieldResult d = Account.LandLord_Registration_Status__pc.getDescribe();
        for (Schema.PicklistEntry p : d.getPicklistValues()) mapVals.put(p.getValue(), p.getLabel());
        cacheAccountRegStatuses = mapVals;
        return mapVals;
    }

    @AuraEnabled
    public static Map<String, String> allocationRegistrationStatusList() {
        if (cacheAllocationRegStatuses != null) return cacheAllocationRegStatuses;
        Map<String, String> mapVals = new Map<String, String>();
        Schema.DescribeFieldResult d = Property_Allocation__c.Landlord_Registrataion_Status__c.getDescribe();
        for (Schema.PicklistEntry p : d.getPicklistValues()) mapVals.put(p.getValue(), p.getLabel());
        cacheAllocationRegStatuses = mapVals;
        return mapVals;
    }

    @AuraEnabled
    public static Contact getLandlordDetails(String landlordId) {
        List<Contact> cons = [
            SELECT Id, Name, Phone, HomePhone, AccountId, Phone_Code__c, Salutation, Number_of_Deposits__c,
                   Number_of_properties__c, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                   Correspondence_Street__c, Correspondence_City__c, Correspondence_State__c, Correspondence_Postal_Code__c,
                   FirstName, LastName, Account_Status__c, Email, AddressFormula__c, Account.Deposit_Protections__c,
                   Account.Number_of_Properties__c, Account.Total_Deposits__c, Person_Reference__c, Landlord_reference__c,
                   Correspondence_Address__c
            FROM Contact
            WHERE Id = :landlordId
            LIMIT 1
        ];
        return cons.isEmpty() ? null : cons[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<Contact> getLandlords() {
        return [
            SELECT Id, Name, Phone, HomePhone, AccountId, Phone_Code__c, Salutation, Number_of_Deposits__c,
                   Number_of_properties__c, MailingStreet, MailingCity, MailingState, MailingPostalCode,
                   Correspondence_Street__c, Correspondence_City__c, Correspondence_State__c, Correspondence_Postal_Code__c,
                   FirstName, LastName, Account_Status__c, Email, AddressFormula__c, Account.Deposit_Protections__c,
                   Account.Number_of_Properties__c, Account_Type__c, Account.Total_Deposits__c
            FROM Contact
            WHERE Account_Type__c = 'Landlord'
            LIMIT 500
        ];
    }

    @AuraEnabled
    public static Map<String, SObject> updateLandlordDetail(String firstName, String lastName, String email, String phoneCode,
                                                            String mobile, String registration, String registrationStatus,
                                                            String contactid, String propAllocationId) {
        Map<String, SObject> ret = new Map<String, SObject>();
        try {
            Contact conCheck = [
                SELECT Id, FirstName, LastName, Email
                FROM Contact
                WHERE Id = :contactid
                LIMIT 1
            ];

            if (conCheck.Email != email) {
                List<User> dupUsers = [
                    SELECT Id, Username, ContactId, Profile.UserLicense.Name, Phone, Email, Name, IsActive
                    FROM User
                    WHERE Profile.UserLicense.Name = :USER_LICENSE_COMMUNITY_LOGIN
                      AND (Email = :email.trim() OR Username = :email.trim())
                    LIMIT 1
                ];
                if (!dupUsers.isEmpty()) {
                    ret.put('Duplicate Email', dupUsers[0]);
                    return ret;
                }
            }

            if (conCheck.FirstName != firstName || conCheck.LastName != lastName || conCheck.Email != email) {
                List<List<SObject>> searchNameList = [
                    FIND :(firstName.trim() + ' ' + lastName.trim()) IN ALL FIELDS
                    RETURNING Contact(Id, Name WHERE Email = :email.trim()
                        AND CreatedById = :UserInfo.getUserId()
                        AND Account.RecordType.Name = 'EWC Landlord')
                ];
                if (!Test.isRunningTest() && searchNameList != null && !searchNameList[0].isEmpty()) {
                    ret.put('Duplicate Name', searchNameList[0][0]);
                    return ret;
                }
            }

            update new Property_Allocation__c(
                Id = propAllocationId,
                Landlord_Registration_Number__c = registration,
                Landlord_Registrataion_Status__c = registrationStatus
            );

            update new Contact(
                Id = contactid,
                FirstName = firstName,
                LastName = lastName,
                Email = email,
                Phone_Code__c = phoneCode,
                Phone = mobile
            );

            updateLandlordDetail(contactid, firstName, lastName, email, phoneCode, mobile);

            ret.put('updated', new User());
            return ret;

        } catch (Exception ex) {
            ret.put(ex.getMessage(), new User());
            return ret;
        }
    }

    @future
    public static void updateLandlordDetail(String contactid, String firstName, String lastName, String email, String phoneCode, String mobile) {
        try {
            List<User> users = [
                SELECT Id, FirstName, LastName, Email, Username, MobilePhone
                FROM User
                WHERE ContactId = :contactid
                LIMIT 1
            ];
            if (!users.isEmpty() || Test.isRunningTest()) {
                if (!users.isEmpty()) {
                    User u = users[0];
                    u.FirstName = firstName;
                    u.LastName = lastName;
                    u.Email = email;
                    u.Username = email;
                    u.MobilePhone = mobile;
                    update u;
                }
            }
        } catch (Exception ex) {
            // swallow to avoid future failure surfacing to UI
        }
    }

    @AuraEnabled
    public static Property__c saveproperty(String receivedParams) {
        Map<String, Object> paramMap = (Map<String, Object>) JSON.deserializeUntyped(receivedParams);

        User u = [SELECT Id, AccountId, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Id rtId = getPropertyRecordTypeId();

        String street = String.valueOf(paramMap.get('Street'));
        String postcode = String.valueOf(paramMap.get('Postcode'));
        String country = String.valueOf(paramMap.get('Country'));
        String baseCountry = String.valueOf(paramMap.get('baseCountry'));
        String county = String.valueOf(paramMap.get('County'));
        String localArea = String.valueOf(paramMap.get('localAuthorityArea'));
        String houseNo = String.valueOf(paramMap.get('houseNo'));
        String town = String.valueOf(paramMap.get('Town'));

        if (String.isBlank(street) || 'undefined'.equalsIgnoreCase(street)) street = '';

        Property__c prop = new Property__c();
        prop.Town__c = town;
        prop.House_No__c = houseNo;
        prop.Property_Owner__c = u.AccountId;
        prop.Street__c = street;
        prop.Postal_Code__c = postcode;
        prop.Country__c = country;
        prop.Base_Country__c = baseCountry;
        prop.County__c = county;
        prop.Local_Authority_Area__c = localArea;
        prop.Property_status__c = STATUS_ACTIVE;
        prop.RecordTypeId = rtId;
        insert prop;

        insert new Property_Allocation__c(
            Property__c = prop.Id,
            Contact__c = u.ContactId,
            Relation_to_Property__c = REL_PRIMARY
        );
        return prop;
    }

    @AuraEnabled
    public static Property__c getPropertyDetails(String propertyId) {
        if (String.isBlank(propertyId)) return null;

        List<Property__c> base = [
            SELECT Id, NoOfDeposit__c, Primary_Landlord__c,
                   (SELECT Id, Property_Address__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                           Contact__r.Email, Contact__r.Phone, Contact__r.Phone_Code__c, Landlord_Registration_Number__c,
                           Relation_to_Property__c
                    FROM Property_Allocations__r),
                   Property_status__c, Local_authority_registration_details__c, House_No__c, City__c, Base_Country__c,
                   Country__c, County__c, District__c, State__c, Street__c, Town__c, Name, Postal_Code__c
            FROM Property__c
            WHERE Id = :propertyId
            LIMIT 1
        ];
        if (base.isEmpty()) return null;

        Property__c prop0 = base[0];

        if (prop0.Property_Allocations__r != null && !prop0.Property_Allocations__r.isEmpty()) {
            prop0.Local_authority_registration_details__c = '';
            update prop0;

            String agg = null;
            for (Property_Allocation__c prc : [
                SELECT Id, Landlord_Registration_Number__c, Property__r.Id
                FROM Property_Allocation__c
                WHERE Property__c = :propertyId
            ]) {
                if (agg == null) agg = prc.Landlord_Registration_Number__c;
                else agg = agg + ', ' + prc.Landlord_Registration_Number__c;
            }

            Property__c toUpdate = new Property__c(Id = propertyId, Local_authority_registration_details__c = agg);
            update toUpdate;

            List<Property__c> refreshed = [
                SELECT Id, NoOfDeposit__c, Primary_Landlord__c,
                       (SELECT Id, Property_Address__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                               Contact__r.Email, Contact__r.Phone, Contact__r.Phone_Code__c, Landlord_Registration_Number__c,
                               Relation_to_Property__c
                        FROM Property_Allocations__r),
                       Property_status__c, Local_authority_registration_details__c, House_No__c, City__c, Base_Country__c,
                       Country__c, County__c, District__c, State__c, Street__c, Town__c, Name, Postal_Code__c
                FROM Property__c
                WHERE Id = :propertyId
                LIMIT 1
            ];
            return refreshed.isEmpty() ? null : refreshed[0];
        }
        return prop0;
    }

    @AuraEnabled
    public static List<Property_Allocation__c> landlordList(String propertyId) {
        return [
            SELECT Id, Relation_to_Property__c, Contact__c, Contact__r.FirstName, Contact__r.LastName,
                   Contact__r.Email, Contact__r.Phone, Contact__r.Landlord_Registration_Number__c,
                   Landlord_Registration_Number__c, Landlord_Registrataion_Status__c,
                   Property__r.House_No__c, Property__r.City__c, Property__r.Country__c, Property__r.County__c,
                   Property__r.District__c, Property__r.State__c, Property__r.Street__c, Property__r.Town__c, Property__r.Name
            FROM Property_Allocation__c
            WHERE Property__c = :propertyId
        ];
    }

    @AuraEnabled
    public static String deletePropertyRecord(String propertyRec, String status) {
        Property__c property = [SELECT Id, Name, Property_status__c FROM Property__c WHERE Id = :propertyRec LIMIT 1];
        try {
            if (status == STATUS_INACTIVE) {
                property.Property_status__c = STATUS_INACTIVE;
                update property;
                return STATUS_INACTIVE;
            } else if (status == STATUS_ACTIVE) {
                property.Property_status__c = STATUS_ACTIVE;
                update property;
                return STATUS_ACTIVE;
            }
            return '';
        } catch (Exception ex) {
            return ex.getMessage();
        }
    }

    @AuraEnabled
    public static List<String> getPhoneCodePiclistValues() {
        try {
            if (cacheContactPhoneCodePicklist != null) return cacheContactPhoneCodePicklist;
            Schema.DescribeFieldResult fieldDescription = Contact.Phone_Code__c.getDescribe();
            List<String> countryCodes = new List<String>();
            for (Schema.PicklistEntry cc : fieldDescription.getPicklistValues()) {
                if (cc.isActive()) countryCodes.add(cc.getValue());
            }
            cacheContactPhoneCodePicklist = countryCodes;
            return countryCodes;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static User getUserDetails() {
        return [
            SELECT Id, Contact.AccountId, User_Type__c, ContactId, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static Map<String, SObject> insertProperties(String street, String houseNo, String city, String postcode, String county, String country, String baseCountry,
                                                        List<Contact> primaryLandlordList, List<Contact> additionalLandlordList, String branchId) {
        Map<String, SObject> returnVal = new Map<String, SObject>();
        try {
            User u = [
                SELECT Id, AccountId, ContactId, Name, User_Type__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            Id ewcRectypeId = getPropertyRecordTypeId();

            List<Contact> primaryLand = (primaryLandlordList != null && !primaryLandlordList.isEmpty())
                ? [SELECT AccountId, LandLord_Registration_Number__c, LandLord_Registration_Status__c FROM Contact WHERE Id IN :primaryLandlordList]
                : new List<Contact>();

            List<Contact> jointLand = (additionalLandlordList != null && !additionalLandlordList.isEmpty())
                ? [SELECT Id, AccountId, LandLord_Registration_Number__c, LandLord_Registration_Status__c FROM Contact WHERE Id IN :additionalLandlordList]
                : new List<Contact>();

            Property__c newProperty = new Property__c();
            if (u.User_Type__c == 'Agent' && !primaryLand.isEmpty()) {
                newProperty.Property_Owner__c = (primaryLand[0].AccountId != null) ? primaryLand[0].AccountId : u.AccountId;
            } else {
                newProperty.Property_Owner__c = u.AccountId;
            }
            newProperty.Property_status__c = STATUS_ACTIVE;
            newProperty.House_No__c = houseNo;
            newProperty.Street__c = street;
            newProperty.Postal_Code__c = postcode;
            newProperty.City__c = city;
            newProperty.County__c = county;
            newProperty.Base_Country__c = baseCountry;
            newProperty.Country__c = 'United Kingdom';
            newProperty.RecordTypeId = ewcRectypeId;
            if (String.isNotBlank(branchId)) newProperty.Branch__c = branchId;

            insert newProperty;
            returnVal.put('propertyCreated', newProperty);

            Id propertyId = newProperty.Id;

            List<Property_Allocation__c> existing = [
                SELECT Id, Contact__c, Relation_to_Property__c
                FROM Property_Allocation__c
                WHERE Property__c = :propertyId
            ];
            Set<Id> existingContactIdList = new Set<Id>();
            for (Property_Allocation__c pa : existing) if (pa.Contact__c != null) existingContactIdList.add(pa.Contact__c);

            List<Property_Allocation__c> toInsert = new List<Property_Allocation__c>();
            if (additionalLandlordList != null) {
                for (Contact con : additionalLandlordList) {
                    if (!existingContactIdList.contains(con.Id)) {
                        toInsert.add(new Property_Allocation__c(Contact__c = con.Id, Property__c = propertyId, Relation_to_Property__c = REL_JOINT));
                    }
                }
            }

            if (primaryLandlordList == null || primaryLandlordList.isEmpty()) {
                toInsert.add(new Property_Allocation__c(Contact__c = u.ContactId, Property__c = propertyId, Relation_to_Property__c = REL_PRIMARY));
            } else if (!existingContactIdList.contains(primaryLandlordList[0].Id)) {
                toInsert.add(new Property_Allocation__c(Contact__c = primaryLandlordList[0].Id, Property__c = propertyId, Relation_to_Property__c = REL_PRIMARY));
            }

            if (!toInsert.isEmpty()) insert toInsert;

            return returnVal;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void updatePropertyAllocation(String editedAllocation, String editedLandlord) {
        Map<String, Object> aMap = (Map<String, Object>) JSON.deserializeUntyped(editedAllocation);
        Map<String, Object> lMap = (Map<String, Object>) JSON.deserializeUntyped(editedLandlord);

        if (aMap != null && aMap.containsKey('Id')) {
            update new Property_Allocation__c(
                Id = (String)aMap.get('Id')
                // original code commented out setting reg fields; preserving behavior
            );
        }

        if (lMap != null && lMap.containsKey('Id')) {
            update new Contact(
                Id = (String)lMap.get('Id'),
                FirstName = (String)lMap.get('firstName'),
                LastName = (String)lMap.get('lastName'),
                Email = (String)lMap.get('email'),
                Phone = (String)lMap.get('telephoneNumber'),
                Phone_Code__c = (String)lMap.get('companyPhoneCode')
            );
        }
    }

    @AuraEnabled
    public static List<Property_Allocation__c> createAllocationForLandlord(String proprtyId, String landlordId) {
        insert new Property_Allocation__c(Property__c = proprtyId, Contact__c = landlordId, Relation_to_Property__c = REL_JOINT);
        return [
            SELECT Id, Property_Address__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                   Contact__r.Email, Contact__r.Phone, Contact__r.Phone_Code__c, Landlord_Registration_Number__c, Relation_to_Property__c
            FROM Property_Allocation__c
            WHERE Property__c = :proprtyId
        ];
    }

    @AuraEnabled
    public static Property__c fetchDupProperties(String houseNo, String street, String townCity, String postCode, String branchId) {
        try {
            String streetVar = '%' + street + '%';
            if (String.isNotBlank(branchId)) {
                List<Property__c> dup = [
                    SELECT Id, Name, House_No__c, Street__c, City__c, Postal_Code__c, CreatedById, Branch__c,
                           (SELECT Id, Name, Property__r.Street__c, Property__r.City__c, Property__r.County__c,
                                   Property__r.Postal_Code__c, Property__r.Country__c, Property__c,
                                   Relation_to_Property__c, Contact__r.Name, Property_Address__c
                            FROM Property_Allocations__r WHERE Relation_to_Property__c = 'Primary Landlord')
                    FROM Property__c
                    WHERE (House_No__c LIKE :houseNo.trim() OR House_No__c LIKE '')
                      AND (Street__c LIKE :streetVar OR Street__c LIKE '')
                      AND City__c = :townCity AND Postal_Code__c = :postCode
                      AND Branch__c = :branchId
                    LIMIT 1
                ];
                return dup.isEmpty() ? null : dup[0];
            } else {
                List<Property__c> dup = [
                    SELECT Id, Name, House_No__c, Street__c, City__c, Postal_Code__c, CreatedById,
                           (SELECT Id, Name, Property__r.Street__c, Property__r.City__c, Property__r.County__c,
                                   Property__r.Postal_Code__c, Property__r.Country__c, Property__c,
                                   Relation_to_Property__c, Contact__r.Name, Property_Address__c
                            FROM Property_Allocations__r WHERE Relation_to_Property__c = 'Primary Landlord')
                    FROM Property__c
                    WHERE House_No__c = :houseNo.trim()
                      AND Street__c LIKE :streetVar
                      AND City__c = :townCity AND Postal_Code__c = :postCode
                      AND CreatedById = :UserInfo.getUserId()
                    LIMIT 1
                ];
                return dup.isEmpty() ? null : dup[0];
            }
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }
}
