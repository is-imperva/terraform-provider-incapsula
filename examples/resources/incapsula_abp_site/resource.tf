# A Site (a.k.a. Website Group) groups Domains together and maps incoming
# requests to Policies via an ordered list of Selectors.
resource "incapsula_abp_site" "sample_site" {
  account_id = var.account_id
  name       = "Sample site"
  industry   = "retail"

  default_max_requests_per_minute  = 60
  default_max_requests_per_session = 600
  default_max_session_length       = "2h"

  # Each selector matches requests one way, chosen by which block `kind`
  # holds. Write exactly one of them.

  # Match by path prefix and apply a specific Policy.
  selector {
    purpose   = "login"
    policy_id = incapsula_abp_policy.policy_with_custom_directives.id
    kind {
      path_prefix {
        value            = "/login"
        case_insensitive = true
      }
    }
    analysis_settings = data.incapsula_abp_site_analysis_settings.login.json
  }

  # Match by regex.
  selector {
    kind {
      path_regex {
        value = "\\.png$"
      }
    }
    analysis_settings = data.incapsula_abp_site_analysis_settings.static.json
  }

  # A postback selector.
  selector {
    kind {
      postback {
        value = "web_interrogation"
      }
    }
    analysis_settings = data.incapsula_abp_site_analysis_settings.postback.json
  }

  # Match requests of an API Security group.
  selector {
    purpose = "backend_api"
    kind {
      api_security_group {
        value = "checkout-api"
      }
    }
    analysis_settings = data.incapsula_abp_site_analysis_settings.postback.json
  }
}
