terraform {
  required_providers {
    incapsula = {
      source = "imperva/incapsula"
    }
  }
}

provider "incapsula" {
  api_key        = "foo"
  api_id         = "bar"
  base_url       = "http://localhost:8081"
  base_url_rev_2 = "http://localhost:8081"
  base_url_rev_3 = "http://localhost:8081"
  base_url_api   = "http://localhost:8081"
}

locals {
  account_id = "cd3ba503-f034-4912-8f89-a599c8cfbbc6"
}

module "abp" {
  source     = "./abp"
  account_id = local.account_id
}


data "incapsula_abp_pending_changes" "current" {
  depends_on = [module.abp]
}

resource "incapsula_abp_preflight" "current" {
  account_id   = local.account_id
  pending_hash = data.incapsula_abp_pending_changes.current.hash
}

resource "incapsula_abp_publish" "publish" {
  preflight_id = incapsula_abp_preflight.current.id
}

output "cond1" {
  value = incapsula_abp_condition.cond1
}

resource "incapsula_abp_proof_of_work_configuration" "pow1" {
  account_id = "a9fa7bb9-a36e-40aa-ac81-fe320d634988"
  name       = "terraform-pow-0"
  difficulty = 42
  algorithm  = "bbs"
}

output "pow1" {
  value = incapsula_abp_proof_of_work_configuration.pow1
}
