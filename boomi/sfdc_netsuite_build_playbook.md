# Build Playbook: Salesforce to NetSuite Real-Time Integration

Based on the [Real-Time Integration Architecture](./sfdc_netsuite_realtime_architecture.md), this document details the step-by-step execution plan to build the integration pipeline within the Dell Boomi AtomSphere canvas.

---

## Phase 1: Prerequisites & Platform Setup

### 1.1 Connection Configurations
Before building processes, establish your global reusable connections.
*   **NetSuite Connection:** 
    *   Navigate to *Connections*. Create a new NetSuite Connection.
    *   Enter the NetSuite Account ID.
    *   Authentication Type: Select **Token-Based Authentication (TBA)**.
    *   Input your Consumer Key, Consumer Secret, Token ID, and Token Secret.
*   **Atom Queue Setup:**
    *   In the Boomi Platform, navigate to *Manage -> Atom Management*.
    *   Select the target environment (Atom Cloud) and open *Queue Management*.
    *   Create a new queue named `SFDC_ClosedWon_Queue` (Type: Point-to-Point).

### 1.2 Shared Web Server Configuration
To allow Salesforce to push payloads securely:
*   Navigate to *Atom Management -> Shared Web Server*.
*   **API Type:** Advanced.
*   **Authentication Type:** API Token.
*   Generate an API token for the "Salesforce_User" identity and save it securely for the Salesforce Admin.

---

## Phase 2: Build the Listener Process (API -> Queue)

This process acts as the "front door". Its sole job is to receive the HTTP POST from Salesforce, acknowledge it quickly, and dump the payload into the Atom Queue for decoupled processing.

### 2.1 The Start Shape (Web Services Server)
1.  Drag a **Start Shape** onto the canvas. Type: `Web Services Server`.
2.  Action: `Listen`.
3.  Operation: Create a new operation. 
    *   Expected Input Type: JSON (Configure with a sample SFDC Account/Order JSON profile).
    *   Response Output Type: None (Boomi automatically returns a `200 OK` on success).

### 2.2 Route to Queue
1.  Drag a **Connector Shape** and attach it to the Start Shape.
2.  Connection: Select `Atom Queue`.
3.  Action: `Send`.
4.  Operation: Select the `SFDC_ClosedWon_Queue` created in Phase 1.

### 2.3 Stop Shape
1.  Add a **Stop Shape** after the Queue shape. The decoupled listener process is complete.

---

## Phase 3: Build the Main Integration Process (Queue -> NetSuite)

This is the heavy lifter. It dequeues messages, transforms data, and executes NetSuite API calls.

### 3.1 Start Shape (Atom Queue Listener)
1.  Drag a **Start Shape**. Type: `Atom Queue`.
2.  Action: `Listen`.
3.  Queue: Select `SFDC_ClosedWon_Queue`.

### 3.2 Data Quality Validation (Business Rule Shape)
1.  Drag a **Business Rules Shape**.
2.  Map the incoming JSON profile to the rule engine.
3.  **Add Rules:**
    *   *Rule 1 (Data Type Check):* Ensure `Amount` is purely numeric.
    *   *Rule 2 (Completeness):* Ensure `BillingState` and `BillingCountry` are not null.
4.  **Accepted Path:** Continues to the integration logic.
5.  **Rejected Path:** Routes to an **Exception Shape** which sends the raw payload to the Dead Letter Queue (DLQ) for engineering review.

### 3.3 Idempotency Check (Does Order Exist?)
1.  Add a **Connector Shape** -> NetSuite.
2.  Action: `Query`. Object: `SalesOrder`.
3.  Operation: Filter by `TranId` equals the incoming SFDC `OrderNumber`.
4.  Add a **Decision Shape**: Checks if a record was returned from the query.
    *   **True (Exists):** Route to a **Stop Shape** to prevent duplicate order creation.
    *   **False (New):** Continue to Step 3.4.

### 3.4 Upsert the Customer Record
1.  Wrap the next steps in a **Try/Catch Shape** (Retry count: 3) to handle NetSuite API blips.
2.  Add a **Map Shape** (SFDC JSON to NetSuite Customer XML).
    *   Map `Account.Id` -> `ExternalId`.
    *   Map `Account.Name` -> `CompanyName`.
3.  Add a **Connector Shape** -> NetSuite. Action: `Upsert`. Object: `Customer`.
4.  Add a **Set Properties Shape** immediately after the NetSuite connector.
    *   Capture the NetSuite `InternalId` returned in the XML response.
    *   Save it as a **Dynamic Document Property** named `DDP_NS_Customer_InternalId`.

### 3.5 Create the Sales Order
1.  Add a **Map Shape** (SFDC JSON to NetSuite SalesOrder XML).
    *   Map `OrderNumber` -> `TranId`.
    *   Map the `DDP_NS_Customer_InternalId` property -> `Entity` (This links the order to the customer).
    *   Map Line Items (`ProductCode` -> `Item`, `Quantity` -> `Quantity`).
2.  Add a **Connector Shape** -> NetSuite. Action: `Create`. Object: `SalesOrder`.
3.  Add a **Stop Shape** (Successful termination).

### 3.6 Exception Handling (Catch Path)
1.  From the **Try/Catch Shape's** *Catch Path*, add an **Exception Shape**.
2.  Configure the Exception Shape to capture the `Base Exception Message` document property.
3.  Route this output to the DLQ (e.g., an S3 bucket or log file) so failed payloads and their exact error messages are preserved.

---

## Phase 4: Deployment & Activation

1.  **Deploy Processes:** Deploy both the Listener Process and the Main Integration Process to your Boomi Atom Cloud.
2.  **Activate Listener:** Go to Atom Management -> Shared Web Server and copy the *Base URL*. The endpoint will be `https://[Base_URL]/ws/simple/execute...`
3.  **Salesforce Handoff:** Provide the URL and the API Token (from Step 1.2) to the Salesforce Admin to configure the Outbound Message or Salesforce Flow Webhook.
4.  **End-to-End Testing:** Trigger a mock "Closed Won" opportunity in the Salesforce sandbox and monitor the Boomi Process Reporting console to verify queue dequeuing and NetSuite record creation.
