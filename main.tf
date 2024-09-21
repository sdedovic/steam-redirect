terraform {
  backend "s3" {
    bucket = "terraform-backend20240809213149202200000001"
    key    = "steam-redirect/steam-redirect/terraform.tfstate"
    region = "us-east-2"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.61"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.6.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Managed = "terraform"
      Project = "steam-redirect"
    }
  }
}

provider "archive" {}

variable "hosted_zone_id" {
  type        = string
  default     = "dedovic.com"
  description = "Identifier for hosted zone, i.e. the domain name."
}

variable "subdomain" {
  type        = string
  default     = "steam-redirect-service"
  description = "Subdomain for the redirect API."
}
