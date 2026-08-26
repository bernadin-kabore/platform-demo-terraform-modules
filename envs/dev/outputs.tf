output "cluster_name" {
  value = module.eks_foundation.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks_foundation.cluster_name}"
}

output "oidc_provider_arn" {
  value = module.eks_foundation.oidc_provider_arn
}

output "karpenter_controller_role_arn" {
  value = module.karpenter_iam.controller_role_arn
}

output "karpenter_node_instance_profile_name" {
  value = module.karpenter_iam.node_instance_profile_name
}

output "karpenter_interruption_queue_name" {
  value = module.karpenter_iam.interruption_queue_name
}

output "crossplane_provider_aws_role_arn" {
  value = module.irsa_crossplane.role_arn
}

output "opencost_role_arn" {
  value = module.irsa_opencost.role_arn
}

output "aws_lb_controller_role_arn" {
  value = module.irsa_aws_lb_controller.role_arn
}

output "external_dns_role_arn" {
  value = module.irsa_external_dns.role_arn
}

output "ecr_repository_urls" {
  value = module.service_delivery.repository_urls
}

output "service_ci_role_arns" {
  value = module.service_delivery.ci_role_arns
}
