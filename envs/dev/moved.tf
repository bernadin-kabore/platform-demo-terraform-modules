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
