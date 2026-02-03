public with sharing class AccountController {

    @AuraEnabled
    public static List<Account> fetchAccounts(Integer limitSize) {
        if (limitSize == null || limitSize <= 0) {
            return new List<Account>();
        }
        if (limitSize > 5) {
            limitSize = 5;
        }

        return [
            SELECT Id, Name, Industry
            FROM Account
            LIMIT :limitSize
        ];
    }
}
