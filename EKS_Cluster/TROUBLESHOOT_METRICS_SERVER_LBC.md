# Metrics Server làm Helm cài AWS Load Balancer Controller thất bại

Ghi nhận 15/10/2026: cluster `retail-dev-eksdemo1`, region `us-east-1`, cấu hình Kubernetes 1.34.

## 1. Kết luận và trạng thái

Terraform và Helm CLI đều lỗi khi validate manifest LBC:

```text
unable to build kubernetes objects from release manifest
error validating data: the server is currently unable to handle the request
```

Đã xác nhận:

- OpenAPI v2 JSON trả **200**, Protobuf trả **503**.
- API server log báo schema có thuộc tính không hợp lệ: `ArbitraryKeys, SchemaProps, SwaggerSchemaProps`.
- Các kiểu bị lỗi gồm `NodeMetrics`, `PodMetrics`, `ContainerMetrics` của Metrics API.

Bằng chứng khớp [issue Metrics Server #1868](https://github.com/kubernetes-sigs/metrics-server/issues/1868): báo cáo lỗi khi nâng 0.8.1 → 0.9.0 trên EKS 1.35. Đây là báo cáo upstream; không chứng minh mọi bản 0.9.x đều lỗi hoặc mọi bản 0.8.1 đều an toàn trên mọi cluster.

**Trạng thái lúc viết:** `terraform.tfvars` đã ghim `metrics_server_addon_version = "v0.8.1-eksbuild.18"`; LBC giữ `disable_openapi_validation = false`. Đây là cấu hình trên đĩa, chưa xác nhận bản này đã apply thành công hoặc Protobuf đã trở lại 200. Chưa đánh dấu sự cố đã xử lý xong.

## 2. Tại sao Metrics Server liên quan đến LBC?

LBC không cần số liệu CPU/RAM của Metrics Server để cài đặt. Hai thành phần liên quan qua **OpenAPI schema chung của Kubernetes API server**:

```text
Metrics Server đăng ký Metrics API qua APIService
    → schema Metrics API được tổng hợp vào OpenAPI của cluster
    → schema tổng hợp chứa thuộc tính không hợp lệ
    → chuyển/đọc schema dạng Protobuf thất bại, trả 503
    → Helm không validate được manifest
    → cài LBC thất bại
```

JSON 200 chỉ chứng minh gửi được tài liệu JSON, không chứng minh nội dung hợp lệ với bộ chuyển đổi Protobuf. [Kubernetes OpenAPI handler](https://github.com/kubernetes/kube-openapi/blob/master/pkg/handler/handler.go) ghi `Error in OpenAPI handler` khi lấy/tạo schema lỗi và có thể trả 503.

APIService `Available=True` và Pod Running cũng không chứng minh schema tổng hợp hợp lệ. Vì thế các kiểm tra trạng thái ban đầu chưa phát hiện lỗi này.

## 3. Quá trình troubleshoot

| Kiểm tra | Kết quả thực tế | Ý nghĩa |
|---|---|---|
| APIService | Người dùng không thấy False | Chưa có lỗi availability rõ ràng; chưa loại trừ schema |
| kubectl get --raw=/openapi/v2 | Thành công | Một cách lấy schema hoạt động; chưa kiểm tra Protobuf |
| Helm CLI với --validate, chart 3.6.0 | Cùng lỗi Terraform | Không phải lỗi riêng Helm provider |
| OpenAPI v3, API discovery | 200 | Các endpoint này truy cập được |
| ConfigMap server dry-run strict | Thành công | Core API hoạt động |
| LBC manifest server dry-run verbose | Một số resource đạt; /openapi/v2 trả 503; exit 1 | Chỉ ra request bị lỗi |
| Cùng URL, đổi Accept header | JSON 200 / Protobuf 503 | Khoanh vùng theo định dạng schema |
| CloudWatch API server logs | Invalid properties trong Metrics API | Đầu mối trực tiếp là schema liên quan Metrics Server |

`404 Not Found` trước dry-run tạo resource mới là bình thường. `created (server dry run)` không lưu resource vào cluster. Exit code 1 nghĩa là toàn bộ bài test chưa đạt.

## 4. Lệnh chẩn đoán

Chạy bằng PowerShell, kubeconfig phải trỏ đúng cluster.

### 4.1. Kiểm tra API

```powershell
kubectl config current-context
kubectl get apiservices
kubectl get pods -n kube-system
kubectl get --raw='/openapi/v3' --request-timeout=30s -v=6 > $null
kubectl api-resources --cached=false --request-timeout=30s -v=6 > $null
```

### 4.2. So sánh JSON / Protobuf

Terminal A:

```powershell
kubectl proxy --address=127.0.0.1 --port=8001
```

Terminal B:

```powershell
curl.exe --silent --show-error --max-time 30 -H "Accept: application/json" -o NUL -w "JSON: %{http_code}\n" http://127.0.0.1:8001/openapi/v2
curl.exe --silent --show-error --max-time 30 -H "Accept: application/com.github.proto-openapi.spec.v2@v1.0+protobuf" -o NUL -w "Protobuf: %{http_code}\n" http://127.0.0.1:8001/openapi/v2
```

Trước sửa: 200 / 503. Sau sửa cần cả hai 200. Dừng proxy bằng Ctrl+C khi xong.

### 4.3. Đọc API server logs

Source `1_main.tf` đã bật log `api`:

```powershell
aws logs tail /aws/eks/retail-dev-eksdemo1/cluster --region us-east-1 --since 1h --log-stream-name-prefix kube-apiserver --filter-pattern '"Error in OpenAPI handler"' --format short
```

Nếu chưa thấy, tái hiện request Protobuf và chờ vài phút rồi tìm lại. [AWS: log control plane có thể đến chậm](https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html).

### 4.4. Tái hiện trên manifest LBC

```powershell
helm template lbc-diagnostic aws-load-balancer-controller --repo https://aws.github.io/eks-charts --version 3.6.0 --namespace kube-system --set clusterName=retail-dev-eksdemo1 --set region=us-east-1 --set vpcId=vpc-02434db115d896e78 --set serviceAccount.create=true --set serviceAccount.name=aws-load-balancer-controller | Out-File -Encoding utf8 .\lbc-diagnostic-rendered.yaml
```

Chỉ chạy tiếp khi render thành công. Thay cluster/VPC/version nếu môi trường khác. Không apply file này thật vì tên release khác Terraform.

```powershell
kubectl apply --dry-run=server --validate=strict -n kube-system -f .\lbc-diagnostic-rendered.yaml -v=6 2> .\lbc-validation.log
$LASTEXITCODE
Select-String -Path .\lbc-validation.log -Pattern 'Response|error|failed|unable'
```

Render chỉ để lấy file; bước kubectl vẫn bật validation. Dry-run không cài CRD mới: nếu báo thiếu CRD, chẩn đoán riêng, không coi mọi lỗi là sự cố Protobuf.

## 5. Cách sửa có kiểm soát

### Bước 1 — Xác định phiên bản

```powershell
aws eks describe-addon --cluster-name retail-dev-eksdemo1 --addon-name metrics-server --region us-east-1 --query "addon.{Version:addonVersion,Status:status,Issues:health.issues}" --output json
kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[*].image}'
aws eks describe-addon-versions --addon-name metrics-server --kubernetes-version 1.34 --region us-east-1 --query "addons[].addonVersions[].addonVersion" --output text
```

Chọn bản đã sửa lỗi và kiểm thử. Nếu chưa có, đánh giá rollback về bản trước lỗi; 0.8.1 là ứng viên theo issue upstream, phải có trong danh sách AWS và kiểm thử trên cluster này. Ghi lại bản cũ để có phương án phục hồi.

### Bước 2 — Ghim phiên bản trong Terraform

Source `9_metric_server-eks-addon.tf` hiện đã có:

```hcl
variable "metrics_server_addon_version" {
  description = "Pinned Metrics Server EKS add-on version"
  type        = string
}

# Trong resource aws_eks_addon.metrics_server:
addon_version = var.metrics_server_addon_version
```

Trong repo, `terraform.tfvars` hiện đặt:

```hcl
metrics_server_addon_version = "v0.8.1-eksbuild.18"
```

Xác nhận bản này có trong kết quả AWS ở bước 1 trước khi apply; không đoán hậu tố eksbuild cho môi trường khác. Data source `metrics_server_latest` còn lại chỉ phục vụ output; output “latest” không phải phiên bản đang chạy. Không sửa image trực tiếp của add-on do AWS quản lý.

### Bước 3 — Sửa Metrics Server trước

Trong `02_EKS_tf_manifests`:

```powershell
terraform validate
terraform plan -target=aws_eks_addon.metrics_server -out=metrics-recovery.tfplan
terraform apply metrics-recovery.tfplan
kubectl rollout status deployment/metrics-server -n kube-system --timeout=300s
kubectl top nodes
```

Đọc plan trước khi apply. `-target` dành riêng cho khôi phục lần này, không dùng thường ngày. Metrics/HPA dựa trên CPU/RAM có thể gián đoạn ngắn trong rollout.

### Bước 4 — Xác nhận và cài LBC

1. Add-on ACTIVE, không health issues; version/image đúng bản đã chọn.
2. JSON và Protobuf đều 200; request mới không tạo lại lỗi schema.
3. Giữ `disable_openapi_validation = false`.
4. Tạo plan đầy đủ mới:

```powershell
terraform plan -out=eks-fixed.tfplan
terraform apply eks-fixed.tfplan
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=300s
helm list -n kube-system
```

Nếu Protobuf vẫn 503, lấy log mới và kiểm tra schema/phiên bản; gửi AWS Support nếu lỗi vẫn thuộc quá trình tổng hợp schema của EKS. Không đánh dấu fixed chỉ vì Metrics Server Running.

## 6. Những hướng không sửa nguyên nhân này

- **Thêm cert-manager:** quản lý chứng chỉ webhook, không sửa schema Metrics API. Chart LBC mặc định không bắt buộc cert-manager. [Tài liệu chart](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/helm/aws-load-balancer-controller/README.md).
- **Tắt OpenAPI validation:** có thể vượt qua bước lỗi nhưng schema vẫn hỏng; không chọn làm mặc định production.
- **Chỉ đổi Helm CLI/token Terraform:** curl đã tái hiện lỗi độc lập với cả hai.
- **Apply saved plan cũ:** không lấy thay đổi mới trong file .tf. Trong sự cố đã thấy plan lưu `disable_openapi_validation = false` và source từng comment workaround; false ở tùy chọn này nghĩa là validation BẬT.
- **Xóa APIService/CRD hoặc dựng lại cluster để thử:** chưa có cơ sở, có thể gây gián đoạn/mất tài nguyên liên quan.

Bài học: ghim phiên bản add-on/chart đã kiểm thử; kiểm tra cả chức năng và schema API sau nâng cấp. Lỗi hiện ở release LBC không đồng nghĩa nguyên nhân nằm trong LBC.
