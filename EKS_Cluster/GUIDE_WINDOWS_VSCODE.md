# Triển khai EKS + Karpenter từ VS Code / Windows

Chạy bằng **PowerShell**: VPC → EKS/add-ons → Karpenter → NodeClass/NodePools → test.
Phạm vi chưa gồm ứng dụng Retail Store, database và CI/CD.

## 1. Chuẩn bị

- AWS CLI v2; Terraform >= 1.12; cluster 1.34 dùng kubectl 1.34.x, Helm 3.19.x phù hợp.
- Kiểm tra `terraform.tfvars` của ba thư mục; guide dùng dev, us-east-1.
- Bucket state phải tồn tại, bật versioning. Backend và remote-state readers phải cùng bucket, mỗi phần dùng key riêng.
- Ghim Metrics Server đã kiểm thử; xem [runbook lỗi Metrics Server/LBC](TROUBLESHOOT_METRICS_SERVER_LBC.md).
- Laptop phải truy cập được EKS API endpoint.

```powershell
$ProjectRoot = 'D:\Udemy\retail-eks-prj\EKS_Cluster'
$AwsRegion = 'us-east-1'
$env:AWS_PROFILE = 'default' # Thay bằng profile của bạn; đăng nhập SSO trước nếu dùng SSO
$env:AWS_REGION = $AwsRegion
aws sts get-caller-identity
aws --version
terraform version
kubectl version --client
helm version
aws s3api head-bucket --bucket tfstate-dev-us-east-1-trongpq-eks --region $AwsRegion
```

**Đạt:** đúng AWS account, công cụ chạy được, head-bucket không lỗi.
Chạy từng lệnh và dừng khi lỗi; PowerShell không tự dừng mọi lệnh native. Kiểm tra `$LASTEXITCODE` khi cần.
Đọc plan trước khi apply. Sửa source phải tạo plan mới; không dùng plan cũ.

## 2. VPC

```powershell
Set-Location "$ProjectRoot\01_VPC_tf_manifests"
terraform init
terraform validate
terraform plan -out=vpc.tfplan
terraform apply vpc.tfplan
terraform output
```

**Đạt:** có `vpc_id`, `private_subnet_ids`, `public_subnet_ids`.

## 3. EKS và add-ons

```powershell
Set-Location "$ProjectRoot\02_EKS_tf_manifests"
terraform init
terraform validate
terraform plan -out=eks.tfplan
terraform apply eks.tfplan

$ClusterName = terraform output -raw eks_cluster_name
if ($LASTEXITCODE -ne 0) { throw 'Không đọc được tên cluster.' }
$ClusterName = $ClusterName.Trim()
aws eks update-kubeconfig --name $ClusterName --region $AwsRegion --alias $ClusterName
kubectl config current-context
kubectl get nodes -o wide
kubectl get deployments,daemonsets -A
kubectl get pods -A
helm list -A
```

**Đạt:** đúng context; node Ready; Deployment đủ AVAILABLE; DaemonSet READY bằng DESIRED; không có Pod lỗi kéo dài.

```powershell
$AddonNames = aws eks list-addons --cluster-name $ClusterName --region $AwsRegion --query addons --output json | ConvertFrom-Json
foreach ($AddonName in $AddonNames) {
  aws eks describe-addon --cluster-name $ClusterName --addon-name $AddonName --region $AwsRegion --query "addon.{Name:addonName,Status:status,Issues:health.issues}" --output json
}
aws eks list-pod-identity-associations --cluster-name $ClusterName --region $AwsRegion
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=300s
kubectl top nodes
kubectl top pods -A
```

**Đạt:** add-ons ACTIVE, không health issues; LBC rollout thành công; metrics có số liệu.
Lỗi OpenAPI 503: dùng [runbook riêng](TROUBLESHOOT_METRICS_SERVER_LBC.md), giữ validation bật.

### Test từng add-on

Các lệnh trên kiểm tra readiness. Kiểm thử chức năng cần workload và cấu hình tương ứng:

| Thành phần | Test chức năng và kết quả cần đạt |
|---|---|
| Pod Identity | Pod dùng SA có association gọi AWS API được phép, không lỗi credentials |
| LBC | Service/Ingress test tạo LB; target healthy; HTTP trả kết quả mong đợi |
| EBS CSI | PVC + Pod dùng StorageClass EBS → PVC Bound; ghi/đọc dữ liệu sau khi tạo lại Pod với cùng PVC |
| Secrets Store CSI + AWS provider | SecretProviderClass + Pod có IAM phù hợp → mount đọc được secret; không in secret ra log |
| ExternalDNS | Service/Ingress có hostname trong hosted zone test → record được tạo, DNS resolve đúng |
| Metrics Server | `kubectl top nodes` và `kubectl top pods -A` trả CPU/RAM; HPA cần test workload riêng |
| Karpenter | Bài test ở mục 6 |

