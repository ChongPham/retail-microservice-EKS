# Chính sách này cấp cho Karpenter quyền hạn được kiểm soát chặt chẽ (scoped permissions) để tự động khởi tạo, 
# cấu hình và quản lý các máy chủ ảo (EC2 instances) và các tài nguyên liên quan khi cụm EKS cần scale-up/scale-down node.

data "aws_iam_policy_document" "karpenter_controller" {

  # ---------------------------------------------------------------------------
  # AllowScopedEC2InstanceAccessActions
  # ---------------------------------------------------------------------------
  statement {
    # Cho phép gọi API tạo máy chủ (RunInstances) và tạo fleet (CreateFleet) 
    # trên các tài nguyên chung của vùng (như AMI, subnet, security group, capacity reservation).
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.region}::image/*",
      "arn:aws:ec2:${data.aws_region.current.region}::snapshot/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:security-group/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:subnet/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:capacity-reservation/*",
    ]
  }

  # ---------------------------------------------------------------------------
  # AllowScopedEC2LaunchTemplateAccessActions
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedEC2LaunchTemplateAccessActions"
    effect = "Allow"
    # Cho phép tạo EC2 instances/fleets sử dụng các Launch Template thuộc cụm EKS này
    # (được phân biệt bằng điều kiện nhãn kubernetes.io/cluster/<cluster_name> = owned).
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowScopedEC2InstanceActionsWithTags
  # Cho phép tạo mới các tài nguyên tính toán (như instance, volume, launch template, network interface) 
  # với điều kiện bắt buộc phải gắn các nhãn (tags) nhận diện cụm và Karpenter NodePool tương ứng. 
  # Điều này ngăn chặn việc Karpenter tạo tài nguyên rác hoặc chiếm quyền kiểm soát tài nguyên bên ngoài cụm.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"

    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.region}:*:fleet/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:volume/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:network-interface/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:spot-instances-request/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:capacity-reservation/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowScopedResourceCreationTagging
  # Cho phép Karpenter gán thẻ (tags) vào các tài nguyên ngay tại thời điểm chúng được tạo ra 
  # (ec2:CreateAction với các hành động như RunInstances, CreateFleet).
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedResourceCreationTagging"
    effect = "Allow"

    actions = [
      "ec2:CreateTags",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.region}:*:fleet/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:volume/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:network-interface/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:spot-instances-request/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = [
        "RunInstances",
        "CreateFleet",
        "CreateLaunchTemplate",
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowScopedResourceTagging
  # Cho phép Karpenter cập nhật hoặc gắn thêm một số thẻ cụ thể 
  # (như tên node, tên cụm) lên các EC2 instance đang chạy trong vòng đời quản lý của nó.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedResourceTagging"
    effect = "Allow"

    actions = [
      "ec2:CreateTags",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values = [
        "eks:eks-cluster-name",
        "karpenter.sh/nodeclaim",
        "Name",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowScopedDeletion
  # Khi cụm giảm tải (scale-down) hoặc khi một node không còn nhu cầu sử dụng, 
  # Karpenter cần quyền để hủy instance đó và xóa các launch template cũ không còn dùng tới.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"

    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.region}:*:instance/*",
      "arn:aws:ec2:${data.aws_region.current.region}:*:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowRegionalReadActions
  # Karpenter cần quyền "nhìn ngó" xem trong vùng AWS hiện tại có những loại máy chủ gì, 
  # giá Spot lịch sử ra sao, Subnet nào còn trống, Security Group nào khả dụng để từ đó đưa ra quyết 
  # định thông minh nhất khi cần chọn loại máy khởi chạy.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"

    actions = [
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.region]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowSSMReadActions
  # Quyền đọc thông số từ AWS Systems Manager)
  # Giúp Karpenter tự động tra cứu và lấy ra ID của bản AMI chuẩn được tối ưu hóa cho EKS (Amazon EKS-optimized AMI) 
  # mới nhất từ AWS Parameter Store mà không cần phải hardcode cứng ID của hệ điều hành.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowSSMReadActions"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
    ]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.region}::parameter/aws/service/*",
    ]
  }

  # ---------------------------------------------------------------------------
  # AllowPricingReadActions
  # Karpenter có tính năng cốt lõi là tối ưu hóa chi phí (Cost Optimization).
  #  Để làm được điều này, nó cần gọi API tra cứu bảng giá của AWS để so sánh giá tiền theo thời gian thực giữa các 
  # loại EC2 instance khác nhau hoặc giữa On-Demand và Spot, từ đó chọn ra cấu hình rẻ nhất và phù hợp nhất cho các Pod 
  # đang chờ.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowPricingReadActions"
    effect = "Allow"

    actions = [
      "pricing:GetProducts",
    ]

    resources = ["*"]
  }

  # ---------------------------------------------------------------------------
  # AllowInterruptionQueueActions
  # (assumes aws_sqs_queue.karpenter_interruption exists)
  # Karpenter cần lắng nghe các thông báo từ AWS (như việc máy chủ Spot sắp bị thu hồi, sự kiện bảo trì phần cứng, 
  # hoặc thay đổi trạng thái instance). Các thông báo này được AWS gửi qua EventBridge và đổ vào một hàng đợi SQS. 
  # Quyền này cho phép Karpenter đọc và xóa các tin nhắn trong hàng đợi đó để kịp thời drain (di dời) các Pod khỏi 
  # node sắp bị hủy một cách an toàn trước khi AWS tắt máy.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"

    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes", 
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]

    resources = [
      aws_sqs_queue.karpenter_interruption.arn,
    ]
  }

  # ---------------------------------------------------------------------------
  # AllowPassingInstanceRole
  # Khi Karpenter ra lệnh khởi tạo một EC2 instance mới, nó phải "chuyển giao" (pass) 
  # một IAM Role cho dịch vụ EC2 để chiếc máy chủ ảo đó mang theo các quyền hạn cần thiết khi chạy bên trong cụm
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowPassingInstanceRole"
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = [
      aws_iam_role.karpenter_node.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "ec2.amazonaws.com",
        "ec2.amazonaws.com.cn",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowScopedInstanceProfileCreationActions
  # Một EC2 instance muốn gắn IAM Role thì cần phải thông qua một đối tượng trung gian gọi là Instance Profile. 
  # Quyền này cho phép Karpenter tự động tạo ra Instance Profile khi khởi tạo node mới, đồng thời ép buộc các profile
  #  này phải được gán đúng nhãn của cụm EKS hiện tại để tránh tạo bừa bãi.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedInstanceProfileCreationActions"
    effect = "Allow"

    actions = [
      "iam:CreateInstanceProfile",
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowScopedInstanceProfileTagActions
  # Cho phép Karpenter cập nhật hoặc gắn thêm thẻ vào Instance Profile vừa tạo.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedInstanceProfileTagActions"
    effect = "Allow"

    actions = [
      "iam:TagInstanceProfile",
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [local.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowScopedInstanceProfileActions
  # Sau khi tạo xong Instance Profile và IAM Role, Karpenter cần các quyền này để gắn (add)
  #  Role vào Instance Profile (hoặc gỡ ra/xóa đi khi không còn dùng đến).
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowScopedInstanceProfileActions"
    effect = "Allow"

    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [data.aws_region.current.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # AllowInstanceProfileReadActions
  # Trước khi tạo mới một Instance Profile, 
  # Karpenter cần kiểm tra xem profile đó đã tồn tại sẵn hay chưa để tránh bị lỗi trùng lặp
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowInstanceProfileReadActions"
    effect = "Allow"

    actions = [
      "iam:GetInstanceProfile",
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
    ]
  }

  # ---------------------------------------------------------------------------
  # AllowUnscopedInstanceProfileListAction
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowUnscopedInstanceProfileListAction"
    effect = "Allow"

    actions = [
      "iam:ListInstanceProfiles",
    ]

    resources = ["*"]
  }

  # ---------------------------------------------------------------------------
  # AllowAPIServerEndpointDiscovery
  # Cho phép tiến trình Karpenter gọi trực tiếp vào API của cụm EKS để lấy các thông tin 
  # cấu hình quan trọng (như Kubernetes API server endpoint, chứng chỉ CA, thông tin mạng), 
  # từ đó giúp các worker node mới có thể bootstrap và join vào cụm một cách chính xác.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "AllowAPIServerEndpointDiscovery"
    effect = "Allow"

    actions = [
      "eks:DescribeCluster",
    ]

    resources = [
      "arn:aws:eks:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}",
    ]
  }
}

resource "aws_iam_policy" "karpenter_controller" {
  name        = "${local.name}-karpenter-controller-policy"
  description = "Karpenter controller IAM policy (AWS official)"
  policy      = data.aws_iam_policy_document.karpenter_controller.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_attach" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}