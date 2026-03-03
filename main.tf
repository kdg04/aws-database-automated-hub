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

  attribute { name = "PK"; type = "S" }
  attribute { name = "SK"; type = "S" }
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
}

resource "aws_dms_replication_instance" "my_dms_instance" {
  replication_instance_id    = "migration-engine-lab"
  replication_instance_class = "dms.t3.small" 
  allocated_storage          = 10
  apply_immediately          = true
}

resource "aws_dms_replication_task" "migration_task" {
  replication_task_id      = "mysql-to-dynamo-automated"
  migration_type           = "full-load"                    # This means "copy everything once"
  
  # LINKING: We use the IDs from the resources we defined earlier
  replication_instance_arn = aws_dms_replication_instance.my_dms_instance.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn

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