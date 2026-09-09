output "repository_urls" {
  description = "ECR repository URL per service, keyed <application>-<service>. The application's CI reads only the registry host from vars.ECR_REGISTRY and derives the rest by the same convention."
  value       = module.ecr.repository_urls
}

output "ci_role_arns" {
  description = "One role per application. Set it as the AWS_CI_ROLE_ARN secret on that application's source repository."
  value       = { for name, role in aws_iam_role.ci : name => role.arn }
}

output "github_oidc_provider_arn" { value = aws_iam_openid_connect_provider.github.arn }
