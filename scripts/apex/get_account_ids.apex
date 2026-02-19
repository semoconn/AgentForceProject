// Get account IDs for CSV generation
for (Account a : [SELECT Id, Name FROM Account ORDER BY Name]) {
    System.debug(a.Id + ' | ' + a.Name);
}
