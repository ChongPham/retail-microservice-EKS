# Build hạ tầng và ứng dụng hiện tại — Windows PowerShell

**Thứ tự:** chuẩn bị → VPC → EKS/add-ons → Karpenter → NodePools → AWS Data Plane → Helm app → test.

Phạm vi là source hiện tại: Catalog dùng RDS MySQL, Orders dùng RDS PostgreSQL, Carts dùng DynamoDB, Checkout dùng Redis, Orders dùng SQS. Chưa triển khai thiết kế MySQL chung, SSM hoặc tách prod trong `recommend-env-deployment.md`. Không gồm CI/CD và monitoring stack; vẫn cài Metrics Server vì HPA cần nó.

## 1. Chuẩn bị và xử lý cấu hình trước khi chạy

Chạy trong terminal PowerShell của VS Code; giữ cùng terminal để dùng các biến bên dưới. Dừng khi lệnh lỗi, kiểm tra `$LASTEXITCODE`; không tiếp tục apply các bước sau.

```powershell
$Root = 'D:\Udemy\retail-eks-prj'
$Region = 'us-east-1'
$env:AWS_PROFILE = 'dev-ops' # Tên AWS CLI profile SSO thực tế của bạn
$env:AWS_REGION = $Region
aws sso login --profile $env:AWS_PROFILE
aws sts get-caller-identity
terraform version
kubectl version --client
helm version
```

**Kiểm tra bắt buộc:**

- Terraform đáp ứng constraint trong repo (`>= 1.12`); kubectl tương thích version EKS trong `terraform.tfvars`. Chọn bộ dev hiện tại, không truyền `env/prod.tfvars`.
- Backend VPC/EKS/Karpenter đang dùng bucket `tfstate-dev-us-east-1-trongpq-eks`, Data Plane dùng `tfstate-dev-us-east-1-trongpq-eks`. Xác định bucket/state thật; sửa remote-state readers để đọc đúng state VPC/EKS. Nếu build mới, thống nhất bucket đã tạo, bật versioning, dùng key riêng mỗi stack. Nếu có state cũ, không đổi bucket/key tùy tiện hoặc tạo state rỗng thay thế.
- EKS `import.tf` chứa cluster/roles có sẵn và account ARN cụ thể. **Build mới không có các resource đó:** đổi tên thành `import.tf.disabled`. **Tiếp tục hạ tầng có sẵn:** chỉ giữ imports khớp account/resource thật và kiểm tra state; không import tài nguyên của dự án khác.
- Trong AWS Secrets Manager, tạo/kiểm tra secret `retailstore-db-secret-1` tại `us-east-1`, JSON gồm `username` và `password` hợp lệ cho cả MySQL/PostgreSQL. Source dùng `data` đọc secret đã tồn tại, không tự tạo nó. Không in password ra terminal/log.
- Trong `values-ui.yaml`, thay domain `stacksimplify.com` bằng domain/Route 53 zone bạn quản lý; nếu chỉ test bằng ALB DNS thì bỏ annotation ExternalDNS hostname. Rà domain filter của ExternalDNS tương ứng.
- Laptop phải kết nối được EKS API endpoint; xác minh đúng account trước mỗi apply. Không cần sửa proxy của terminal agent.

Sửa tên file Checkout (chỉ khi chưa có `values.yaml`):

```powershell
$CheckoutChart = "$Root\Retail_Helm_with_Data_Plane\retail_chart_updates\charts_v1.0.0\retail-store-sample-checkout-chart"
if (!(Test-Path "$CheckoutChart\values.yaml")) {
  Rename-Item -LiteralPath "$CheckoutChart\vaules.yaml" -NewName 'values.yaml'
}
```

## 2. Tạo VPC

```powershell
Set-Location "$Root\EKS_Cluster\01_VPC_tf_manifests"
terraform init
terraform validate
terraform plan
terraform apply
terraform output vpc_id
terraform output private_subnet_ids
```

Review plan của `apply` rồi nhập `yes`. Đạt: VPC/public-private subnets/NAT/route tables được tạo, outputs đúng. Mỗi thư mục Terraform là một stack: init/apply riêng, không apply từng file `.tf`.

## 3. Tạo EKS và add-ons

```powershell
Set-Location "$Root\EKS_Cluster\02_EKS_tf_manifests"
terraform init
terraform validate
terraform plan
terraform apply

$Cluster = (terraform output -raw eks_cluster_name).Trim()
aws eks update-kubeconfig --name $Cluster --region $Region --alias $Cluster
kubectl config current-context
kubectl get nodes
kubectl get pods -n kube-system
kubectl get deployment,daemonset -n kube-system
helm list -n kube-system
aws eks list-addons --cluster-name $Cluster --region $Region
kubectl top nodes
```

