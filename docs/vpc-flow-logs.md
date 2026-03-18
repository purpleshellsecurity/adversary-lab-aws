# Understanding VPC Flow Logs and CloudWatch Insights


## What are VPC Flow Logs?

VPC Flow Logs capture metadata about every network connection flowing through your VPC. Where CloudTrail tells you who called an AWS API, Flow Logs tell you who connected to what IP address, on which port, how much data moved, and whether it was allowed or blocked.

Flow Logs answer the question: **what network traffic is happening in my VPC, and is it being allowed or blocked?**

### What Flow Logs capture

- Every TCP, UDP, and ICMP connection through the VPC
- Source and destination IP addresses and ports
- Bytes and packets transferred per flow
- Whether traffic was ACCEPT or REJECT by security groups and NACLs
- The network interface (ENI) the traffic passed through

### What Flow Logs do NOT capture

- The actual content of packets — no payload, no HTTP body, no credentials
- Traffic to/from the instance metadata endpoint (169.254.169.254)
- DNS queries to the Amazon-provided VPC resolver (169.254.169.253 / the `.2` address of your VPC CIDR) — use Route 53 Resolver Query Logs for those. DNS queries to custom or third-party resolvers ARE captured.
- ARP, DHCP, and Windows activation traffic

In this lab, Flow Logs are delivered to the CloudWatch Log Group `/detection-lab/vpc-flow-logs/detection-lab` where you can query them in the same tool as CloudTrail.


## How to Open CloudWatch Insights for Flow Logs

1. Go to **CloudWatch → Logs → Logs Insights**
2. Click the log group selector at the top
3. Choose `/detection-lab/vpc-flow-logs/detection-lab`
4. Set a time range — **Last 1 hour** is a good start
5. Paste a query and click **Run query**

> [!TIP]
> You can select multiple log groups at once. Select both the flow log group and the CloudTrail log group to query them together — useful for correlating network activity with API calls.


## Anatomy of a Flow Log Record

Flow log records are **space-separated plain text**, not JSON. Each record is one line representing all traffic between two endpoints within an aggregation window. The default aggregation interval is **10 minutes**; you can optionally set it to 1 minute when creating the flow log. On Nitro-based instances (including t3.small), the interval is always 1 minute or less regardless of this setting.

A raw record looks like this:

```
2 977237383150 eni-0abc123def456 10.0.1.45 54.210.167.19 52341 443 6 18 8760 1705359064 1705359124 ACCEPT OK
```

Breaking that down field by field:

| Position | Field | Example value | What it means |
|---|---|---|---|
| 1 | `version` | `2` | Flow log format version |
| 2 | `account-id` | `977237383150` | AWS account ID |
| 3 | `interface-id` | `eni-0abc123def456` | The ENI the traffic passed through |
| 4 | `srcaddr` | `10.0.1.45` | Source IP address |
| 5 | `dstaddr` | `54.210.167.19` | Destination IP address |
| 6 | `srcport` | `52341` | Source port |
| 7 | `dstport` | `443` | Destination port |
| 8 | `protocol` | `6` | IP protocol number |
| 9 | `packets` | `18` | Total packets in this flow |
| 10 | `bytes` | `8760` | Total bytes in this flow |
| 11 | `start` | `1705359064` | Start of capture window (Unix timestamp) |
| 12 | `end` | `1705359124` | End of capture window (Unix timestamp) |
| 13 | `action` | `ACCEPT` | Whether traffic was allowed or blocked |
| 14 | `log-status` | `OK` | Whether logging succeeded |

### Protocol numbers

Flow logs use IP protocol numbers, not names:

| Number | Protocol | Common use |
|---|---|---|
| `1` | ICMP | Ping, traceroute |
| `6` | TCP | HTTP, HTTPS, SSH, most application traffic |
| `17` | UDP | DNS, NTP, streaming |

### action values

| Value | Meaning |
|---|---|
| `ACCEPT` | Traffic was allowed through by both the security group and NACL |
| `REJECT` | Traffic was blocked by a security group or NACL rule |
| `-` | No action recorded — traffic type not tracked (e.g. DHCP) |

### log-status values

| Value | Meaning |
|---|---|
| `OK` | Log delivered successfully |
| `NODATA` | No traffic during the capture window |
| `SKIPDATA` | Some records dropped due to capacity limits or an internal error |


## How CloudWatch Insights Parses Flow Logs

This is the part that confuses most people. Flow logs are space-separated text, not JSON — so how do you query individual fields?

CloudWatch Insights automatically parses the space-separated fields into named columns based on the flow log format. You reference them by name in your queries, not by position. The field names map as follows:

