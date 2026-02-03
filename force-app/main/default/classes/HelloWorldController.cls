public with sharing class HelloWorldController {
    
    /**
     * Simple method that returns Hello World message
     * @return String - Hello World message
     */
    public static String getHelloMessage() {
        return 'Hello World from Apex!';
    }
    
    /**
     * Method with parameter
     * @param name - User's name
     * @return Personalized greeting
     */
    public static String getPersonalizedGreeting(String name) {
        if (String.isBlank(name)) {
            name = 'Guest';
        }
        return 'Hello ' + name + '! Welcome to Salesforce Apex.';
    }
    
    /**
     * Method to get current date and time
     * @return Current datetime as string
     */
    public static String getCurrentDateTime() {
        Datetime now = Datetime.now();
        return 'Current Date & Time: ' + now.format('dd-MM-yyyy HH:mm:ss');
    }
}