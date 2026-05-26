# Practical Guide 2: Data Handling & Integration

Concrete patterns for managing Multi-Currency, Large Data Volumes (LDV), and Integration.

## 1. Advanced Currency Management (ACM)

MNCs must report in a corporate currency while transacting locally.

*   **Action:** Enable **Advanced Currency Management (Dated Exchange Rates)**.
*   **Why:** If an Opportunity closed in Jan 2024 (1 USD = 110 JPY), its historical USD value should NOT change when the exchange rate updates in Dec 2024 (1 USD = 150 JPY). ACM locks the rate based on `CloseDate`.
*   **Limitation Warning:** ACM only works on standard Opportunity objects. If you have custom objects needing dated exchange rates, you MUST build custom Apex logic linking to a custom exchange rate table.

## 2. Handling Large Data Volumes (LDV)

If an object exceeds 5-10 million records, standard SOQL queries will timeout.

### 2.1 SOQL Selectivity (The Golden Rule)
A query is "selective" if it uses an indexed field AND returns less than 10% of the first million records (and 5% after).

**Bad Query (Full Table Scan - Will Timeout):**
```sql
// Fails if 'Status__c' is not indexed or returns > 10% of records
List<Order__c> ords = [SELECT Id, Amount__c FROM Order__c WHERE Status__c = 'Processing'];
```

**Good Query (Uses Custom Index + External ID):**
```sql
// Fast: ERP_Order_ID__c is marked as an External ID (which automatically indexes it).
// Returns exactly 1 record.
Order__c ord = [SELECT Id, Amount__c FROM Order__c WHERE ERP_Order_ID__c = 'ERP-992341' LIMIT 1];
```

### 2.2 Skinny Tables
*   **Action:** If you frequently query a high-volume object but hit timeouts due to Salesforce joining the standard and custom field tables under the hood, contact Salesforce Support to create a **Skinny Table**.
*   **Result:** Support creates a single database view containing only the specific standard and custom fields you request, bypassing the JOIN operation.

## 3. Practical Integration Patterns

Stop using batch ETLs for everything. Move to event-driven architectures.

### Pattern 1: Change Data Capture (CDC)
*   **Use Case:** Syncing Salesforce Accounts/Contacts to your Data Warehouse (e.g., Snowflake, Oracle ADW).
*   **How:** Enable CDC for the `Account` object in Setup. Salesforce automatically publishes an event to `/data/ChangeEvents` whenever an Account is created/updated/deleted. Your DWH ingestion tool (e.g., MuleSoft, Kafka) subscribes to this stream.

### Pattern 2: Pub/Sub API (gRPC)
*   **Use Case:** High-volume, bi-directional integration with enterprise systems (e.g., Oracle Fusion ERP).
*   **How:** Define a **Platform Event** (e.g., `Order_Created__e`). Use Apex or Flow to publish this event when an Opportunity is Closed Won. The ERP subscribes via the Pub/Sub API, processes the order, and publishes an `Order_Fulfilled__e` event back to Salesforce.

```java
// Apex: Publishing a Platform Event
Order_Created__e orderEvent = new Order_Created__e(
    Opportunity_ID__c = opp.Id,
    Total_Amount__c = opp.Amount,
    Region__c = 'EMEA'
);
Database.SaveResult sr = EventBus.publish(orderEvent);
```
