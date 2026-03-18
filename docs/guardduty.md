# GuardDuty Cheatsheet

GuardDuty is AWS's managed threat detection service. It sits passively in your account, analyzes log sources, and generates findings when it detects suspicious behavior. No agents, no log routing required — you enable it and it starts working.


## How it works

GuardDuty pulls from three foundational data sources automatically:

| Data Source | What it sees |
|---|---|
| CloudTrail management events | Every AWS API call — who did what, when, from where |
| VPC Flow Logs | Network traffic metadata — source/dest IP, port, protocol, accept/reject |
| DNS query logs | DNS lookups made from EC2 instances in your VPC |

On top of that, **S3 Protection** is enabled in this lab — it adds CloudTrail S3 data events (GetObject, PutObject, DeleteObject) which enables behavioral/heuristic detection on S3 access patterns.

GuardDuty does not read your application logs, doesn't scan files (without optional Malware Protection enabled), and doesn't require you to configure what to look for. It uses AWS threat intelligence feeds, ML models, and anomaly detection to identify threats across all three data sources simultaneously.


## Detection types

GuardDuty findings are named using the pattern `ThreatPurpose:ResourceType/ThreatFamilyName`. Understanding this makes findings much easier to read.

**Rule-based detections** fire when a specific known-bad action occurs:

- `Recon:IAMUser/MaliciousIPCaller` — API calls from a known malicious IP
- `UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B` — console login from an IP address never seen before
- `DefenseEvasion:IAMUser/AnomalousBehavior` — anomalous API calls indicating defense evasion tactics (deleting flow logs, disabling alarms, etc.)

**Behavioral/heuristic detections** fire when activity deviates from an established baseline:

- `Exfiltration:S3/AnomalousBehavior` — S3 reads that don't match normal access patterns
- `UnauthorizedAccess:S3/MaliciousIPCaller.Custom` — S3 access from a known threat actor IP
- `Discovery:S3/MaliciousIPCaller` — bucket enumeration from a suspicious IP
- `CredentialAccess:IAMUser/AnomalousBehavior` — unusual credential usage from an EC2 instance

The behavioral detections are what make GuardDuty interesting for detection engineering — they require a baseline to establish before they fire, so findings may not appear immediately after detonating a TTP for the first time.


## Finding severity

| Severity | Score | What it means |
|---|---|---|
| Critical | 9.0–10.0 | Immediate action required — active compromise indicators |
| High | 7.0–8.9 | Strong indicators of compromise |
| Medium | 4.0–6.9 | Suspicious activity worth investigating |
| Low | 1.0–3.9 | Reconnaissance or low-confidence signals |


## What this lab has enabled

| Data Source | Enabled | Why |
|---|---|---|
| CloudTrail management events | ✅ | Core — detects IAM abuse, CloudTrail evasion, API anomalies |
| VPC Flow Logs + DNS | ✅ | Core — detects C2 communication, port scanning, crypto mining |
| S3 Protection | ✅ | Demonstrates heuristic detection on data plane S3 activity |
| Kubernetes audit logs | ❌ | No EKS in this lab |
| EBS Malware scanning | ❌ | Charges per GB scanned, not relevant here |


## Checking findings

**Console:**
```
https://us-east-1.console.aws.amazon.com/guardduty/
```

**CLI — list all findings:**
```bash
DETECTOR_ID=$(aws guardduty list-detectors --region us-east-1 --query 'DetectorIds[0]' --output text)

aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --region us-east-1 \
  --output table
```

**CLI — get finding details:**
```bash
aws guardduty get-findings \
  --detector-id $DETECTOR_ID \
  --finding-ids <finding-id> \
  --region us-east-1
```

**CLI — filter by severity (HIGH and above):**
```bash
aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --region us-east-1 \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}'
```

**Generate a sample finding to test the pipeline:**
```bash
aws guardduty create-sample-findings \
  --detector-id $DETECTOR_ID \
  --region us-east-1 \
  --finding-types "UnauthorizedAccess:IAMUser/MaliciousIPCaller"
```


## Timing

GuardDuty findings are not instant. Expected delays after detonating a TTP:

| Detection type | Typical delay |
|---|---|
| Rule-based (known bad IP, known bad action) | 5–15 minutes |
| Behavioral/heuristic (anomaly vs baseline) | 15–60 minutes, or longer on first run |
| Baseline establishment (new account/resource) | 7–14 days for full ML model warm-up |

The `finding_publishing_frequency` in our Terraform is set to `FIFTEEN_MINUTES` — this controls how often **subsequent occurrences** of existing findings are re-published to EventBridge. New findings are always sent within approximately 5 minutes of detection regardless of this setting.


## Finding types reference

Full list of all GuardDuty finding types with descriptions:

https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_finding-types-active.html


## TTPs and expected findings

| Stratus TTP | Expected GuardDuty Finding |
|---|---|
| `aws.credential-access.ec2-steal-instance-credentials` | `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS` |
| `aws.defense-evasion.cloudtrail-stop` | `Stealth:IAMUser/CloudTrailLoggingDisabled` |
| `aws.persistence.backdoor-iam-user` | `Persistence:IAMUser/AnomalousBehavior` |
| `aws.exfiltration.s3-backdoor-bucket-policy` | `Policy:S3/BucketAnonymousAccessGranted` |
| `aws.privilege-escalation.iam-create-admin-user` | `PrivilegeEscalation:IAMUser/AnomalousBehavior` |

> [!NOTE]
> Behavioral findings (`AnomalousBehavior`) require GuardDuty to have established a baseline for your account. On a fresh account these may not fire on first detonation — run the TTP multiple times over a few days for reliable results.


## Verify GuardDuty is running

```bash
DETECTOR_ID=$(aws guardduty list-detectors --region us-east-1 --query 'DetectorIds[0]' --output text)

aws guardduty get-detector \
  --detector-id $DETECTOR_ID \
  --region us-east-1 \
  --query '{Status:Status,UpdatedAt:UpdatedAt,S3Logs:DataSources.S3Logs.Status}'
```

Expected output:
```json
{
    "Status": "ENABLED",
    "S3Logs": "ENABLED"
}
```


## Cost after the 30-day free trial

GuardDuty bills based on volume of data processed, not a flat rate.

| Source | Billing unit | Rate (us-east-1) |
|---|---|---|
| CloudTrail management events | per million events | $4.00/M |
| VPC Flow Logs + DNS | per GB | $1.00/GB (first 500 GB) |
| S3 data events (S3 Protection) | per million events | $0.80/M (first 500M) |

For this lab with a single t3.small and light TTP usage, expect **$5–10/month** after the trial. Check your estimated cost in the GuardDuty console under **Usage** before the trial ends.
