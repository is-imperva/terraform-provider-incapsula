terraform {
  required_providers {
    incapsula = {
      source = "imperva/incapsula"
    }
  }
}

variable "account_id" {
  type = string
}

resource "incapsula_abp_policy" "poltest1" {
  account_id  = var.account_id
  name        = "policy pt 1"
  description = "My cool policy"

  directive {
    action = "allow"
  }
}

resource "incapsula_abp_policy" "poltest2" {
  account_id  = var.account_id
  name        = "policy pt 2"
  description = "My cool policy change desc"

  directive {
    action = "allow"
  }
}

resource "incapsula_abp_policy" "poltest3" {
  account_id  = var.account_id
  name        = "cool name"
  description = "policy 3.2"

  directive {
    action = "allow"
  }
}

resource "incapsula_abp_condition" "cond1" {
  account_id  = var.account_id
  name        = "terraform-0"
  description = "Created through terraform twice"
  code        = "(any true false)"
}

# Attach the literal condition above to the auto-generated condition list of
# poltest1's first directive.
resource "incapsula_abp_condition_list_entry" "poltest1_allow_cond1" {
  account_id               = var.account_id
  parent_condition_list_id = incapsula_abp_policy.poltest1.directive[0].condition_id
  condition_id             = incapsula_abp_condition.cond1.id
  state                    = "active"
  tags                     = ["terraform_managed"]
}

# A reusable condition list grouping individual conditions; can be referenced
# from multiple policies via condition_list_entry.
resource "incapsula_abp_condition_list" "shared_list" {
  account_id  = var.account_id
  name        = "terraform-shared-list"
  description = "Reusable condition list managed by terraform"
}

# Add cond1 to the shared list.
resource "incapsula_abp_condition_list_entry" "shared_list_cond1" {
  account_id               = var.account_id
  parent_condition_list_id = incapsula_abp_condition_list.shared_list.id
  condition_id             = incapsula_abp_condition.cond1.id
  state                    = "active"
  tags                     = ["terraform_managed"]
}

# Attach the shared list to poltest2's first directive.
resource "incapsula_abp_condition_list_entry" "poltest2_allow_shared_list" {
  account_id               = var.account_id
  parent_condition_list_id = incapsula_abp_policy.poltest2.directive[0].condition_id
  condition_list_id        = incapsula_abp_condition_list.shared_list.id
  state                    = "active"
  tags                     = ["terraform_managed"]
}

#
# Proof Of Work
#

resource "incapsula_abp_proof_of_work_configuration" "pow1" {
  account_id = var.account_id
  name       = "terraform-pow-0"
  difficulty = 42
  algorithm  = "bbs"
}

data "incapsula_abp_proof_of_work_configuration" "pow1_lookup" {
  account_id = var.account_id
  name       = incapsula_abp_proof_of_work_configuration.pow1.name
}

data "incapsula_abp_site_analysis_settings" "login" {
  rate_limiting           = "per_site"
  max_requests_per_minute = 100
}

data "incapsula_abp_site_analysis_settings" "static" {
  rate_limiting = "none"
}

data "incapsula_abp_site_analysis_settings" "postback" {
  rate_limiting                     = "custom_scope"
  rate_limiting_custom_scope        = "my scope"
  max_requests_per_minute           = 55
  max_requests_per_session          = 555
  max_session_length                = "1h"
  use_site_rate_limiting_parameters = false
}

resource "incapsula_abp_site" "site1" {
  account_id = var.account_id
  name       = "terraform-site-0"

  default_max_requests_per_minute  = 60
  default_max_requests_per_session = 600
  default_max_session_length       = "2h"

  selector {
    path_prefix       = "/login"
    policy_id         = incapsula_abp_policy.poltest1.id
    analysis_settings = data.incapsula_abp_site_analysis_settings.login.json
  }

  selector {
    path_regex        = "\\.png$"
    analysis_settings = data.incapsula_abp_site_analysis_settings.static.json
  }

  selector {
    postback          = "web_interrogation"
    analysis_settings = data.incapsula_abp_site_analysis_settings.postback.json
  }
}

