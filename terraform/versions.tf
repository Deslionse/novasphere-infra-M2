terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Backend local pour demarrer. La S1 du module Bac+5 migre ce state
  # vers un backend S3 partage avec verrouillage natif (use_lockfile).
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "NovaSphere"
      ManagedBy = "Terraform"
      Owner     = var.owner
    }
  }
}
