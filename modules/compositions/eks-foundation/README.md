# eks-foundation

Platform composition for the network and EKS foundation. It deliberately
consumes the existing `vpc` and `eks` resource modules so environments select
policy without duplicating resource implementation.

Environment roots should call this module instead of wiring VPC and EKS
primitives directly. Existing state is migrated with the `moved` declarations
in the environment root.