Đạt: managed nodes Ready, Deployment/DaemonSet đủ replica, add-ons không lỗi; `kubectl top` có dữ liệu.

- Với từng add-on: `aws eks describe-addon --cluster-name $Cluster --addon-name <ten-addon> --region $Region`; cần `ACTIVE` và không health issues.
- Cluster tạo xong nhưng Helm provider lỗi token hết hạn: chạy lại plan/apply với phiên SSO còn hiệu lực. Source đang dùng token từ `aws_eks_cluster_auth`; không dùng lại saved plan cũ chứa token. Nếu lần đầu provider không bootstrap được cùng cluster, có thể tách một lần bằng `terraform apply -target=aws_eks_node_group.private_nodes` (kéo theo cluster/dependencies), rồi bắt buộc chạy full plan/apply.
- Lỗi OpenAPI 503 của LBC: xem [runbook](EKS_Cluster/TROUBLESHOOT_METRICS_SERVER_LBC.md); giữ validation bật, kiểm tra phiên bản Metrics Server đã pin.

## 4. Cài Karpenter controller

```powershell
Set-Location "$Root\EKS_Cluster\03_Karpenter_tf_manifests"
terraform init
terraform validate
terraform plan
terraform apply
kubectl rollout status deployment/karpenter -n kube-system --timeout=300s
terraform output -raw karpenter_node_role_name
```

Nếu pull chart OCI báo lỗi xác thực, đăng nhập public ECR rồi chạy lại:

```powershell
$EcrToken = aws ecr-public get-login-password --region us-east-1
if ($LASTEXITCODE -ne 0) { throw 'Không lấy được token ECR' }
$EcrToken | helm registry login --username AWS --password-stdin public.ecr.aws
Remove-Variable EcrToken
```

## 5. Tạo EC2NodeClass và NodePools

Sửa `1_ec2nodeclass.yaml`: role **name** từ bước 4, cluster tags/subnet/SG selectors đúng VPC. AZ trong hai NodePool phải có subnet tương ứng.

```powershell
Set-Location "$Root\EKS_Cluster\04_Karpenter_k8s_manifests"
kubectl apply -f .\1_ec2nodeclass.yaml
kubectl wait --for=condition=Ready ec2nodeclass/default-ec2nodeclass --timeout=300s
kubectl apply -f .\2_nodepool_ondemand.yaml
kubectl apply -f .\3_nodepool_spot.yaml
kubectl wait --for=condition=Ready nodepool/ondemand-nodepool --timeout=300s
kubectl wait --for=condition=Ready nodepool/spot-nodepool --timeout=300s
kubectl get nodepools
```

Chưa có node mới là bình thường: Karpenter chỉ cấp khi có Pod cần capacity. Các values app hiện chọn On-Demand.

## 6. Tạo AWS Data Plane

```powershell
Set-Location "$Root\Retail_AWS_DataPlane\AWS_Data_Plane_tf_manifests"
terraform init
terraform validate
terraform plan
terraform apply
terraform output -raw catalog_rds_endpoint
terraform output -raw orders_rds_postgresql_endpoint
terraform output -raw checkout_redis_endpoint
terraform output -raw orders_sqs_queue_url
aws dynamodb describe-table --table-name Items --region us-west-2 --query Table.TableStatus
aws rds describe-db-instances --region $Region --query 'DBInstances[].{Name:DBInstanceIdentifier,Status:DBInstanceStatus}'
```

Đạt: hai RDS `available`, DynamoDB `ACTIVE`, Redis được tạo, SQS/Pod Identity associations có trong state. Tránh `terraform output -json` toàn bộ vì repo có debug outputs chứa credential.

## 7. Điền values và cài ứng dụng

Trong `Retail_Helm_with_Data_Plane/retail_values_HELM_aws_dataplane`:

| File | Giá trị cần khớp AWS thật |
|---|---|
| `values-catalog.yaml` | MySQL endpoint, `catalogdb`, secret name/region; `mysql.create: false` |
| `values-order.yaml` | PostgreSQL endpoint kèm `:5432`, `ordersdb`, secret, queue name; PostgreSQL/RabbitMQ local tắt |
| `values-cart.yaml` | `Items`, region/endpoint `us-west-2`; DynamoDB local tắt |
| `values-checkout.yaml` | Redis endpoint kèm `:6379`, Orders URL `http://orders`; Redis local tắt |
| `values-ui.yaml` | Backend URLs `catalog/carts/checkout/orders`, domain bạn quản lý hoặc bỏ annotation DNS |

Giữ namespace `default` và release names bên dưới để khớp ServiceAccount associations. Dùng Catalog/Orders v2, ba chart còn lại v1. Có HPA/PDB trong custom values; tối thiểu 15 Pod app nên cần đủ capacity/quota.

