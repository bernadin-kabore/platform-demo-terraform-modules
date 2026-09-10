output "role_arns" {
  description = "Vended role ARNs, keyed as the input map was. This is what goes into the consuming repository as AWS_CI_ROLE_ARN."
  value       = { for role_key, role in aws_iam_role.vended : role_key => role.arn }
}

output "role_names" {
  value = { for role_key, role in aws_iam_role.vended : role_key => role.name }
}

output "permissions_boundary_arn" {
  description = "The ceiling attached to every vended role. Echoed back so an audit can assert it is the same policy on all of them."
  value       = var.permissions_boundary_arn
}

output "granted_statements" {
  description = <<-DESC
    What each role was actually granted, flattened for review. Makes a plan
    diff legible: an added action shows up here as a one-line change rather
    than as a re-rendered JSON blob.
  DESC
  value       = local.role_statements
}

output "ecr_repository_urls" {
  description = "Image repositories created for the ecr-push grants, keyed <application>-<service>."
  value       = module.ecr.repository_urls
}
