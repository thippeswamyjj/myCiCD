/*
* ---------------------------------------------------------------
* @Name         APPLogger
* @Author       Deepu Chacko & Jayaramappa Thippeswamy
* @Version      v1.0
* @Created Date 01 July 2018
* @Description  Logging all developer logs to chatter as feed post and comments
* ----------------------------------------------------------------
* Disclaimer
* At the time of creating this class, we are employed with Salesforce as Architects. 
* However all code units and approach provided here are purely for experimental purposes and comes with no warranty or support. 
* Matter of fact, all code units and approach provided in this class are purely our own and has nothing to do with our employer. 
* It is assumed that you have the right Salesforce coding skills and will use the ideas presented here as you see fit, in your landscape. 
* The primary purpose of this artifact is just to share the knowledge and our own experience. Nothing more, nothing less. 
* Use this approach at your own risk
*/
public without sharing class APPLogger  {
    // Variable declarations
    private final   static String CONS_LINEBREAK     = '\n';
    private         static String firstMethod       = '';                                   // When the first call to addLog is made, this variable is set. Used in saveLog method
    private         static String prevMethod        = '';                                   // When Class A calls Class B and the control goes back to Class A, the logging should be separate comments even though the key is same i.e. Class A
    private         static Map<String, Integer> keyVsCounter= new Map<String, Integer>();
    private         static List<Map<String, String>> keyVsLogsList = new List<Map<String, String>>();
    private         static Map<String, String> keyVsLogs    = new Map<String, String>();    // All the logs in a method of a class is kept in this map with the key = Class.Method
    private         static Map<String, String> keyVsTrace   = new Map<String, String>();    // Stack trace for each of the method is kept here, map = Class.Method
    private         static Map<String, String> keyVsLimits  = new Map<String, String>();    // Limits captured at the start of each method is kept here, map = Class.Method
    private         static Logger__c loggerSettings         = Logger__c.getInstance();      // All the settings are kept in this Logger hierarchy custom setting

    // The heart of the logger is in this method.
    // Sequence of steps in the logic is as follows:
    //      1. Get class and method name so we know from where this method was called. This will be the key for all the three map variables above
    //      2. Add the passed message string to the map along with the time stamp
    //      3. Add the stack trace corresponding to this class and method
    //      4. Add the limits at the start of this class and method
    public static void addLog(String message){
        // Default action irrespective of whether logging is enabled or not
       

        // Proceed only if the logging is turned on 
        if(!loggerSettings.Enable_Logging__c) return;

        // Get the class and method name and name
        String key = getClassAndMethodName();
        //jammy is here

        // If this is the very first call to logging in this transaction then the expectation is that saveLog will be called in the same calling function
        if(String.isEmpty(firstMethod)) { 
            firstMethod = key;
            prevMethod = firstMethod;
        }  
        
        //Class which calls addLog method is changed. 
        if (prevMethod != key) keyChangeHandler(message,key);
        
        //Same class is calling addLog
        else {
            String currentMessage = keyVsLogs.get(key);
            //first transaction
            if (String.isEmpty(currentMessage)) keyVsLogs.put(key,message + CONS_LINEBREAK);
            
            else{
                //tried putting this directly in map to avoid one varible. Saw some wierd issue. TBD
                currentMessage += message + CONS_LINEBREAK;
                keyVsLogs.put(key,currentMessage);
            }
        }
        // Now we need the stack trace and limits so that we can display at the end of the message
        if(!keyVsTrace.containsKey(key)) keyVsTrace.put(key, getStackTraceTreeView());

        // If limits logging is required and we have not already stored the limits for the class then add it here
        if(loggerSettings.Enable_Limits__c && !keyVsLimits.containsKey(key)) keyVsLimits.put(key, getLimitsConsumed());
    }

    // Save function has an interesting twist
    // It is possible that the saveLog can be called multiple times in a transaction
    // But the method should be intelligent enough to know to commit to chatter only if the transaction that initiated the log is saving it.
    public static void saveLog(){
        // Proceed only if the logging is turned on 
        if(!loggerSettings.Enable_Logging__c) return;

        // Get the class and method name
        List<FeedComment> dmlComments   = new List<FeedComment>();
        String key                      = getClassAndMethodName();

        if(key != firstMethod) return;
        if(prevMethod != key ) keyChangeHandler(null,key);
                
        // Create a dummy feed post so we can simply dump all the logs as comments
        FeedItem feedElement    = new FeedItem();
        feedElement.parentId    = loggerSettings.Chatter_Public_Group_Id__c;
        feedElement.title       = 'APPLogger';
        feedElement.body        = 'APPLogger';
        insert feedElement;

        // Now create all the comments from the logs
        if(keyVsLogsList.size() > 0){
            for(Map<String,String> keyVsLogsMap :keyVsLogsList ){ 
                for(String logKey : keyVsLogsMap.keyset()){
                    FeedComment dmlComment  = new FeedComment();
                    dmlComment.FeedItemId   = feedElement.id;
                    dmlComment.CommentType  = 'textcomment';
                    dmlComment.CommentBody  = keyVsTrace.get(logKey)                                                                            // Stack Trace
                                                + CONS_LINEBREAK.repeat(1) + keyVsLogsMap.get(logKey)                                                  // Log Messages
                                                    + CONS_LINEBREAK.repeat(2) + (loggerSettings.Enable_Limits__c ? keyVsLimits.get(logKey) : '');  // Limits
                    dmlComments.add(dmlComment);
                }
            }    
        }

        if(dmlComments.size() > 0) Database.insert(dmlComments, false);
    }

    // If an exception is thrown then this will allow us to invoke save in a separate future transaction
    @future 
    public static void saveLogsInFuture(){
        saveLog();
    }

    // An interesting idea by Jayaramappa Thippeswamy to use SerializationException class to get the stack trace and hence the calling class and method name
    private static String getClassAndMethodName(){
        String currMethod               = ''; 
        SerializationException  mockException   = new SerializationException ();

        // index starts at 2 because the 0th element is this method and 1st element is addLog and 2nd element is the calling function 
        currMethod = mockException.getStackTraceString().split(CONS_LINEBREAK).get(2);
        // Remove things like Line number and column number
        currMethod = currMethod.substring(0, currMethod.indexOf(':'));
        
        // When Class A calls Class B and the control goes back to Class A, the logging should be separate comments even though the key is same i.e. Class A
        //if(String.isBlank(prevMethod)) prevMethod = currMethod;
       
/*        
        // When it is different i.e. Class A -> Class B -> Class A then send back a unique key
        if(prevMethod != currMethod) {
            counter++;
            currMethod = (currMethod + '_' + counter);
            prevMethod = currMethod;
        }
*/
        return currMethod;
    }

    // Stack trace is easy to understand the context of a log message. This method gets the current stack trace and returns a string showing a tree like structure
    private static String getStackTraceTreeView(){
        String retVal       = '';       // Return value
        String delimiter    = '..';       // Stack trace tree delimiter

        SerializationException  mockException   = new SerializationException ();
        String stackTrace                       = mockException.getStackTraceString();
        List<String> lstStackTrace              = stackTrace.split(CONS_LINEBREAK);

        // This FOR loops creates the stack trace in a nice tree format
        // index starts at 2 because the 0th element is this method and 1st element is addLog and 2nd element is the calling function 
        for(Integer i=2; i<lstStackTrace.size(); i++){
            String traceEntry = lstStackTrace[i];
            // Remove things like Line number and column number
            traceEntry = traceEntry.substring(0, traceEntry.indexOf(':'));
            
            // Since the index starts with 2, am repeating the delimiter i-2 times                                              
            retVal += (delimiter.repeat(i-2) + traceEntry + CONS_LINEBREAK);
        }

        return retVal; 
    }

    // Get limits based on when it is called
    private static String getLimitsConsumed(){
        String retVal       = '';

        List<String> limitsConsumed = new List<String>();

        limitsConsumed.add('AggregateQueries-'  + Limits.getAggregateQueries()) ;
        limitsConsumed.add('Callouts-'          + Limits.getCallouts()) ;
        limitsConsumed.add('CpuTime-'           + Limits.getCpuTime()) ;
        limitsConsumed.add('DatabaseTime-'      + Limits.getDatabaseTime()) ;
        limitsConsumed.add('DmlRows-'           + Limits.getDmlRows()) ;
        limitsConsumed.add('DmlStatements-'     + Limits.getDmlStatements()) ;
        limitsConsumed.add('EmailInvocations-'  + Limits.getEmailInvocations()) ;
        limitsConsumed.add('FutureCalls-'       + Limits.getFutureCalls() ) ;
        limitsConsumed.add('HeapSize-'          + Limits.getHeapSize() ) ;
        limitsConsumed.add('Queries-'           + Limits.getQueries() ) ;
        limitsConsumed.add('QueryLocatorRows-'  + Limits.getQueryLocatorRows() ) ;
        limitsConsumed.add('QueryRows-'         + Limits.getQueryRows() ) ;
        limitsConsumed.add('QueueableJobs-'     + Limits.getQueueableJobs() ) ;
        limitsConsumed.add('Savepoints-'        + Limits.getSavepoints() ) ;
        limitsConsumed.add('SoslQueries-'       + Limits.getSoslQueries() ) ;

        for(String eachLimit: limitsConsumed){
            retVal += (eachLimit  + CONS_LINEBREAK);
        }

        return retVal;
    }
    
    private static void keyChangeHandler(String logs, String key ){
        //invoker changed. add to list
        keyVsLogsList.add(keyVsLogs);
        //initially we used clear. But it removed added elements also. so workaround. TBD. 
        keyVsLogs = new Map<String,String>();
        //change previousinvoker only when invoker changes
        prevMethod = key;
        if (!String.isEmpty(logs)) keyVsLogs.put(key,logs + CONS_LINEBREAK);
    }
}