```powershell
$Charts = "$Root\Retail_Helm_with_Data_Plane\retail_chart_updates"
$Values = "$Root\Retail_Helm_with_Data_Plane\retail_values_HELM_aws_dataplane"
$Apps = @(
  @{Name='catalog'; Chart="$Charts\charts_v2.0.0\retail-store-sample-catalog-chart"; Values="$Values\values-catalog.yaml"},
  @{Name='carts'; Chart="$Charts\charts_v1.0.0\retail-store-sample-cart-chart"; Values="$Values\values-cart.yaml"},
  @{Name='orders'; Chart="$Charts\charts_v2.0.0\retail-store-sample-orders-chart"; Values="$Values\values-order.yaml"},
  @{Name='checkout'; Chart="$Charts\charts_v1.0.0\retail-store-sample-checkout-chart"; Values="$Values\values-checkout.yaml"},
  @{Name='ui'; Chart="$Charts\charts_v1.0.0\retail-store-sample-ui-chart"; Values="$Values\values-ui.yaml"}
)
foreach ($App in $Apps) {
  helm lint $App.Chart -f $App.Values
  if ($LASTEXITCODE -ne 0) { throw "Lint lỗi: $($App.Name)" }
}
foreach ($App in $Apps) {
  helm upgrade --install $App.Name $App.Chart -n default -f $App.Values --atomic --wait --timeout 15m
  if ($LASTEXITCODE -ne 0) { throw "Deploy lỗi: $($App.Name)" }
}
```

Nếu một release timeout, kiểm tra nguyên nhân trước khi chạy lại; không gỡ database để khắc phục lỗi Pod.

**Rollback với Helm 3:** `--atomic` tự bật `--wait` (giữ cờ tường minh cho dễ đọc). Upgrade thất bại sẽ thử rollback release đó về revision thành công trước; cài mới thất bại thì Helm gỡ bản cài lỗi. Rollback cũng có thể lỗi nên vẫn cần xem status/history.

Phạm vi là **một release**, không phải giao dịch cho cả năm app: nếu Orders lỗi sau Catalog/Carts đã nâng cấp thành công, Orders được rollback và script dừng; Catalog/Carts vẫn ở bản mới. Không rollback dữ liệu/migration DB hoặc tự xử lý lỗi `helm test` chạy sau upgrade. CI/CD cần smoke test và kế hoạch rollback/promotion các service tương thích nếu muốn xử lý lỗi toàn luồng.

Tham khảo: [Helm 3 upgrade](https://docs.helm.sh/docs/v3/helm/helm_upgrade/).

## 8. Test sau triển khai

```powershell
helm list -n default
kubectl get pods,svc,ingress,hpa,pdb -n default
kubectl get nodeclaims
kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type
kubectl get secretproviderclasspodstatus -n default
kubectl get secrets catalog-db orders-db -n default
foreach ($App in $Apps) {
  helm test $App.Name -n default --logs
  if ($LASTEXITCODE -ne 0) { throw "Helm test lỗi: $($App.Name)" }
}
kubectl get ingress ui -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Mở `http://<ALB-hostname>` → xem Catalog → thêm giỏ hàng → checkout/tạo đơn. Kiểm tra không có lỗi credential/DB trong logs. Helm test kiểm tra kết nối cơ bản, chưa chứng minh toàn bộ nghiệp vụ hoặc persistence; kiểm tra dữ liệu bằng công cụ AWS/quyền DB phù hợp nếu cần.

Đạt: app Ready, HPA có metrics, secret mount thành công, ALB có địa chỉ/target healthy, thao tác UI thành công. Không có Pod MySQL/PostgreSQL/Redis/DynamoDB local vì custom values đã tắt. Kiểm tra DNS nếu đã cấu hình domain. PVC test EBS CSI chỉ cần nếu dùng workload có volume; các database AWS không dùng EBS CSI của EKS.

## 9. Khi lỗi

```powershell
kubectl get events -A --sort-by=.metadata.creationTimestamp
kubectl describe pod <pod-name> -n default
kubectl logs <pod-name> -n default --tail=100
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100
```

- Pending: kiểm tra requests, NodePool/AZ/quota và Karpenter.
- Secret mount lỗi: kiểm tra secret name/region, namespace/SA, Pod Identity/IAM và CSI.
- DB timeout: endpoint/port và SG node → SG DB; lỗi authentication: kiểm tra credential/database name.
- AccessDenied: kiểm tra SSO identity/role của thao tác hoặc Pod Identity của ứng dụng.

Guide được đối chiếu source và lint local: Catalog/Orders/Carts/UI đạt; Checkout cần sửa tên `vaules.yaml` trước. Chưa chạy apply hoặc kiểm thử AWS trong lần viết guide này.
