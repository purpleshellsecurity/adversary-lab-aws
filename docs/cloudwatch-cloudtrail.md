# Understanding CloudTrail Logs and CloudWatch Insights


## What is CloudTrail?

CloudTrail is AWS's audit log. Every management-plane API call made in your account — from the console, CLI, SDK, or any AWS service — gets recorded as a CloudTrail event. That includes:

- Someone logging into the console
- A CLI command creating an EC2 instance
- An IAM role assuming another role
- An API call that was denied

> [!NOTE]
> CloudTrail only logs **management events** by default. Data events (S3 object operations like GetObject/PutObject, Lambda invocations) are not captured unless you explicitly enable them on the trail.

CloudTrail answers the question: **who did what, when, from where, and did it succeed?**

In this lab, CloudTrail events flow into a CloudWatch Log Group where you can query them in real time using CloudWatch Logs Insights.


## How to Open CloudWatch Insights

1. Go to **CloudWatch → Logs → Logs Insights** in the AWS console
2. In the log group selector at the top, choose `/detection-lab/cloudtrail/detection-lab`
3. Set a time range in the top right — **Last 1 hour** is a good starting point
4. Paste a query into the editor and click **Run query**

> [!NOTE]
> CloudTrail events take 5–15 minutes to appear in CloudWatch after they occur. If you ran something and don't see it yet, wait a few minutes and try again.


## Anatomy of a CloudTrail Event

Every event is a JSON object. Understanding the structure is the foundation for writing good queries. Here is a real example with every field annotated:

```json
{
  "eventTime": "2024-01-15T22:31:04Z",       // When the API call happened (UTC)
  "eventName": "CreateUser",                  // The API call that was made
  "eventSource": "iam.amazonaws.com",         // Which AWS service received the call
  "awsRegion": "us-east-1",                   // Which region the call was made in
  "sourceIPAddress": "54.210.167.19",         // Where the call came from
  "userAgent": "aws-cli/2.13.0",              // What tool made the call
  "userIdentity": {                           // WHO made the call
    "type": "IAMUser",                        // The identity type (see below)
    "arn": "arn:aws:iam::977237383150:user/alice",
    "accountId": "977237383150",
    "userName": "alice"
  },
  "requestParameters": {                      // What was sent to the API
    "userName": "new-user"                    // Varies by event type
  },
  "responseElements": {                       // What AWS returned
    "user": {
      "userId": "AIDA...",
      "arn": "arn:aws:iam::977237383150:user/new-user",
      "createDate": "2024-01-15T22:31:04Z"
    }
  }
  // errorCode and errorMessage are absent on success.
  // On failure they are populated: "AccessDenied", "NoSuchEntity", etc.
}
```


## Key Fields Reference

### Top-level fields

| Field | What it tells you |
|---|---|
| `eventTime` | When the call happened in UTC |
| `eventName` | The API action — `CreateUser`, `StopLogging`, `AssumeRole`, `PutBucketPolicy`, etc. |
| `eventSource` | Which service — `iam.amazonaws.com`, `s3.amazonaws.com`, `ec2.amazonaws.com` |
| `awsRegion` | Which region the call targeted |
| `sourceIPAddress` | The IP the call came from. If an AWS service made the call on your behalf, this shows the service name e.g. `ec2.amazonaws.com` |
| `userAgent` | The tool — `aws-cli`, `console.amazonaws.com`, `Terraform`, `boto3`, etc. |
| `errorCode` | Absent on success. `AccessDenied`, `UnauthorizedOperation`, `NoSuchEntity`, etc. on failure |
| `errorMessage` | The error detail if the call failed |

### userIdentity fields

This is the most important part of a CloudTrail event — it tells you exactly who made the call.

| Field | What it tells you |
|---|---|
| `userIdentity.type` | The identity type — see table below |
| `userIdentity.arn` | The full ARN of the caller |
| `userIdentity.userName` | For IAM users — their username |
| `userIdentity.accountId` | The AWS account the caller belongs to |
| `userIdentity.sessionContext.sessionIssuer.arn` | For AssumedRole — the original role before it was assumed |
| `userIdentity.sessionContext.sessionIssuer.type` | For AssumedRole — `Role` or `Root` |

