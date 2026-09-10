terraform {
  required_providers {
    incapsula = {
      source = "imperva/incapsula"
    }
  }
}

provider "incapsula" {
  api_key                      = "foo"
  api_id                       = "bar"
  base_url                     = "http://localhost:8081"
  base_url_rev_2               = "http://localhost:8081"
  base_url_rev_3               = "http://localhost:8081"
  base_url_api                 = "http://localhost:8081"
  disable_api_key_verification = true
}

// Look up account ID corresponding to the provided API key
data "incapsula_abp_account" "current" {}

# All configuration put in a separate module so it can be referenced as
# a dependency for the publishing part. When any resource in the module
# changes its state publishing will be triggered
module "abp" {
  source     = "./abp"
  account_id = data.incapsula_abp_account.current.id
}

data "incapsula_abp_pending_changes" "current" {
  depends_on = [module.abp]
}

# Create a preflight (a snapshot of the configuration)
resource "incapsula_abp_preflight" "current" {
  account_id   = data.incapsula_abp_account.current.id
  pending_hash = data.incapsula_abp_pending_changes.current.hash
}

# Publish the specific preflight (make the corresponding configuration active)
resource "incapsula_abp_publish" "publish" {
  preflight_id = incapsula_abp_preflight.current.id
}

output "encrypted_secret" {
  value = module.abp.my_credential_encrypted_secret
}
