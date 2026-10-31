# Cảnh báo Grafana → SNS → email

Terraform tạo topic `grafana-<cluster-name>-alerts`, các email subscription và giới hạn quyền `sns:Publish` của role AMG vào đúng topic. Không cần thêm topic policy riêng cho role cùng account với cấu hình hiện tại.

## 1. Khai báo người nhận

Trong `OPENTELEMTRY_k8s_manifests/terraform.tfvars`, điền email thật:

```hcl
grafana_alert_email_addresses = ["your-email@example.com"]
```

Mặc định `[]`: chỉ tạo topic, chưa có người nhận. Không dùng email ví dụ khi apply. Mỗi môi trường dùng danh sách người nhận riêng.

## 2. Plan và apply

Trước khi chạy, kiểm tra AWS SSO/profile, backend và remote state VPC/EKS đúng môi trường. Các giá trị trong source vẫn cần khớp hạ tầng đã triển khai.

```powershell
Set-Location D:\Udemy\retail-eks-prj\Observability\OPENTELEMTRY_k8s_manifests
terraform init
terraform validate
terraform plan -out=sns-alerts.tfplan
# Đọc toàn bộ plan: đây là plan của cả stack Observability, không chỉ SNS.
terraform apply sns-alerts.tfplan
terraform output -raw grafana_alert_topic_arn
terraform output -raw grafana_alert_region
```

Mở email từ AWS SNS, bấm **Confirm subscription**. Chưa xác nhận thì chưa nhận được alert. Subscription còn pending cũng có hạn chế khi Terraform xóa nó.

## 3. Nối Grafana với SNS

Đăng nhập AMG bằng user SSO có quyền cấu hình alerting:

1. Vào **Alerting → Contact points → Add contact point**.
2. Đặt tên `sns-retail-alerts`, chọn **AWS SNS**.
3. Điền Topic ARN và Region từ output ở bước 2; chọn message format `text`.
4. Dùng credentials của workspace IAM role; để trống Access Key, Secret Key, Profile và Assume Role ARN. Source đã gắn quyền publish vào role AMG.
5. Bấm **Test** và kiểm tra email, rồi lưu contact point.

Terraform trong stack này chưa tạo contact point/notification policy trong Grafana. Các thao tác bước 3–4 là cấu hình một lần trong UI; IAM policy và `notification_destinations = ["SNS"]` không tự tạo chúng.

## 4. Nối alert thực tế và kiểm tra

1. Tạo alert rule dùng datasource AMP đã cấu hình. Để thử, có thể dùng PromQL `vector(1)` và điều kiện lớn hơn `0`, pending period ngắn.
2. Gắn label `notify=sns` cho rule.
3. Trong **Notification policies**, thêm route khớp `notify=sns` đến contact point `sns-retail-alerts` (giữ nguyên các route khác).
4. Chờ rule chuyển **Firing**, hết thời gian group wait và xác nhận email đến. Test contact point chỉ kiểm tra kênh gửi, bước này kiểm tra cả rule và routing.
5. Xóa/tắt rule thử, thay bằng rule cần vận hành. Nếu muốn kiểm tra thông báo resolved, cho rule trở về Normal và đảm bảo không tắt resolved notifications.

Nếu không nhận email: kiểm tra subscription đã Confirmed, đúng Topic ARN/Region, quyền role AMG, trạng thái rule và notification policy.

Tài liệu: [Grafana SNS contact point](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-amazon-sns/), [AWS SNS subscription](https://docs.aws.amazon.com/us_en/sns/latest/dg/sns-create-subscribe-endpoint-to-topic.html).
