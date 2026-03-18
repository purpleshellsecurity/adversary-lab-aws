# Logging Verification Cheatsheet

Quick commands to verify each log source is working after deployment.


## 1. CloudTrail → CloudWatch

**What it captures:** Every management-plane API call in your account.

**Verify the trail is running:**

```bash
aws cloudtrail get-trail-status --name detection-lab-trail --region us-east-1 \
  --query '{Logging:IsLogging,LastDelivery:LatestDeliveryTime}'
```

Expected: `"Logging": true`

**Verify CloudTrail can deliver to CloudWatch (check for errors first):**

```bash
aws cloudtrail get-trail-status --name detection-lab-trail --region us-east-1 \
  --query '{Logging:IsLogging,CWError:LatestCloudWatchLogsDeliveryError,CWTime:LatestCloudWatchLogsDeliveryTime}'
```

Expected: `"CWError": null` and eventually a timestamp in `CWTime`.

If `CWError` is `CannotAssumeRole` this is a known IAM propagation issue where CloudTrail tries to assume the IAM role before it has fully propagated. See [hashicorp/terraform-provider-aws#693](https://github.com/hashicorp/terraform-provider-aws/issues/693).

**Fix: run `terraform apply` a second time.** The second apply resets the role policy to what Terraform expects and forces CloudTrail to retry the assume role with the fully propagated role.

```bash
terraform apply
```

Then wait 3-5 minutes and check again. `CWError` should clear and `CWTime` will show a timestamp once events start flowing.

**Verify logs are arriving in CloudWatch:**

```bash
aws logs describe-log-streams \
  --log-group-name /detection-lab/cloudtrail/detection-lab \
  --region us-east-1 \
  --order-by LastEventTime \
  --descending \
  --query 'logStreams[0].{Stream:logStreamName,Last:lastEventTimestamp}'
```

Expected: a stream with a recent timestamp in `Last`.

> [!NOTE]
> `Last` will be null until CloudTrail flushes its first batch which can take 5–15 minutes.

**Trigger a test event and confirm it appears:**

```bash
# Make any API call — this will show up in CloudTrail within ~1 minute
aws sts get-caller-identity --region us-east-1
```

Then query CloudWatch Insights (`/detection-lab/cloudtrail/detection-lab`):

```
fields @timestamp, eventName, userIdentity.arn
| filter eventName = "GetCallerIdentity"
| sort @timestamp desc
| limit 5
```


## 2. VPC Flow Logs → CloudWatch

**What it captures:** Network traffic metadata through the VPC.

**Verify flow logs are enabled on the VPC:**

```bash
aws ec2 describe-flow-logs --region us-east-1 \
  --query 'FlowLogs[?LogGroupName==`/detection-lab/vpc-flow-logs/detection-lab`].{ID:FlowLogId,Status:FlowLogStatus,Destination:LogGroupName}'
```

Expected: `"Status": "ACTIVE"`

**Verify logs are arriving in CloudWatch:**

```bash
aws logs describe-log-streams \
  --log-group-name /detection-lab/vpc-flow-logs/detection-lab \
  --region us-east-1 \
  --order-by LastEventTime \
  --descending \
  --query 'logStreams[0].{Stream:logStreamName,Last:lastEventTimestamp}'
```

Expected: a stream named after an ENI ID with a recent timestamp.

**Trigger a test event:**

```bash
# Any outbound connection from the instance generates flow records
# SSM traffic is enough — just connecting generates flows
```

Then query CloudWatch Insights (`/detection-lab/vpc-flow-logs/detection-lab`):

```
fields @timestamp, srcAddr, dstAddr, dstPort, action
| sort @timestamp desc
| limit 20
```


## 3. Host Logs → CloudWatch (via CloudWatch Agent)

**What it captures:** Auditd (syscalls), syslog, auth log from the EC2 instance.

**Verify the CloudWatch Agent is running on the instance (from SSM session):**

```bash
sudo systemctl status amazon-cloudwatch-agent
```

Expected: `Active: active (running)`

**Check the agent config is loaded:**

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
```

Expected: `"status": "running"`

**Verify auditd is running and has rules:**

```bash
sudo systemctl status auditd
sudo auditctl -l | head -20
```

Expected: auditd active, rules listed.

**Verify logs are arriving in CloudWatch (from your Mac):**

```bash
aws logs describe-log-streams \
  --log-group-name /detection-lab/host/auditd/detection-lab \
  --region us-east-1 \
  --order-by LastEventTime \
  --descending \
  --query 'logStreams[0].{Stream:logStreamName,Last:lastEventTimestamp}'
```

Expected: a stream named after the instance ID with a recent timestamp.

**Trigger a test auditd event (from SSM session):**

```bash
# Run any command — execve syscall is captured by audit rules
ls /tmp
sudo cat /etc/passwd
```

Then query CloudWatch Insights (`/detection-lab/host/auditd/detection-lab`):

```
fields @timestamp, @message
| filter @message like /execve/
| sort @timestamp desc
| limit 20
```


## 4. GuardDuty

**What it captures:** ML-based threat detection across CloudTrail, DNS, and VPC Flow Logs.

**Verify the detector is enabled:**

```bash
DETECTOR_ID=$(aws guardduty list-detectors --region us-east-1 --query 'DetectorIds[0]' --output text)
aws guardduty get-detector --detector-id $DETECTOR_ID --region us-east-1 \
  --query '{Status:Status,UpdatedAt:UpdatedAt}'
```

Expected: `"Status": "ENABLED"`

**Generate a test finding:**

```bash
aws guardduty create-sample-findings \
  --detector-id $DETECTOR_ID \
  --region us-east-1 \
  --finding-types "UnauthorizedAccess:IAMUser/MaliciousIPCaller"
```

**Check for findings:**

```bash
aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --region us-east-1 \
  --query 'FindingIds' \
  --output table
```

Or open the console:

```
https://us-east-1.console.aws.amazon.com/guardduty/
```

**Verify syslog and auth logs are arriving:**

```bash
aws logs describe-log-streams \
  --log-group-name /detection-lab/host/syslog/detection-lab \
  --region us-east-1 \
  --order-by LastEventTime \
  --descending \
  --query 'logStreams[0].{Stream:logStreamName,Last:lastEventTimestamp}'
aws logs describe-log-streams \
  --log-group-name /detection-lab/host/auth/detection-lab \
  --region us-east-1 \
  --order-by LastEventTime \
  --descending \
  --query 'logStreams[0].{Stream:logStreamName,Last:lastEventTimestamp}'
```

> [!NOTE]
> Syslog and auth will return `null` until activity is generated on the instance. Connect via SSM and run:

```bash
logger "test message from detection lab"
sudo su -
sudo cat /etc/passwd
```

Wait 30 seconds then recheck. Per AWS documentation the CloudWatch Agent flushes logs every 5 seconds by default (`force_flush_interval = 5`). If logs still don't appear after 1 minute, check the agent is running on the instance: `sudo systemctl status amazon-cloudwatch-agent`


## 5. Stratus Red Team End-to-End Test

Run a TTP from the VM and confirm it appears in both GuardDuty and CloudWatch.

**From the SSM session on the VM:**

```bash
# Configure AWS credentials (the instance role is used automatically)
aws sts get-caller-identity
# List available TTPs
stratus list --platform aws
# Run the core IMDS credential theft scenario
stratus detonate aws.credential-access.ec2-steal-instance-credentials
# Clean up after
stratus cleanup aws.credential-access.ec2-steal-instance-credentials
```

**Then check CloudWatch Insights** (`/detection-lab/cloudtrail/detection-lab`):

```
fields @timestamp, eventName, userIdentity.arn, sourceIPAddress
| filter userIdentity.type = "AssumedRole"
| filter sourceIPAddress != "169.254.169.254"
| sort @timestamp desc
| limit 20
```

**Then check GuardDuty** — findings appear ~15 minutes after detonation:

```
https://us-east-1.console.aws.amazon.com/guardduty/
```


## Quick Status Summary

Run this from your Mac to check everything at once:

```bash
# CloudTrail logging
echo "=== CloudTrail ===" && \
aws cloudtrail get-trail-status --name detection-lab-trail --region us-east-1 \
  --query 'IsLogging' --output text
# GuardDuty status
echo "=== GuardDuty ===" && \
DETECTOR_ID=$(aws guardduty list-detectors --region us-east-1 --query 'DetectorIds[0]' --output text) && \
aws guardduty get-detector --detector-id $DETECTOR_ID --region us-east-1 \
  --query 'Status' --output text
# CloudWatch log groups exist
echo "=== Log Groups ===" && \
aws logs describe-log-groups --log-group-name-prefix /detection-lab \
  --region us-east-1 \
  --query 'logGroups[*].logGroupName' --output table
# CloudWatch Agent on instance
echo "=== SSM Connect ===" && \
aws ssm describe-instance-information --region us-east-1 \
  --query 'InstanceInformationList[*].{ID:InstanceId,Status:PingStatus}' --output table
```
