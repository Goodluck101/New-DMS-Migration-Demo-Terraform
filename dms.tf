# IAM Role for DMS
resource "aws_iam_role" "dms_role" {
  name = "dms-vpc-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dms_role_policy" {
  role = aws_iam_role.dms_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DescribeNetworkInterfaces",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:PutObjectAcl",
          "dms:Describe*",
          "dms:Create*",
          "dms:Modify*",
          "dms:Delete*"
        ],
        Resource = "*"
      }
    ]
  })
}

# Security Group for DMS
resource "aws_security_group" "dms_sg" {
  name_prefix = "dms-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432  # PostgreSQL
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Change as necessary
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DMS Replication Instance
resource "aws_dms_replication_instance" "dms_instance" {
  replication_instance_id    = "dms-instance-1"
  replication_instance_class = "dms.r5.large"  # Adjust instance class as needed
  allocated_storage          = 100  # Adjust storage as needed
#  engine_version             = "3.4.5"  # Adjust version as needed
  apply_immediately          = true
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  availability_zone          = "eu-west-2a"  # Adjust AZ as needed
  replication_subnet_group_id = aws_dms_replication_subnet_group.dms_subnet_group.id

  vpc_security_group_ids = [aws_security_group.dms_sg.id]
}

# DMS Subnet Group
resource "aws_dms_replication_subnet_group" "dms_subnet_group" {
    replication_subnet_group_description = "Subnet group for DMS replication instance"
  replication_subnet_group_id = "dms-subnet-group"
  subnet_ids                  = [
    aws_subnet.private_subnet1.id,
    aws_subnet.private_subnet2.id
  ]
  tags = {
    Name = "DMS Subnet Group"
  }
}

# DMS Source Endpoint (PostgreSQL)
resource "aws_dms_endpoint" "source_endpoint" {
  endpoint_id   = "source-postgresql-endpoint"
  endpoint_type = "source"
  engine_name   = "postgres"
  username      = "postgres"  # Replace with your source DB username
  password      = "password"  # Replace with your source DB password
  server_name   = "database-1-instance-1.cgfnjlpo1b2r.eu-west-2.rds.amazonaws.com"  # Replace with your source DB host
  port          = 5432
  database_name = "karo"  # Replace with your source DB name
}

# DMS Target Endpoint (RDS PostgreSQL)
resource "aws_dms_endpoint" "target_endpoint" {
  endpoint_id   = "target-rds-endpoint"
  endpoint_type = "target"
  engine_name   = "postgres"
  username      = "postgres"  # Replace with your target DB username
  password      = "password"  # Replace with your target DB password
  server_name   = "database-2-instance-1.cgfnjlpo1b2r.eu-west-2.rds.amazonaws.com"  # Replace with your target DB host
  port          = 5432
  database_name = "karo"  # Replace with your target DB name
}

# DMS Task
resource "aws_dms_replication_task" "dms_task" {
  replication_task_id          = "task-1"
  replication_instance_arn     = aws_dms_replication_instance.dms_instance.replication_instance_arn
  source_endpoint_arn          = aws_dms_endpoint.source_endpoint.endpoint_arn
  target_endpoint_arn          = aws_dms_endpoint.target_endpoint.endpoint_arn
  migration_type               = "full-load"  # Change to "cdc" for ongoing replication
  table_mappings               = <<JSON
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "1",
      "object-locator": {
        "schema-name": "public",
        "table-name": "%"
      },
      "rule-action": "include"
    }
  ]
}
JSON
  replication_task_settings = <<JSON
{
  "TargetMetadata": {
    "TargetSchema": "",
    "SupportLobs": true,
    "FullLobMode": true,
    "LobChunkSize": 64,
    "LimitedSizeLobMode": true,
    "LobMaxSize": 32,
    "InlineLobMaxSize": 0,
    "LoadMaxFileSize": 0,
    "ParallelLoadThreads": 0,
    "ParallelLoadBufferSize": 0,
    "BatchApplyEnabled": false,
    "TaskRecoveryTableEnabled": false
  },
  "FullLoadSettings": {
    "TargetTablePrepMode": "DROP_AND_CREATE",
    "CreatePkAfterFullLoad": false,
    "StopTaskCachedChangesApplied": false,
    "StopTaskCachedChangesNotApplied": false,
    "MaxFullLoadSubTasks": 8,
    "TransactionConsistencyTimeout": 600,
    "CommitRate": 10000
  },
  "Logging": {
    "EnableLogging": true
  },
  "ControlTablesSettings": {
    "ControlSchema": "",
    "HistoryTimeslotInMinutes": 5,
    "HistoryTableEnabled": false,
    "SuspendedTablesTableEnabled": false,
    "StatusTableEnabled": false
  },
  "StreamBufferSettings": {
    "StreamBufferCount": 3,
    "StreamBufferSizeInMB": 8,
    "CtrlStreamBufferSizeInMB": 5
  },
  "ChangeProcessingDdlHandlingPolicy": {
    "HandleSourceTableDropped": true,
    "HandleSourceTableTruncated": true,
    "HandleSourceTableAltered": true
  },
  "ErrorBehavior": {
    "DataErrorPolicy": "LOG_ERROR",
    "DataTruncationErrorPolicy": "LOG_ERROR",
    "DataErrorEscalationPolicy": "SUSPEND_TABLE",
    "DataErrorEscalationCount": 0,
    "TableErrorPolicy": "SUSPEND_TABLE",
    "TableErrorEscalationPolicy": "STOP_TASK",
    "TableErrorEscalationCount": 0,
    "RecoverableErrorCount": -1,
    "RecoverableErrorInterval": 5,
    "RecoverableErrorThrottling": true,
    "RecoverableErrorThrottlingMax": 1800,
    "ApplyErrorDeletePolicy": "IGNORE_RECORD",
    "ApplyErrorInsertPolicy": "LOG_ERROR",
    "ApplyErrorUpdatePolicy": "LOG_ERROR",
    "ApplyErrorEscalationPolicy": "LOG_ERROR",
    "ApplyErrorEscalationCount": 0,
    "FullLoadIgnoreConflicts": true,
    "FailOnTransactionConsistencyBreached": false,
    "FailOnNoTablesCaptured": false
  },
  "ChangeProcessingTuning": {
    "BatchApplyPreserveTransaction": true,
    "BatchApplyTimeoutMin": 1,
    "BatchApplyTimeoutMax": 30,
    "BatchApplyMemoryLimit": 500,
    "BatchSplitSize": 0
  },
  "ValidationSettings": {
    "EnableValidation": true,
    "ValidationMode": "ROW_LEVEL",
    "ThreadCount": 5,
    "PartitionSize": 10000,
    "FailureMaxCount": 10000,
    "RecordFailureDelayInMinutes": 5,
    "RecordSuspendDelayInMinutes": 30,
    "MaxKeyColumnSize": 8096,
    "MaxLobColumnSize": 0,
    "IncludeOpForFullLoad": true,
    "ValidationOnly": false,
    "HandleCollationDiff": false,
    "RecordFailureDelayInSeconds": 0,
    "ValidationTable": "",
    "ValidationFailure": true,
    "ValidationSuspended": true
  }
}
JSON

  tags = {
    Name = "DMS Task 1"
  }
}