| In the raw log | In Insights queries | Example value |
|---|---|---|
| Position 3 | `interfaceId` | `eni-0abc123` |
| Position 4 | `srcAddr` | `10.0.1.45` |
| Position 5 | `dstAddr` | `54.210.167.19` |
| Position 6 | `srcPort` | `52341` |
| Position 7 | `dstPort` | `443` |
| Position 8 | `protocol` | `6` |
| Position 9 | `packets` | `18` |
| Position 10 | `bytes` | `8760` |
| Position 13 | `action` | `ACCEPT` |
| Position 14 | `logStatus` | `OK` |

> [!IMPORTANT]
> Field names in flow log Insights queries use camelCase — `srcAddr` not `srcaddr`, `dstPort` not `dstport`. If a query returns no results when you expect some, check your capitalisation.

You also have the standard CloudWatch built-in fields:

| Field | What it contains |
|---|---|
| `@timestamp` | The event timestamp — use this instead of `start`/`end` |
| `@message` | The full raw log line |
| `@logStream` | The log stream name (usually the ENI ID) |


## Query Syntax for Flow Logs

Flow log queries follow the same CloudWatch Insights syntax as CloudTrail. The key difference is the field names and the fact that you're working with numeric data (bytes, packets, ports) rather than JSON strings.

### Filtering by IP address

```
# Exact IP match
| filter srcAddr = "10.0.1.45"
# Partial match — all traffic from the 10.0.x.x range (internal)
| filter srcAddr like /^10\./
# Everything NOT from internal IPs (external traffic)
| filter srcAddr not like /^10\./
```

### Filtering by port

```
# Specific port
| filter dstPort = 443
# Multiple ports
| filter dstPort in [80, 443, 8080, 8443]
# Port range — traffic on high ephemeral ports
| filter dstPort > 1024
```

### Filtering by action

```
| filter action = "ACCEPT"
| filter action = "REJECT"
```

### Filtering by protocol

```
| filter protocol = "6"    # TCP only
| filter protocol = "17"   # UDP only
| filter protocol = "1"    # ICMP only
```

### Aggregating bytes and packets

```
# Total bytes transferred per destination
| stats sum(bytes) as TotalBytes by dstAddr
| sort TotalBytes desc
# Average packet size per flow — small packets can indicate scanning
| stats avg(bytes / packets) as AvgPacketSize by srcAddr
| sort AvgPacketSize asc
```

### Time-based analysis

```
# Traffic volume over time — spot spikes
| stats sum(bytes) as TotalBytes by bin(5m)
| sort @timestamp asc
```


## Start Here — General Exploration

Run these first to build an understanding of what normal traffic looks like before looking for anything specific.

```
# See raw records — understand the format before querying fields
fields @timestamp, @message
| sort @timestamp desc
| limit 20
```

```
# All traffic in a readable table
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol, action, bytes, packets
| sort @timestamp desc
| limit 50
```

```
# What destination ports are being used most?
# This tells you what services the VM is connecting to
fields dstPort
| stats count() as Connections, sum(bytes) as TotalBytes by dstPort
| sort Connections desc
```

```
# Traffic volume breakdown — who is sending the most data?
fields srcAddr, dstAddr
| stats sum(bytes) as TotalBytes, count() as Flows by srcAddr, dstAddr
| sort TotalBytes desc
```

```
# Traffic over time — look for unusual spikes
fields @timestamp, bytes
| stats sum(bytes) as TotalBytes by bin(5m)
| sort @timestamp asc
```

```
# Protocol breakdown
fields protocol
| stats count() as Flows, sum(bytes) as TotalBytes by protocol
| sort TotalBytes desc
```


## Understanding Normal Traffic in This Lab

Before hunting for suspicious activity it helps to know what normal looks like. In this lab you will consistently see:

**Port 443 outbound (HTTPS)** — the VM connects to AWS service endpoints on port 443 for SSM Session Manager, the CloudWatch Agent shipping logs, and Stratus Red Team making API calls. This is the majority of your outbound traffic.

**Port 53 outbound (DNS)** — every hostname lookup generates UDP flows to the VPC DNS resolver at the `.2` address of your VPC CIDR (e.g. `10.0.0.2`).

**Inbound REJECT** — the security group has no inbound rules, so any connection attempt from the internet shows as REJECT. This is expected and correct.

**Short-lived flows** — most flows last under a few minutes and involve small amounts of data. Long-lived flows or unusually large byte counts stand out.


## Accepted vs Rejected Traffic

```
# All rejected traffic
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol
| filter action = "REJECT"
| sort @timestamp desc
```

