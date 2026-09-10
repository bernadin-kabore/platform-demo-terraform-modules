# ---------------------------------------------------------------------------
# The image repositories an ecr-push grant implies.
#
# These moved here from envs/dev along with the roles, and for the same reason:
# an application's repositories and the identity allowed to push to them are
# created together, by the same pull request, or the golden path still has a
# step against the Terraform repository in the middle of it.
#
# Only the repositories. Account-wide registry configuration -- the scanning
# rules -- stays in envs/dev via modules/ecr-registry, because it is a
# singleton and two states cannot both own it. See that module.
# ---------------------------------------------------------------------------

locals {
  vended_ecr_repositories = distinct(flatten([
    for role_key, role in var.roles : [
      for grant in role.grants : [
        for service in grant.services :
        "${local.role_application[role_key]}-${service}"
      ] if grant.bundle == "ecr-push"
    ]
  ]))
}

module "ecr" {
  source           = "../ecr"
  repository_names = local.vended_ecr_repositories
  tags             = var.tags
}
