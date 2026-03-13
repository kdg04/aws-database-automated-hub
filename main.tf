terraform {
  required_version = ">= 1.0"       
  backend "s3" {
    bucket = "terraform-state-bucket-kdg-2026" 
    key    = "state/terraform.tfstate"
    region = "ap-south-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" 
    }
  }
}

# 1. Specify the Provider
provider "aws" {                           # The AWS plugin that Terraform downloads to translate the .tf code into API calls that AWS understands.
  region = "ap-south-1" 
}

# 2. Create the RDS MySQL Instance
resource "aws_db_instance" "mysql_source" {            # resource "Type" "logical name (not seen in AWS console)" logical name is used for
                                                       # another resource block to refer it in this  .tf file. It is generally used to 
                                                       # access the Id as aws_db_instance.mysql_source.id
  identifier = "mysql-source-db"
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t4g.micro"    
  db_name              = "e_commerce_db"
  username             = "root"
  password             = "fiascokd_04"                 # In real life, use a Secret Manager!
  vpc_security_group_ids = [aws_security_group.allow_mysql.id]
  skip_final_snapshot  = true
  publicly_accessible  = true
}

# 3. Create the DynamoDB Target Table
resource "aws_dynamodb_table" "ecommerce_nosql" {
  name           = "e_orders_nosql"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PK"
  range_key      = "SK"

  attribute { 
    name = "PK" 
    type = "S" 
    }
  attribute { 
    name = "SK" 
    type = "S" 
    }
}

# 4.a Look up your Default VPC
data "aws_vpc" "default" {       # Data are already existing resources created manually, by terraform, or by another team
  default = true
}

# 4.b Look up the subnets inside that VPC
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 4.c Use them in your Subnet Group
resource "aws_dms_replication_subnet_group" "dms_group" {      # Resources are owned and managed (create/update/delete) by Terraform
  replication_subnet_group_id          = "dms-lab-subnet-group"
  replication_subnet_group_description = "DMS Subnets"
  
  # This dynamically pulls all subnet IDs found above
  subnet_ids = data.aws_subnets.all.ids
}

# 5.a THE PLUMBER: Required for the DMS engine to exist in the VPC
resource "aws_iam_role" "dms_vpc_role_v2" {
  name = "dms-vpc-role-v2"              # <== this name is what shows in the console
  assume_role_policy = jsonencode({     # Trust policy, who is allowed to bear the role
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "dms.amazonaws.com" }       # role bearer
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc_attach" {
  role       = aws_iam_role.dms_vpc_role_v2.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# 2. THE CloudWatch Role: Required for logging
resource "aws_iam_role" "dms_cw_role_v2" {
  name = "dms-cloudwatch-logs-role-v2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_cw_attach" {
  role       = aws_iam_role.dms_cw_role_v2.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

resource "aws_iam_role" "dms_dynamodb_role_v2" {
  name = "dms-dynamodb-access-role-v2"
  assume_role_policy = jsonencode ({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "dms.amazonaws.com"}
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_dynamodb_attach" {
  role = aws_iam_role.dms_dynamodb_role_v2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role" "dms_ec2_role_v2" {
  name = "dms-ec2-access-role-v2"
  assume_role_policy = jsonencode ({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "dms.amazonaws.com"}
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_ec2_attach" {
  role = aws_iam_role.dms_ec2_role_v2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_security_group" "allow_mysql" {
  name          = "allow_mysql_traffic"
  description   = "Allow inbound MySQL traffic"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]            # Caution: Opens to the whole world for this lab
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"                     # any protocol tcp, https, http ...
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "mysql-source-endpoint"
  endpoint_type = "source"
  engine_name   = "mysql"
  username      = "root"
  password      = "fiascokd_04"                             # Matches your RDS password
  server_name   = aws_db_instance.mysql_source.address      # Links to your RDS
  port          = 3306
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "dynamodb-target-endpoint"
  endpoint_type = "target"
  engine_name   = "dynamodb"
  service_access_role = aws_iam_role.dms_dynamodb_role_v2.arn
}

resource "aws_dms_replication_instance" "my_dms_instance" {
  replication_instance_id    = "migration-engine-lab"
  replication_instance_class = "dms.t3.small" 
  allocated_storage          = 10
  apply_immediately          = true
  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc_attach,
    aws_iam_role_policy_attachment.dms_cw_attach
  ]
}

resource "aws_dms_replication_task" "migration_task" {
  replication_task_id      = "mysql-to-dynamo-automated"
  migration_type           = "full-load"                    # This means "copy everything once"
  
  # LINKING: We use the IDs from the resources we defined earlier
  replication_instance_arn = aws_dms_replication_instance.my_dms_instance.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn

  depends_on = [
    aws_dms_replication_instance.my_dms_instance,
    aws_dms_endpoint.source,
    aws_dms_endpoint.target
  ]

  table_mappings = jsonencode({
    rules = [
      {
        "rule-type": "transformation", "rule-id": "1", "rule-name": "RenameTable",
        "rule-target": "table", 
        "object-locator": { "schema-name": "e_commerce_db", "table-name": "e_orders" },
        "rule-action": "rename", "value": "e_orders_nosql"
      },
      {
        "rule-type": "selection", "rule-id": "2", "rule-name": "SelectOrders",
        "object-locator": { "schema-name": "e_commerce_db", "table-name": "e_orders" },
        "rule-action": "include"
      }
    ]
  })
}