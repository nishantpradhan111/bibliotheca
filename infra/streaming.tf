# Defines private network access for the EMR and Kafka streaming path.
resource "aws_security_group" "streaming" {
  name        = "${local.name}-streaming"
  description = "Private Kafka and EMR traffic for analytics"
  vpc_id      = aws_vpc.library.id
}

# Lets EMR workers reach the broker's private EKS NodePort.
resource "aws_vpc_security_group_ingress_rule" "streaming_internal" {
  security_group_id            = aws_eks_cluster.library.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.streaming.id
  ip_protocol                  = "tcp"
  from_port                    = 30094
  to_port                      = 30094
}

# EMR's private-subnet service-access group must be separate from its node group.
resource "aws_security_group" "emr_service_access" {
  name        = "${local.name}-emr-service-access"
  description = "Dedicated private-subnet EMR service access"
  vpc_id      = aws_vpc.library.id
}

# Allows EMR traffic to reach required AWS APIs and Kafka endpoints.
resource "aws_vpc_security_group_egress_rule" "streaming" {
  security_group_id = aws_security_group.streaming.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Allows the dedicated EMR service-access network interface to reach AWS APIs.
resource "aws_vpc_security_group_egress_rule" "emr_service_access" {
  security_group_id = aws_security_group.emr_service_access.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Allows EMR nodes in this group to communicate with one another.
resource "aws_vpc_security_group_ingress_rule" "emr_internal" {
  security_group_id            = aws_security_group.streaming.id
  referenced_security_group_id = aws_security_group.streaming.id
  ip_protocol                  = "-1"
}

# Allows EMR control traffic from its dedicated service-access group.
resource "aws_vpc_security_group_ingress_rule" "emr_control" {
  security_group_id            = aws_security_group.streaming.id
  referenced_security_group_id = aws_security_group.emr_service_access.id
  ip_protocol                  = "tcp"
  from_port                    = 8443
  to_port                      = 8443
}

# Allows the service-access network interface to reach the EMR node group.
resource "aws_vpc_security_group_ingress_rule" "emr_service_access" {
  security_group_id            = aws_security_group.emr_service_access.id
  referenced_security_group_id = aws_security_group.streaming.id
  ip_protocol                  = "tcp"
  from_port                    = 9443
  to_port                      = 9443
}

# Lets the EMR control plane provision and manage its cluster instances.
resource "aws_iam_role" "emr_service" {
  name = "${local.name}-emr-service"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "elasticmapreduce.amazonaws.com" }
    }]
  })
}

# Attaches AWS's managed policy for EMR control-plane operations.
resource "aws_iam_role_policy_attachment" "emr_service" {
  role       = aws_iam_role.emr_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

# Gives the EMR primary the separate identity used by the Flink runtime.
resource "aws_iam_role" "emr_ec2" {
  name = "${local.name}-emr-ec2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attaches the baseline EMR EC2 instance permissions.
resource "aws_iam_role_policy_attachment" "emr_ec2" {
  role       = aws_iam_role.emr_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

# Limits Flink artifacts, checkpoints, and logs to their S3 prefixes.
resource "aws_iam_role_policy" "emr_s3" {
  name = "analytics-artifacts-and-cloudwatch"
  role = aws_iam_role.emr_ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.covers.arn,
        "${aws_s3_bucket.covers.arn}/emr-logs/*",
        "${aws_s3_bucket.covers.arn}/flink/*",
        "${aws_s3_bucket.covers.arn}/bootstrap/emr-cloudwatch-bootstrap.sh"
      ]
      }, {
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.analytics.arn}:log-stream:*"
      }, {
      Effect   = "Allow"
      Action   = ["logs:DescribeLogGroups"]
      Resource = "*"
    }]
  })
}

# Keeps EMR analytics logs searchable in CloudWatch for one week.
resource "aws_cloudwatch_log_group" "analytics" {
  name              = "/digital-library/analytics"
  retention_in_days = 7
}

# Uploads the log bootstrap action from source for reproducible cluster startup.
resource "aws_s3_object" "emr_cloudwatch_bootstrap" {
  bucket       = aws_s3_bucket.covers.id
  key          = "bootstrap/emr-cloudwatch-bootstrap.sh"
  source       = "${path.module}/../scripts/emr-cloudwatch-bootstrap.sh"
  source_hash  = filebase64sha256("${path.module}/../scripts/emr-cloudwatch-bootstrap.sh")
  content_type = "application/x-shellscript"
}

# Creates a single-node EMR cluster that hosts the assignment's Flink job.
resource "aws_emr_cluster" "analytics" {
  count                             = var.enable_analytics_cluster ? 1 : 0
  name                              = "${local.name}-analytics"
  release_label                     = "emr-7.14.0"
  applications                      = ["Flink"]
  service_role                      = aws_iam_role.emr_service.arn
  log_uri                           = "s3://${aws_s3_bucket.covers.bucket}/emr-logs/"
  keep_job_flow_alive_when_no_steps = true
  termination_protection            = var.emr_termination_protection

  ec2_attributes {
    subnet_id                         = aws_subnet.private[var.availability_zones[0]].id
    emr_managed_master_security_group = aws_security_group.streaming.id
    emr_managed_slave_security_group  = aws_security_group.streaming.id
    service_access_security_group     = aws_security_group.emr_service_access.id
    instance_profile                  = aws_iam_instance_profile.emr_ec2.arn
  }

  master_instance_group {
    instance_type  = "m5.xlarge"
    instance_count = 1
  }

  # Single-node demo: primary runs all components, using 4 of the 8-vCPU quota.
  # Changing an existing multi-node cluster requires a reviewed replacement.

  configurations_json = jsonencode([{
    Classification = "flink-conf"
    Properties = {
      "execution.checkpointing.interval" = "30 s"
      "state.checkpoints.dir"            = "s3://${aws_s3_bucket.covers.bucket}/flink/checkpoints/"
    }
  }])

  depends_on = [aws_iam_role_policy_attachment.emr_service, aws_iam_role_policy_attachment.emr_ec2, aws_iam_role_policy.emr_s3, aws_cloudwatch_log_group.analytics, aws_route.private_internet, aws_vpc_security_group_egress_rule.streaming, aws_vpc_security_group_egress_rule.emr_service_access, aws_vpc_security_group_ingress_rule.emr_control, aws_vpc_security_group_ingress_rule.emr_service_access]
}

# Preserves the existing cluster's state address when the optional count is enabled.
moved {
  from = aws_emr_cluster.analytics
  to   = aws_emr_cluster.analytics[0]
}

# Makes the EMR EC2 IAM role available to the cluster's primary instance.
resource "aws_iam_instance_profile" "emr_ec2" {
  name = "${local.name}-emr-ec2"
  role = aws_iam_role.emr_ec2.name
}
