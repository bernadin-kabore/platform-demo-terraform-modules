# Karpenter-specific IAM + spot interruption plumbing. Kept separate from
# the eks module so Karpenter can be upgraded/reinstalled independently of
# the cluster itself.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = "aws"
}

# ---------------------------------------------------------------------------
# Node IAM role + instance profile — assumed by EC2 instances Karpenter
# launches. Reuses the same permission set as the EKS-managed node group.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-karpenter-node"
  role = aws_iam_role.node.name
}

# ---------------------------------------------------------------------------
# Controller IAM role (IRSA) — what the Karpenter pod itself assumes to
# call EC2 fleet/spot APIs.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "${var.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.controller_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "controller_permissions" {
  statement {
    sid    = "AllowScopedEC2InstanceActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      # Karpenter creates a launch template per distinct node shape and garbage
      # collects them. Without delete permission it logs "failed to delete
      # launch template" on every reconcile and the templates accumulate
      # against the account limit indefinitely.
      "ec2:DeleteLaunchTemplate",
      "ec2:CreateTags",
      "ec2:TerminateInstances",
      "ec2:DescribeInstances",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeImages",
      "pricing:GetProducts",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.node.arn]
  }

  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.interruption.arn]
  }

  statement {
    sid       = "AllowEKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [var.cluster_arn]
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "${var.cluster_name}-karpenter-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller_permissions.json
}

# ---------------------------------------------------------------------------
# Spot interruption handling — SQS queue + EventBridge rules feeding it.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.interruption.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name = "${var.cluster_name}-karpenter-spot-interruption"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name = "${var.cluster_name}-karpenter-rebalance"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name = "${var.cluster_name}-karpenter-instance-state-change"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule = aws_cloudwatch_event_rule.rebalance.name
  arn  = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule = aws_cloudwatch_event_rule.instance_state_change.name
  arn  = aws_sqs_queue.interruption.arn
}

# ---------------------------------------------------------------------------
# Cluster access for the nodes Karpenter launches.
#
# This cluster uses the API authentication mode, so there is no aws-auth
# ConfigMap: a node role that is not registered as an access entry produces
# instances that boot, run healthily in EC2, and never join. Nothing errors —
# the NodeClaim simply sits at Registered=Unknown forever, and the symptom that
# reaches you is unrelated pods Pending on "Too many pods" because capacity
# never grows. The managed node group gets its entry created by EKS itself,
# which is why that one works and this one has to be declared.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"
  tags          = var.tags
}

# ---------------------------------------------------------------------------
# The EC2 Spot service-linked role.
#
# The default NodePool is spot-first, and the first spot fleet request in an
# account fails with
# "AuthFailure.ServiceLinkedRoleCreationNotPermitted" unless this role exists.
# It is account-global and shared by everything that uses Spot, so it is
# created only when var.create_spot_service_linked_role is true — set it to
# false in any account where another stack already owns it, and import it if
# this configuration should adopt one that already exists:
#
#   terraform import 'module.karpenter_iam.aws_iam_service_linked_role.spot[0]' \
#     arn:aws:iam::<account>:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot
# ---------------------------------------------------------------------------

resource "aws_iam_service_linked_role" "spot" {
  count            = var.create_spot_service_linked_role ? 1 : 0
  aws_service_name = "spot.amazonaws.com"
}
