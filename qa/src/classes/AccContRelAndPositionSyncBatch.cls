global class AccContRelAndPositionSyncBatch implements Database.Batchable<sObject> {

//    Database.executeBatch(new AccContRelAndPositionSyncBatch(), 200);
//test sync
    private static final String SEPARATOR = ';';

    global AccContRelAndPositionSyncBatch() {}

    global Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id
            ,   agileed__Account__c
            ,   agileed__Contact__c
            ,   agileed__Job__r.Name
            ,   agileed__Active__c
            FROM agileed__Position__c
        ]);
    }

    global void execute(Database.BatchableContext BC, List<agileed__Position__c> positions) {
        System.debug('\n\n positions.size() => ' + positions.size() + '\n');
        System.debug('\n\n positions => ' + positions + '\n');

        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (agileed__Position__c position : positions) {
            accountIds.add(position.agileed__Account__c);
            contactIds.add(position.agileed__Contact__c);
        }

        System.debug('\n\n accountIds => ' + accountIds + '\n');
        System.debug('\n\n contactIds => ' + contactIds + '\n');

        Map<Id, Map<Id, AccountContactRelation>> relationByContactIdByAccountId = this.getRelationByContactIdByAccountId(accountIds, contactIds);
        System.debug('\n\n relationByContactIdByAccountId.size() => ' + relationByContactIdByAccountId.size() + '\n');
        System.debug('\n\n relationByContactIdByAccountId => ' + relationByContactIdByAccountId + '\n');

        Map<String, AccountContactRelation> relationsByIdToUpsert = new Map<String, AccountContactRelation>();
        for (agileed__Position__c position : positions) {
            if (relationByContactIdByAccountId.containsKey(position.agileed__Account__c)) {
                Map<Id, AccountContactRelation> relationsByContactId = relationByContactIdByAccountId.get(position.agileed__Account__c);

                if (relationsByContactId.containsKey(position.agileed__Contact__c)) {
                    AccountContactRelation existingRelation = relationsByContactId.get(position.agileed__Contact__c);

                    AccountContactRelation relationInWork = null;
                    if (relationsByIdToUpsert.containsKey(existingRelation.Id)) {
                        relationInWork = relationsByIdToUpsert.get(existingRelation.Id);
                    } else {
                        relationInWork = existingRelation;
                    }

                    relationInWork = this.setupRelationObject(position, relationInWork);

                    System.debug('\n\n relationInWork => ' + relationInWork + '\n');
                    relationsByIdToUpsert.put(relationInWork.Id, relationInWork);
                } else if (relationsByIdToUpsert.containsKey(position.agileed__Account__c + '' + position.agileed__Contact__c)){
                    System.debug('\n\n second if \n');
                    AccountContactRelation relationInWork = relationsByIdToUpsert.get(position.agileed__Account__c + '' + position.agileed__Contact__c);
                    relationInWork = this.setupRelationObject(position, relationInWork);
                    System.debug('\n\n relationInWork => ' + relationInWork + '\n');
                    relationsByIdToUpsert.put(relationInWork.AccountId + '' + relationInWork.ContactId, relationInWork);
                } else {
                    AccountContactRelation relation = this.makeRelation(position);
                    System.debug('\n\n new relation => ' + relation + '\n');
                    relationsByIdToUpsert.put(relation.AccountId + '' + relation.ContactId, relation);
                    System.debug('\n\n relationsByIdToUpsert => ' + relationsByIdToUpsert + '\n');
                }
            } else if (relationsByIdToUpsert.containsKey(position.agileed__Account__c + '' + position.agileed__Contact__c)){
                System.debug('\n\n second second if \n');
                AccountContactRelation relationInWork = relationsByIdToUpsert.get(position.agileed__Account__c + '' + position.agileed__Contact__c);
                relationInWork = this.setupRelationObject(position, relationInWork);
                System.debug('\n\n relationInWork => ' + relationInWork + '\n');
                relationsByIdToUpsert.put(relationInWork.AccountId + '' + relationInWork.ContactId, relationInWork);
            } else {
                AccountContactRelation relation = this.makeRelation(position);
                System.debug('\n\n new new relation for contact => ' + relation + '\n');
                relationsByIdToUpsert.put(relation.AccountId + '' + relation.ContactId, relation);
                System.debug('\n\n relationsByIdToUpsert => ' + relationsByIdToUpsert + '\n');
            }
        }

        System.debug('\n\n relationsByIdToUpsert.size() => ' + relationsByIdToUpsert.size() + '\n');
        System.debug('\n\n relationsByIdToUpsert => ' + relationsByIdToUpsert + '\n');

        upsert relationsByIdToUpsert.values();

        delete positions;
    }

    global void finish(Database.BatchableContext BC) {
        System.debug('\n\n The AccContRelAndPositionSyncBatch has been finished! \n');
    }


    /* ========================================================= */
    /*     High Level Helpers
    /* ========================================================= */
    private Map<Id, Map<Id, AccountContactRelation>> getRelationByContactIdByAccountId(Set<Id> accountIds, Set<Id> contactIds) {
        List<AccountContactRelation> relations =  this.getAccountContactRelationsWhereAccountIdsAndContactIds(accountIds, contactIds);
        System.debug('\n\n relations => ' + relations + '\n');

        Map<Id, Map<Id, AccountContactRelation>> relationByContactIdByAccountId = new Map<Id, Map<Id, AccountContactRelation>>();

        if (relations.isEmpty()) {
            return relationByContactIdByAccountId;
        }

        for (AccountContactRelation relation : relations) {
            if (relationByContactIdByAccountId.containsKey(relation.AccountId)) {
                if ( ! relationByContactIdByAccountId.get(relation.AccountId).containsKey(relation.ContactId)) {
                    relationByContactIdByAccountId.get(relation.AccountId).put(relation.ContactId, relation);
                }
            } else {
                relationByContactIdByAccountId.put(relation.AccountId, new Map<Id, AccountContactRelation> {
                    relation.ContactId => relation
                });
            }
        }

        return relationByContactIdByAccountId;
    }


    /* ========================================================= */
    /*     Low Level Helpers
    /* ========================================================= */
    private AccountContactRelation makeRelation(agileed__Position__c position) {
        AccountContactRelation relation = new AccountContactRelation(
            AccountId = position.agileed__Account__c
        ,   ContactId = position.agileed__Contact__c
        );
        return this.setupRelationObject(position, relation);
    }

    private AccountContactRelation setupRelationObject(agileed__Position__c position, AccountContactRelation relation) {
        String jobName = position.agileed__Job__r.Name;
        if (position.agileed__Active__c == true) {
            if (relation.ActiveAgileTitles__c == null) {
                relation.ActiveAgileTitles__c = jobName;
            } else if ( ! relation.ActiveAgileTitles__c.containsIgnoreCase(jobName)) {
                relation.ActiveAgileTitles__c = relation.ActiveAgileTitles__c + SEPARATOR + jobName;
            }
        } else {
            if (relation.InactiveAgileTitles__c == null) {
                relation.InactiveAgileTitles__c = jobName;
            } else if ( ! relation.InactiveAgileTitles__c.containsIgnoreCase(jobName)) {
                relation.InactiveAgileTitles__c = relation.InactiveAgileTitles__c + SEPARATOR + jobName;
            }
        }

        relation.IsAgile__c = true;

        return relation;
    }


    /* ========================================================= */
    /*     SOQL Helpers
    /* ========================================================= */
    private List<AccountContactRelation> getAccountContactRelationsWhereAccountIdsAndContactIds(Set<Id> accIds, Set<Id> conIds) {
        return [
            SELECT Id
            ,   IsActive
            ,   AccountId
            ,   ContactId
            ,   IsAgile__c
            ,   ActiveAgileTitles__c
            ,   InactiveAgileTitles__c
            FROM AccountContactRelation
            WHERE AccountId IN :accIds
                AND ContactId IN :conIds
        ];
    }

}

