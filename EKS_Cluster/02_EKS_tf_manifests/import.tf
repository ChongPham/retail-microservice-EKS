import {
  to = aws_iam_role.eks_cluster
  id = "retail-dev-eks-cluster-role"
}

import {
  to = aws_iam_role.eks_nodegroup_role
  id = "retail-dev-eks-nodegroup-role"
}

import {
  to = aws_iam_policy.lbc_iam_policy
  id = "arn:aws:iam::174772361218:policy/retail-dev-AWSLoadBalancerControllerIAMPolicy"
}

import {
  to = aws_iam_role.lbc_iam_role
  id = "retail-dev-lbc-iam-role"
}

import {
  to = aws_iam_role.ebs_csi_iam_role
  id = "retail-dev-ebs-csi-iam-role"
}

import {
  to = aws_iam_role.externaldns_role
  id = "retail-dev-externaldns-role"
}

import {
  to = aws_eks_cluster.main
  id = "retail-dev-eksdemo1"
}