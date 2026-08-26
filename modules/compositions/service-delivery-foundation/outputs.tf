output "repository_urls" { value = module.ecr.repository_urls }
output "ci_role_arns" { value = { for name, role in aws_iam_role.ci : name => role.arn } }
output "github_oidc_provider_arn" { value = aws_iam_openid_connect_provider.github.arn }