resource "incapsula_abp_site" "site2" {
  account_id = var.account_id
  name       = "terraform-site-2"

  default_max_requests_per_minute  = 30
  default_max_requests_per_session = 300
  default_max_session_length       = "1h"

  selector {
    path_prefix       = "/login"
    policy_id         = incapsula_abp_policy.poltest3.id
    analysis_settings = data.incapsula_abp_site_analysis_settings.login.json
  }
}

resource "incapsula_abp_domain" "domain1" {
  account_id              = var.account_id
  site_id                 = incapsula_abp_site.site1.id
  cookiescope             = "example.com"
  log_region              = "apac"
  cookie_mode             = "none_secure"
  enable_mitigation       = false
  enable_mobile_sdk_token = false
  // Todo: backend auto-prefixes with `/` causing a perpetual change-detection if omitted on this field
  // Other paths are validated enforcing path prefixing, we could do that in the tf-layer, backend, or not at all
  obfuscate_path                     = "/spooky-path"
  interstitial_inprogress_iframe_src = "http://www.example.com/iframe-src"
  divert_host                        = "www.example.com"
  unmasked_headers                   = ["content-length", "content-type"]
  proxy_flags                        = ["enable_referrer_fix", "inject_js_into_body"]

  # Temporary commented out as it doesn't work locally due to MY dependency
  # no_js_injection_path {
  #   path_prefix = "/no-js-here"
  # }

  captcha_settings {
    // Todo: Could unpack this into a `data`
    geetest {
      geetest_captcha_id  = "abcd"
      geetest_private_key = "my key"
    }
  }

  analysis_ip_lookup_mode {
    header_name   = "X-Forwarded-For"
    reverse_index = 0
  }
  challenge_ip_lookup_mode {
    header_name   = "Origin"
    reverse_index = 0
  }
  criteria {
    exact = "terraform-domain-0.example.com"
  }
}

resource "incapsula_abp_domain" "domain2" {
  account_id  = var.account_id
  site_id     = incapsula_abp_site.site1.id
  cookiescope = "example.com"
  log_region  = "usa"
  cookie_mode = "lax"

  # Temporary commented out as it doesn't work locally due to MY dependency
  // Todo: reference a rule here
  # no_js_injection_path {
  #   incap_rule = "URL == \"/admin\""
  # }

  captcha_settings {
    managed_geetest {
      difficulty = "hard"
    }
  }
  criteria {
    prefix = "terraform-domain-1"
  }
}

resource "incapsula_abp_domain" "domain3" {
  account_id  = var.account_id
  site_id     = incapsula_abp_site.site1.id
  cookiescope = "example.com"
  log_region  = "eu"
  cookie_mode = "legacy"
  captcha_settings {
    managed_hcaptcha {
      difficulty = "auto"
    }
  }
  criteria {
    suffix = "sub3.example.com"
  }
}

resource "incapsula_abp_domain_encryption_key" "dummy-key" {
  domain_id = incapsula_abp_domain.domain3.id
  key = "U2VjcmV0IGtleSB1c2luZyBzdGF0ZS1vZi10aGUtYXJ0IGJhc2U2NCBlbmNyeXB0aW9u"
}


resource "incapsula_abp_site_domain_priority" "prio" {
  site_id = incapsula_abp_site.site1.id
  domain_ids = [incapsula_abp_domain.domain2.id, incapsula_abp_domain.domain1.id, incapsula_abp_domain.domain3.id]
}

/*resource "incapsula_abp_account_site_priority" "accprio" {
  account_id = var.account_id
  site_ids = [
    incapsula_abp_site.site2.id,
    incapsula_abp_site.site1.id,
    // .. fill out complete list
  ]
}*/

