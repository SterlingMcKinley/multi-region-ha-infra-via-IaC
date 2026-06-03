terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "sterling-sre-portfolio-tf-state-2026"
    key            = "global/multi-region-ha/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-running-locks"
  }
}

provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

provider "aws" {
  alias  = "secondary"
  region = "us-west-2"
}

# --- PRIMARY REGION DEPLOYMENT ---
module "vpc_primary" {
  source             = "../modules/vpc"
  providers          = { aws = aws.primary }
  region             = "us-east-1"
  vpc_cidr           = "10.1.0.0/16"
  public_subnets     = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnets    = ["10.1.10.0/24", "10.1.11.0/24"]
  availability_zones = ["us-east-1a", "us-east-1b"]
}

module "app_primary" {
  source            = "../modules/compute_app"
  providers         = { aws = aws.primary }
  region            = "us-east-1"
  vpc_id            = module.vpc_primary.vpc_id
  public_subnet_ids = module.vpc_primary.public_subnet_ids
}

# --- SECONDARY REGION DEPLOYMENT ---
module "vpc_secondary" {
  source             = "../modules/vpc"
  providers          = { aws = aws.secondary }
  region             = "us-west-2"
  vpc_cidr           = "10.2.0.0/16"
  public_subnets     = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnets    = ["10.2.10.0/24", "10.2.11.0/24"]
  availability_zones = ["us-west-2a", "us-west-2b"]
}

module "app_secondary" {
  source            = "../modules/compute_app"
  providers         = { aws = aws.secondary }
  region            = "us-west-2"
  vpc_id            = module.vpc_secondary.vpc_id
  public_subnet_ids = module.vpc_secondary.public_subnet_ids
}

# --- GLOBAL ROUTING ENGINE (FAILOVER POLICY) ---
resource "aws_route53_zone" "primary_domain" {
  provider = aws.primary
  name     = "sreportfolio-testing.com" # Replace with a domain you own or mock domain
}

resource "aws_route53_health_check" "primary_health" {
  provider          = aws.primary
  fqdn              = module.app_primary.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = "2"
  request_interval  = "10"
}

resource "aws_route53_record" "primary_record" {
  provider = aws.primary
  zone_id  = aws_route53_zone.primary_domain.zone_id
  name     = "app.sreportfolio-testing.com"
  type     = "A"

  failover_routing_policy { type = "PRIMARY" }
  set_identifier         = "primary-cluster"
  health_check_id        = aws_route53_health_check.primary_health.id

  alias {
    name                   = module.app_primary.alb_dns_name
    zone_id                = module.app_primary.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary_record" {
  provider = aws.primary
  zone_id  = aws_route53_zone.primary_domain.zone_id
  name     = "app.sreportfolio-testing.com"
  type     = "A"

  failover_routing_policy { type = "SECONDARY" }
  set_identifier         = "secondary-cluster"

  alias {
    name                   = module.app_secondary.alb_dns_name
    zone_id                = module.app_secondary.alb_zone_id
    evaluate_target_health = true
  }
}