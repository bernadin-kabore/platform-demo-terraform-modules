# ---------------------------------------------------------------------------
# Account-wide ECR registry configuration. Exactly one root module may own
# this.
#
# aws_ecr_registry_scanning_configuration is a singleton per account and
# region -- there is no name, no identifier, nothing to key it by. It used to
# sit inside modules/ecr alongside the repositories, which was harmless while
# one root created every repository in the account. It stops being harmless the
# moment a second root does: the role vending machine creates ECR repositories
# for scaffolded applications from its own state, and if it also brought this
# resource along, the two states would each hold a copy and each apply would
# revert the other. Neither plan would look wrong.
#
# So the split is by lifetime, not by convenience: repositories come and go
# with applications and belong to whichever root vends them; the registry
# itself is platform-wide and belongs to envs/dev.
#
# Registry-wide scanning also guarantees that scan-on-push is never skipped for
# a repository created somewhere this module cannot see -- which, after the
# split, is most of them.
# ---------------------------------------------------------------------------

resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}