### userIdentity.type values

| Type | What it means |
|---|---|
| `IAMUser` | A human or service using long-term IAM user credentials |
| `AssumedRole` | Temporary credentials from `sts:AssumeRole` — includes EC2 instance roles, Lambda execution roles, and cross-account access |
| `Root` | The account root user — should almost never appear |
| `AWSService` | An AWS service acting on your behalf — Auto Scaling, CloudFormation, Config, etc. |
| `FederatedUser` | A user who obtained temporary credentials via `sts:GetFederationToken`. Note: AWS IAM Identity Center (SSO) users appear as `IdentityCenterUser`, not `FederatedUser` |

### requestParameters and responseElements

These fields vary completely depending on which API was called. For example:

- A `CreateUser` event has `requestParameters.userName` and `responseElements.user.arn`
- A `RunInstances` event has `requestParameters.instanceType`, `requestParameters.imageId`, etc.
- A `PutBucketPolicy` event has `requestParameters.bucketName` and `requestParameters.bucketPolicy`

The best way to learn what fields exist for a given event is to look at a real one. Use `fields @timestamp, @message` to see the raw JSON.


## CloudWatch Insights Query Syntax

### Basic structure

Queries are a pipeline — each step filters or transforms the output of the previous step:

```
fields ...       # pick which columns to display
| filter ...     # keep only matching rows
| stats ...      # aggregate and count
| sort ...       # order the results
| limit N        # cap the number of rows returned
```

You do not need every clause. The simplest valid query is just `fields @timestamp, @message`.


### fields

Choose which columns appear in your results. Use dot notation to reach into nested JSON fields:

```
fields @timestamp, eventName, userIdentity.arn, sourceIPAddress
```

`@timestamp` and `@message` are special CloudWatch built-in fields. `@message` contains the full raw JSON of the event.

To see deeply nested fields:

```
fields @timestamp, userIdentity.sessionContext.sessionIssuer.arn, eventName
```


### filter

Narrow down which events appear in results.

**Exact match:**

```
| filter eventName = "CreateUser"
```

**Not equal:**

```
| filter userIdentity.type != "AWSService"
```

**Match any value in a list:**

```
| filter eventName in ["CreateUser", "DeleteUser", "CreateAccessKey"]
```

**Partial string match using regex:**

```
| filter userIdentity.arn like /alice/
```

**Negative partial match:**

```
| filter sourceIPAddress not like /amazonaws.com/
```

**Null check — find failed calls:**

```
| filter errorCode != null
```

**Combining conditions — chain multiple filter lines (they AND together):**

```
| filter eventSource = "iam.amazonaws.com"
| filter errorCode != null
```


### stats

Aggregate events into counts and summaries.

**Count all matching events:**

```
| stats count() as Total
```

**Count grouped by a field:**

```
| stats count() as Total by eventName
```

**Count grouped by multiple fields:**

```
| stats count() as Calls by userIdentity.arn, eventName
```

**Count unique values:**

```
| stats count_distinct(sourceIPAddress) as UniqueIPs by userIdentity.arn
```


### sort and limit

```
| sort @timestamp desc     # newest events first
| sort @timestamp asc      # oldest events first
| sort Total desc          # highest count first
| limit 25                 # show at most 25 rows
```


## Queries to Learn the Log Structure

Start with these before trying anything more specific. They help you understand what is actually in the logs.

```
# See everything — raw JSON, newest first
fields @timestamp, @message
| sort @timestamp desc
| limit 20
```

```
# See the most common fields in a readable table
fields @timestamp, eventName, eventSource, userIdentity.type, userIdentity.arn, sourceIPAddress
| sort @timestamp desc
| limit 50
```

```
# What API calls are happening and how often?
fields eventName
| stats count() as Total by eventName
| sort Total desc
```

```
# Which identities are making calls?
fields userIdentity.type, userIdentity.arn
| stats count() as Total by userIdentity.type, userIdentity.arn
| sort Total desc
```

```
# Which AWS services are being called?
fields eventSource
| stats count() as Total by eventSource
| sort Total desc
```

