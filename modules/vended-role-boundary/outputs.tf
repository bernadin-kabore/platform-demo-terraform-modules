output "arn" {
  description = "Attach as permissions_boundary on every vended role, and pin with an iam:PermissionsBoundary condition on whatever is allowed to create them."
  value       = aws_iam_policy.boundary.arn
}

output "name" {
  value = aws_iam_policy.boundary.name
}
