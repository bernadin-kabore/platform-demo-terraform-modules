moved {
  from = module.vpc
  to   = module.eks_foundation.module.vpc
}

moved {
  from = module.eks
  to   = module.eks_foundation.module.eks
}

moved {
  from = module.ecr
  to   = module.service_delivery.module.ecr
}

# The registry scanning configuration left modules/ecr for its own module when
# the role vending machine started creating ECR repositories from a separate
# state. Same resource, same account-wide singleton, new address -- without
# this it would be destroyed and recreated, and a destroy of the registry
# scanning configuration is an account-wide change, not a per-repository one.
moved {
  from = module.service_delivery.module.ecr.aws_ecr_registry_scanning_configuration.this
  to   = module.ecr_registry.aws_ecr_registry_scanning_configuration.this
}
