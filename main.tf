# Resolve latest Amazon Linux 2023 AMI — no SSM permission needed
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── IAM Role ──────────────

data "aws_iam_policy_document" "instance_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "instance_permissions" {
  statement {
    sid    = "S3AppData"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:ListBucket",
      "s3:DeleteObject", "s3:GetBucketPolicy", "s3:PutBucketPolicy"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SSMParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter", "ssm:GetParameters",
      "ssm:DescribeParameters", "ssm:PutParameter", "ssm:DeleteParameter"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IAMActions"
    effect = "Allow"
    actions = [
      "iam:GetUser", "iam:ListUsers", "iam:ListRoles",
      "iam:CreateUser", "iam:DeleteUser",
      "iam:AttachUserPolicy", "iam:DetachUserPolicy",
      "iam:CreateAccessKey", "iam:DeleteAccessKey",
      "iam:CreateLoginProfile", "iam:DeleteLoginProfile",
      "iam:CreateRole", "iam:DeleteRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PassRole", "iam:PutUserPolicy"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EC2Discovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "STSAndPivot"
    effect  = "Allow"
    actions = ["sts:GetCallerIdentity", "sts:AssumeRole"]
    resources = ["*"]
  }

  statement {
    sid    = "CloudTrailStop"
    effect = "Allow"
    actions = [
      "cloudtrail:StopLogging", "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail", "cloudtrail:GetTrailStatus"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.project_name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent needs this managed policy to ship logs and metrics
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "instance_permissions" {
  name   = "LabInstancePermissions"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance_permissions.json
}

resource "aws_iam_instance_profile" "lab" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance.name
  tags = var.tags
}

# ── CloudWatch Log Groups for host telemetry ──────────────────────────────────

resource "aws_cloudwatch_log_group" "host_auditd" {
  name              = "/detection-lab/host/auditd/${var.project_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "host_syslog" {
  name              = "/detection-lab/host/syslog/${var.project_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "host_auth" {
  name              = "/detection-lab/host/auth/${var.project_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────

resource "aws_instance" "lab" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.lab.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens                 = "required"   # IMDSv2 only
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # ── System updates ────────────────────────────────────────────────────────
    # Skip dnf update to avoid curl-minimal/curl conflict on AL2023
    # curl is pre-installed as curl-minimal, jq and others are available
    # rsyslog is required to create /var/log/messages and /var/log/secure
    # AL2023 uses journald by default and does not create these files
    dnf install -y jq unzip cronie audit rsyslog --skip-broken
    systemctl enable rsyslog --now

    # ── Auto-shutdown via cron ────────────────────────────────────────────────
    systemctl enable crond --now
    echo "0 ${var.auto_shutdown_hour} * * * root /usr/sbin/poweroff" > /etc/cron.d/auto-shutdown

    # ── Auditd — Linux kernel audit framework ─────────────────────────────────
    # Captures process execution, file access, network connections,
    # privilege escalation, and user activity at the syscall level
    systemctl enable auditd --now

    # Load a comprehensive audit ruleset
    cat > /etc/audit/rules.d/detection-lab.rules << 'AUDITEOF'
    # Delete all existing rules
    -D

    # Buffer size — increase if you see "backlog limit exceeded"
    -b 8192

    # Failure mode: 1 = log, 2 = panic
    -f 1

    # ── Process execution ─────────────────────────────────────────────────────
    -a always,exit -F arch=b64 -S execve -k process_execution
    -a always,exit -F arch=b32 -S execve -k process_execution

    # ── Privilege escalation ──────────────────────────────────────────────────
    -a always,exit -F arch=b64 -S setuid -S setgid -k privilege_escalation
    -w /usr/bin/sudo -p x -k sudo_usage
    -w /etc/sudoers -p wa -k sudoers_change
    -w /etc/sudoers.d/ -p wa -k sudoers_change

    # ── User and authentication ───────────────────────────────────────────────
    -w /etc/passwd -p wa -k user_modification
    -w /etc/shadow -p wa -k user_modification
    -w /etc/group -p wa -k group_modification
    -w /var/log/lastlog -p wa -k login_activity
    -w /var/run/utmp -p wa -k session_activity

    # ── Network connections ───────────────────────────────────────────────────
    -a always,exit -F arch=b64 -S connect -k network_connection
    -a always,exit -F arch=b64 -S bind -k network_bind

    # ── File and directory changes ────────────────────────────────────────────
    -w /tmp -p wxa -k tmp_activity
    -w /var/tmp -p wxa -k tmp_activity
    -w /etc/cron.d/ -p wa -k cron_change
    -w /etc/crontab -p wa -k cron_change
    -w /var/spool/cron/ -p wa -k cron_change

    # ── SSH ───────────────────────────────────────────────────────────────────
    -w /etc/ssh/sshd_config -p wa -k sshd_config_change
    -w /root/.ssh/ -p wa -k ssh_key_change

    # ── Kernel modules ────────────────────────────────────────────────────────
    -a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k kernel_module

    # ── Make rules immutable (comment out during development) ─────────────────
    # -e 2
    AUDITEOF

    # Reload audit rules
    augenrules --load

    # ── CloudWatch Agent ──────────────────────────────────────────────────────
    # Install the agent
    dnf install -y amazon-cloudwatch-agent

    # Write the agent config
    # Collects: auditd logs, syslog, auth.log
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
    {
      "agent": {
        "run_as_user": "root"
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/audit/audit.log",
                "log_group_name": "/detection-lab/host/auditd/${var.project_name}",
                "log_stream_name": "{instance_id}",
                "timestamp_format": "%s",
                "encoding": "utf-8"
              },
              {
                "file_path": "/var/log/messages",
                "log_group_name": "/detection-lab/host/syslog/${var.project_name}",
                "log_stream_name": "{instance_id}",
                "timestamp_format": "%b %d %H:%M:%S",
                "encoding": "utf-8"
              },
              {
                "file_path": "/var/log/secure",
                "log_group_name": "/detection-lab/host/auth/${var.project_name}",
                "log_stream_name": "{instance_id}",
                "timestamp_format": "%b %d %H:%M:%S",
                "encoding": "utf-8"
              }
            ]
          }
        }
      }
    }
    CWEOF

    # Start the CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

    systemctl enable amazon-cloudwatch-agent

    # ── Stratus Red Team ──────────────────────────────────────────────────────
    # Pin version to avoid GitHub API rate limits during bootstrap
    STRATUS_VERSION="v2.29.0"
    curl -Lo /tmp/stratus.tar.gz \
      "https://github.com/DataDog/stratus-red-team/releases/download/$${STRATUS_VERSION}/stratus-red-team_Linux_x86_64.tar.gz"
    tar -xzf /tmp/stratus.tar.gz -C /usr/local/bin stratus
    chmod +x /usr/local/bin/stratus
  EOF

  tags = merge(var.tags, {
    Name = "${var.project_name}-linux-vm"
  })
}
