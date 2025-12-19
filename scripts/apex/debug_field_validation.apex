// Debug script to trace field validation
Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
Schema.SObjectType sObjType = globalDescribe.get('case');
System.debug('sObjType: ' + sObjType);

Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

// Check Status field
Schema.SObjectField statusField = fieldMap.get('status');
System.debug('Status field: ' + statusField);
if (statusField != null) {
    System.debug('Status accessible: ' + statusField.getDescribe().isAccessible());
} else {
    System.debug('Status field is null');
}

// Check Priority field
Schema.SObjectField priorityField = fieldMap.get('priority');
System.debug('Priority field: ' + priorityField);
if (priorityField != null) {
    System.debug('Priority accessible: ' + priorityField.getDescribe().isAccessible());
} else {
    System.debug('Priority field is null');
}

// Try extracting from condition
String condition = 'Status != \'Closed\' AND Priority = \'High\'';
// Remove string literals
String conditionWithoutStrings = condition.replaceAll('\'[^\']*\'', ' ');
System.debug('Condition without strings: [' + conditionWithoutStrings + ']');

// Tokenize
String tokenized = conditionWithoutStrings.replaceAll('[(),:]', ' ');
tokenized = tokenized.replaceAll('!=|<>|<=|>=|=|<|>', ' ');
System.debug('Tokenized: [' + tokenized + ']');

// Manual split
List<String> rawTokens = new List<String>();
String current = '';
for (Integer i = 0; i < tokenized.length(); i++) {
    String c = tokenized.substring(i, i+1);
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        if (current.length() > 0) {
            rawTokens.add(current);
            current = '';
        }
    } else {
        current += c;
    }
}
if (current.length() > 0) {
    rawTokens.add(current);
}
System.debug('Raw tokens: ' + rawTokens);

// Check each token
Set<String> operators = new Set<String>{
    '=', '!=', '<>', '<', '>', '<=', '>=', 'LIKE', 'IN', 'NOT', 'AND', 'OR',
    'NULL', 'TRUE', 'FALSE'
};

for (String token : rawTokens) {
    Boolean isOperator = operators.contains(token.toUpperCase());
    Boolean isNumeric = token.isNumeric();
    Schema.SObjectField field = fieldMap.get(token.toLowerCase());
    Boolean isField = field != null;
    Boolean isAccessible = isField ? field.getDescribe().isAccessible() : false;

    System.debug('Token: [' + token + '] -> isOperator=' + isOperator + ', isNumeric=' + isNumeric + ', isField=' + isField + ', isAccessible=' + isAccessible);
}