Readiness chưa chứng minh IAM/EBS/DNS/ALB hoạt động end-to-end. Dọn workload và tài nguyên AWS test sau khi xong; ExternalDNS có thể giữ record nếu policy là upsert-only.

## 4. Karpenter

```powershell
$EcrPassword = aws ecr-public get-login-password --region us-east-1
if ($LASTEXITCODE -ne 0) { throw 'Không lấy được token ECR.' }
$EcrPassword | helm registry login --username AWS --password-stdin public.ecr.aws
$LoginExitCode = $LASTEXITCODE
Remove-Variable EcrPassword
if ($LoginExitCode -ne 0) { throw 'Helm registry login thất bại.' }

Set-Location "$ProjectRoot\03_Karpenter_tf_manifests"
terraform init
terraform validate
terraform plan -out=karpenter.tfplan
terraform apply karpenter.tfplan
kubectl rollout status deployment/karpenter -n kube-system --timeout=300s
kubectl get sa karpenter -n kube-system
kubectl get crd ec2nodeclasses.karpenter.k8s.aws nodepools.karpenter.sh nodeclaims.karpenter.sh
terraform output -raw karpenter_node_role_name
```

**Đạt:** rollout thành công, có SA và ba CRD. Lưu tên node role cho bước 5.

## 5. NodeClass và NodePools

Sửa `04_Karpenter_k8s_manifests/1_ec2nodeclass.yaml`:

- `spec.role`: tên role từ bước 4, ví dụ `retail-dev-karpenter-node-role`.
- Subnet/SG selectors: khớp tag tài nguyên đúng VPC cluster.
- AZ trong NodePools phải có subnet phù hợp; source dùng us-east-1a/b/c.

```powershell
Set-Location "$ProjectRoot\04_Karpenter_k8s_manifests"
kubectl apply -f .\1_ec2nodeclass.yaml
kubectl wait --for=condition=Ready ec2nodeclass/default-ec2nodeclass --timeout=300s
kubectl apply -f .\2_nodepool_ondemand.yaml
kubectl apply -f .\3_nodepool_spot.yaml
kubectl wait --for=condition=Ready nodepool/ondemand-nodepool --timeout=300s
kubectl wait --for=condition=Ready nodepool/spot-nodepool --timeout=300s
kubectl get ec2nodeclass default-ec2nodeclass -o yaml
kubectl get nodepools
```

**Đạt:** Ready=True; status.subnets/securityGroups đúng tài nguyên. Chưa có NodeClaim là bình thường nếu chưa cần node mới.

## 6. Test Karpenter và dọn test

Test có thể tạo EC2 tính phí. Selector buộc Pod chạy trên On-Demand pool thay vì managed node group.

```powershell
@'
apiVersion: v1
kind: Pod
metadata:
  name: karpenter-smoke-test
  namespace: default
spec:
  nodeSelector:
    karpenter.sh/nodepool: ondemand-nodepool
  containers:
    - name: pause
      image: registry.k8s.io/pause:3.10
      resources:
        requests:
          cpu: "500m"
          memory: "128Mi"
'@ | kubectl apply -f -

kubectl get nodeclaims
kubectl wait --for=condition=Ready pod/karpenter-smoke-test -n default --timeout=600s
kubectl get pod karpenter-smoke-test -n default -o wide
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type
```

**Đạt:** Pod Ready trên node thuộc ondemand-nodepool. Nếu pool chưa có node phù hợp, phải thấy NodeClaim/node mới. Nếu đã có node đủ chỗ, bài test chỉ xác nhận scheduling, chưa chứng minh tạo node mới.

```powershell
kubectl delete pod karpenter-smoke-test -n default
kubectl get nodeclaims
kubectl get nodes -L karpenter.sh/nodepool
```

Theo dõi lại sau vài phút. Node có thể được thu hồi khi không còn cần thiết; workload khác/disruption constraints có thể giữ node. `consolidateAfter: 30s` không đảm bảo EC2 bị xóa sau đúng 30 giây.

## 7. Khi lỗi / chạy tiếp lần sau

```powershell
kubectl get events -A --sort-by=.metadata.creationTimestamp
kubectl describe ec2nodeclass default-ec2nodeclass
kubectl describe nodepool ondemand-nodepool
kubectl describe pod karpenter-smoke-test -n default
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --all-containers=true --tail=100
```

Với Pod khác, dùng describe/logs đúng tên và namespace. Mở terminal mới thì khai báo lại biến ở mục 1 và lấy ClusterName ở mục 3. Sửa phần nào thì plan/apply tại thư mục đó; giữ nguyên state. Prod cần state, biến và selectors riêng.