```
# Count of rejected connections grouped by destination port
# Useful for spotting port scanning
fields dstPort
| filter action = "REJECT"
| stats count() as Attempts by dstPort
| sort Attempts desc
```

```
# Inbound connection attempts to the VM
# Everything should be REJECT since there are no inbound SG rules
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter dstAddr like /^10\./
| sort @timestamp desc
```

```
# REJECT vs ACCEPT ratio per source IP
# A source IP with mostly REJECTs is likely scanning
fields srcAddr, action
| stats count() as Total by srcAddr, action
| sort Total desc
```


## Outbound Traffic Analysis

```
# What external IPs is the VM connecting to?
fields dstAddr
| filter srcAddr like /^10\./
| filter action = "ACCEPT"
| filter dstAddr not like /^10\./
| stats count() as Connections, sum(bytes) as TotalBytes by dstAddr
| sort TotalBytes desc
```

```
# Outbound connections by destination port
# Expected: 443 (HTTPS), 53 (DNS)
# Investigate: anything else with high volume
fields dstPort
| filter srcAddr like /^10\./
| filter action = "ACCEPT"
| stats count() as Connections, sum(bytes) as TotalBytes by dstPort
| sort TotalBytes desc
```

```
# Unusually large outbound transfers
# Single flows over 1MB are worth investigating
fields @timestamp, srcAddr, dstAddr, dstPort, bytes, packets
| filter srcAddr like /^10\./
| filter action = "ACCEPT"
| filter bytes > 1000000
| sort bytes desc
```

```
# Connections to unusual ports — not 443, 53, or 123
fields @timestamp, srcAddr, dstAddr, dstPort, bytes
| filter srcAddr like /^10\./
| filter action = "ACCEPT"
| filter dstPort not in [443, 53, 123, 80]
| sort bytes desc
```


## Protocol Analysis

```
# ICMP traffic — ping, traceroute, or potential tunneling
# ICMP tunneling is a real exfil technique — large ICMP flows are suspicious
fields @timestamp, srcAddr, dstAddr, bytes, packets
| filter protocol = "1"
| sort bytes desc
```

```
# UDP traffic
# Expected: DNS (port 53), NTP (port 123)
# Unexpected: large UDP flows to unknown IPs
fields @timestamp, srcAddr, dstAddr, dstPort, bytes
| filter protocol = "17"
| filter dstPort not in [53, 123]
| sort bytes desc
```

```
# TCP connections that were reset or short-lived
# High packet counts with low byte counts = scanning or connection probing
fields @timestamp, srcAddr, dstAddr, dstPort, packets, bytes
| filter protocol = "6"
| filter packets < 4
| filter action = "ACCEPT"
| sort @timestamp desc
```


## Time-Based Analysis

```
# Traffic volume over time — spot spikes and anomalies
fields @timestamp, bytes
| stats sum(bytes) as TotalBytes, count() as Flows by bin(5m)
| sort @timestamp asc
```

```
# Which hours have the most traffic?
# Helps establish baseline — traffic at 3am when nobody is working stands out
fields @timestamp, bytes
| stats sum(bytes) as TotalBytes by bin(1h)
| sort @timestamp asc
```

```
# Connection count per minute — spike indicates scanning or burst activity
fields @timestamp
| stats count() as Flows by bin(1m)
| sort Flows desc
```


## Correlating Flow Logs with CloudTrail

Network activity and API calls happen together. When you see suspicious network traffic in Flow Logs, the next question is whether it corresponds to API calls in CloudTrail.

**How to do it in Insights:**

In the log group selector, select **both**:
- `/detection-lab/vpc-flow-logs/detection-lab`
- `/detection-lab/cloudtrail/detection-lab`

```
# Combined view — all events from both sources in one timeline
fields @timestamp, @message, @logStream
| sort @timestamp desc
| limit 100
```

**Practical correlation workflow:**

**Step 1** — find a suspicious IP in flow logs:

```
fields @timestamp, srcAddr, dstAddr, dstPort, bytes, action
| filter srcAddr not like /^10\./
| filter action = "ACCEPT"
| sort bytes desc
| limit 20
```

**Step 2** — pivot to CloudTrail to see if that IP made any API calls. Switch to the CloudTrail log group only:

```
fields @timestamp, eventName, userIdentity.arn, sourceIPAddress
| filter sourceIPAddress = "54.210.167.19"
| sort @timestamp desc
```

**Step 3** — if API calls exist, what did they do?

```
fields @timestamp, eventName, requestParameters, errorCode
| filter sourceIPAddress = "54.210.167.19"
| filter errorCode = null
| sort @timestamp desc
```