/*  NSL-342: Account Contact Flow: Batch to convert Positions to Account Contacts Relations
    ====================================================================================================================
    1. For each active Position (first):
        1.1. Find all the Account Contact Relations with the same Account & Contact & Agile Title.
            If found:
            a) Check the AccountContactRelation.IsActive checkbox if not yet checked.
            b) Check the AccountContactRelation.IsAgile Checkbox if not check yet.
        1.2 If none were found, find the all the Account Contact Relations with the same Account & Contact
        & Empty Agile Title.
            If found:
            a) Fill in the Agile Title from the Position.Job.Name.
            b) Check the AccountContactRelation.IsActive checkbox if not checked yet.
            c) Check the AccountContactRelation.IsAgile Checkbox if not checked yet.
        1.3 If none were found:
            a) Create a new Account Contact Relation and fill in the Account, Contact, Agile Title.
            b) Check the AccountContactRelation.IsAgile checkbox.

    2. For each inactive position (second):
        1.1 Find all the Account Contact Relations with the same Account & Contact & Agile Title.
            If found:
            a) Check our uncheck the AccountContactRelation.IsActive checkbox if necessary based on Agile info.
        1.2 If none were found:
            a) Create a new AccountContactRelation and fill in the Account, Contact, Agile Title.
            b) Check the AccountContactRelation.IsAgile checkbox.
    ====================================================================================================================
 */