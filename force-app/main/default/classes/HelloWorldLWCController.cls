public with sharing class HelloWorldLWCController {
    
    /**
     * Get Hello World message for LWC
     * @return Map with message data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getHelloWorldMessage() {
        Map<String, Object> response = new Map<String, Object>();
        
        try {
            response.put('message', 'Hello World from Apex Controller!');
            
            response.put('status', 'success');
            response.put('user', UserInfo.getName());
            response.put('orgName', UserInfo.getOrganizationName());
            
        } catch (Exception e) {
            response.put('status', 'error');
            response.put('message', 'Error: ' + e.getMessage());
        }
        
        return response;
    }
    
    /**
     * Get server info for LWC
     * @return Server information
     */
    @AuraEnabled(cacheable=true)
    public static ServerInfo getServerInfo() {
        ServerInfo info = new ServerInfo();
        info.serverTime = Datetime.now();
        info.apiVersion = 59.0;
        info.orgId = UserInfo.getOrganizationId();
        info.userName = UserInfo.getUserName();
        info.isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        
        return info;
    }
    
    /**
     * Wrapper class for server info
     */
    public class ServerInfo {
        @AuraEnabled public Datetime serverTime {get; set;}
        @AuraEnabled public Decimal apiVersion {get; set;}
        @AuraEnabled public String orgId {get; set;}
        @AuraEnabled public String userName {get; set;}
        @AuraEnabled public Boolean isSandbox {get; set;}
    }
}