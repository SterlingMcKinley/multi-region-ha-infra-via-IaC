variable "region" {
  type        = string
  description = "The AWS region where the compute resources will be deployed."
}

variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the Application Load Balancer and security groups will be created."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "A list of public subnet IDs where the Application Load Balancer will be provisioned."
}