```
# What tools are making calls? (userAgent)
fields userAgent
| stats count() as Total by userAgent
| sort Total desc
```

```
# Find all failed calls
fields @timestamp, eventName, errorCode, errorMessage, userIdentity.arn, sourceIPAddress
| filter errorCode != null
| sort @timestamp desc
```

```
# Find calls from a specific user
fields @timestamp, eventName, sourceIPAddress, requestParameters
| filter userIdentity.userName = "alice"
| sort @timestamp desc
```

```
# Find all IAM-related activity
fields @timestamp, eventName, userIdentity.arn, requestParameters
| filter eventSource = "iam.amazonaws.com"
| sort @timestamp desc
```

```
# Find all calls from a specific IP address
fields @timestamp, eventName, userIdentity.arn
| filter sourceIPAddress = "54.210.167.19"
| sort @timestamp desc
```

```
# Summarise activity by hour — useful for spotting unusual time patterns
fields @timestamp, eventName
| stats count() as Total by bin(1h)
| sort @timestamp desc
```


## Understanding AssumedRole Events

`AssumedRole` is the identity type you will see most often in this lab because the EC2 instance uses a role, not an IAM user. It is worth understanding how the ARN works.

When a role is assumed, CloudTrail records two different ARNs:

```
userIdentity.arn
  → the session ARN, e.g.:
    arn:aws:sts::977237383150:assumed-role/detection-lab-instance-role/i-0abc123def456
                                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^
                                           the role name               the session name
                                                                       (EC2 instance ID here)
userIdentity.sessionContext.sessionIssuer.arn
  → the original role ARN, e.g.:
    arn:aws:iam::977237383150:role/detection-lab-instance-role
```

To find all calls made by a specific role, filter on the issuer ARN:

```
fields @timestamp, eventName, userIdentity.arn, sourceIPAddress
| filter userIdentity.sessionContext.sessionIssuer.arn like /detection-lab-instance-role/
| sort @timestamp desc
```


## Understanding requestParameters

`requestParameters` is different for every API call. The best way to learn is to look at real events. Here are some common ones:

**IAM — CreateUser:**

```json
"requestParameters": { "userName": "new-user" }
```

**IAM — AttachUserPolicy:**

```json
"requestParameters": {
  "userName": "new-user",
  "policyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

**S3 — PutBucketPolicy:**

```json
"requestParameters": {
  "bucketName": "my-bucket",
  "bucketPolicy": "{...policy JSON...}"
}
```

**EC2 — RunInstances:**

```json
"requestParameters": {
  "instanceType": "t3.nano",
  "imageId": "ami-0abc123"
}
```

To explore `requestParameters` for any event type:

```
# Find a specific event type and see its full requestParameters
fields @timestamp, requestParameters
| filter eventName = "AttachUserPolicy"
| sort @timestamp desc
| limit 5
```


## Common Patterns Worth Knowing

**Calls from the console vs CLI**

Console calls have `userAgent` containing `console.amazonaws.com`. CLI calls show `aws-cli/version`. Programmatic calls from SDKs show `boto3`, `aws-sdk-go`, `Terraform`, etc.

```
fields @timestamp, eventName, userAgent
| filter userAgent like /console/
| sort @timestamp desc
```

**Failed vs successful calls**

`errorCode` is absent on success and populated on failure. The most common error codes:

| errorCode | Meaning |
|---|---|
| `AccessDenied` | The caller does not have permission |
| `UnauthorizedOperation` | Same as AccessDenied, used by some services |
| `NoSuchEntity` | The resource does not exist |
| `InvalidClientTokenId` | The access key ID does not exist in AWS records |
| `ExpiredToken` | Temporary credentials have expired |

**Read vs write calls**

Read calls (Describe, Get, List) rarely indicate a problem on their own. Write calls (Create, Delete, Put, Attach, Stop) are higher signal — they change state.

```
# Find only write/mutating calls
fields @timestamp, eventName, userIdentity.arn
| filter eventName not like /^Describe/
| filter eventName not like /^Get/
| filter eventName not like /^List/
| filter eventName not like /^Head/
| sort @timestamp desc
```