resource "incapsula_abp_credential" "my_credential" {
  account_id = var.account_id
  // With a key on disk in PEM format base64 < {keyfile} | tr -d '\n'
  // pgp_key = "LS0tLS1CRUdJTiBQR1AgUFVCTElDIEtFWSBCTE9DSy0tLS0tCgptRE1FYUY2N2tSWUpLd1lCQkFIYVJ3OEJBUWRBcDRBSGk3cTh0a01xaHp2L3dpUHBCbTNFVUI1SGtaalJiYXRCCloyNGNZRFcwU1UxaGNtTjFjeUJIY21GemN5QW9SMlZ1WlhKaGJDQndkWEp3YjNObElHbGtaVzUwYVhSNUlHdGwKZVNrZ1BHMWhjbU4xY3k1bmNtRnpjMEJ3Y205MGIyNXRZV2xzTG1OdmJUNkltUVFURmdvQVFSWWhCTmJDcXdNawo5RnM0V3k4amI3dWhDOE1aOUFYL0JRSm9YcnVSQWhzQkJRa0paZ0dBQlFzSkNBY0NBaUlDQmhVS0NRZ0xBZ1FXCkFnTUJBaDRIQWhlQUFBb0pFTHVoQzhNWjlBWC9GWHNBLzNXRW85OVUxN2lzQW5zZXBEczJJUzNVVjZwWDJ6TFYKaEpvaFNGWjlIU01oQVB3Sk1hM1ZocEJZeGM1S3RONGFEbmRUWCs1aDMyQ1Y5LzBERTVZUFJ2NFdBN2d6QkdoZQp1OE1XQ1NzR0FRUUIya2NQQVFFSFFGUnd1WVJoMHlOaE5tUHZJTmdnV04ycml0R3dBaGRPMEJmeDhnVXd2QVJlCmlQVUVHQllLQUNZV0lRVFd3cXNESlBSYk9Gc3ZJMis3b1F2REdmUUYvd1VDYUY2N3d3SWJBZ1VKQ1dZQmdBQ0IKQ1JDN29RdkRHZlFGLzNZZ0JCa1dDZ0FkRmlFRStzeWlKUm9pemlMSjhhelY1aXZZZ2dwMmxpOEZBbWhldThNQQpDZ2tRNWl2WWdncDJsaTlnL1FFQXk1RThzT1pqVlRaRXRKTTE2OExsYmNoL3haVjAyQjIzSW5FbDEyN0xCaWNBCi8zMzZORldIajZLVXl4N2gvRndxTUVJVUZWMXMvRXd3MHNjN2E1UE5VWWdMaHBRQS9SWWRFcDlYYm5adEhuRngKbGpNRmhzTUpBYWRIeFdmVk9DN2hNWGtDMzF5UEFRQzZCNjVkclkzdmh2MW40WmlDbllmaUhNSkhNbXlpNDZwYwpCQThFTExqb0JiZ3pCR2hldTh3V0NTc0dBUVFCMmtjUEFRRUhRRXBoYW9CWndrZWpmNzR6d1FlSkN3VE5iaUNwClR2dStOQW83ZG5ObDdZTC9pSDRFR0JZS0FDWVdJUVRXd3FzREpQUmJPRnN2STIrN29RdkRHZlFGL3dVQ2FGNjcKekFJYklBVUpDV1lCZ0FBS0NSQzdvUXZER2ZRRi8xZWVBUURxWm45YnVJODc0Qmp2T0tWd3U5UEwyc1hadnIvawp2YUZCenZCRHZPNEt5QUQvWlBjUndQSlQ2aHRuQW43NWpkWXp2R0R4dnNBdEp3QlI1b1ZTU1RZbVlnUzRPQVJvClhydmVFZ29yQmdFRUFaZFZBUVVCQVFkQUV2VG9MeUkwTDRiWDZGMlBBZjV2OUdjeGZqNE43K25namVzRnhxa3UKdUUwREFRZ0hpSDRFR0JZS0FDWVdJUVRXd3FzREpQUmJPRnN2STIrN29RdkRHZlFGL3dVQ2FGNjczZ0liREFVSgpDV1lCZ0FBS0NSQzdvUXZER2ZRRi93b25BUDRpejR5R1RBUDk3RUNFd3RuZU9TcXlIRWxHVVhaZ1c1RGVHRjEyClNaUm1PUUVBKzlqeXFyUkkrTDVSVW9zbkFqVUxJKytWMjQwOVNCRzFSYm1QUlRGZzlnMD0KPXdrWG8KLS0tLS1FTkQgUEdQIFBVQkxJQyBLRVkgQkxPQ0stLS0tLQo="
  pgp_key = "keybase:marcusgrass"
}

output "my_credential_encrypted_secret" {
  value = incapsula_abp_credential.my_credential.encrypted_secret
}