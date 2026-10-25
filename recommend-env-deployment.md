# Guide: SSM, RDS MySQL và CI/CD riêng DEV/PROD

**Đây là kế hoạch implement theo yêu cầu mới; chưa sửa/apply hạ tầng.** Dùng SSM ở cả DEV và PROD; người dùng truy cập DB PROD chỉ được đọc. RDS chỉ dùng MySQL. Không triển khai VPN.

## 1. Phân quyền SSO và triển khai

Tên `dev`, `dev-ops`, `prod-role` được dùng theo danh tính bạn cung cấp. Chưa mặc định đây là ba AWS account khác nhau: cần ánh xạ đúng **SSO profile → permission set/role ARN → account ID** bằng `aws sts get-caller-identity --profile <profile>`.

| Danh tính | Quyền đề xuất |
|---|---|
| `dev` | SSM vào node Managed Node Group DEV; đọc/ghi dữ liệu test bằng SQL user dev; không deploy hạ tầng |
| `dev-ops` | Danh tính hiện dùng viết và triển khai Terraform DEV; không được apply/deploy PROD |
| `prod-role` | Danh tính được phép triển khai PROD; trong CI/CD chỉ được assume sau điều kiện phát hành/phê duyệt |
| Người được cấp quyền xem DB PROD | SSO user được gán permission set truy cập PROD: SSM tới node Managed Node Group PROD + credential SQL chỉ đọc |

**Deploy PROD và SSM PROD là hai quyền cấp riêng**, có thể gán cho cùng một SSO user nếu cần. Chỉ biết endpoint/password hoặc có SSO dev không đủ truy cập PROD. DEV cho nhóm dev thao tác dữ liệu test thuận tiện nhưng vẫn yêu cầu SSO, SQL credential và mạng private; không mở database công khai.

- Terraform không tạo lại SSO users. Nếu permission sets do repo này quản lý thì tách vào stack identity/bootstrap; nếu do tổ chức quản lý thì chỉ nhận account IDs/role ARNs.
- Local dùng SSO profile qua `AWS_PROFILE`, không hardcode profile trong provider. Provider đặt `allowed_account_ids`; nếu các role cùng account, phải phân quyền bằng IAM/trust policy, account ID không phân biệt được role.
- CI/CD dùng OIDC, không dùng phiên SSO tương tác hoặc lưu SSO token. Nếu `prod-role` là tên permission set SSO, tạo role CI tương ứng trong account prod với phạm vi triển khai tương đương; không sửa trực tiếp role `AWSReservedSSO_*` để thêm OIDC.
- Role chỉ xem DB PROD không được đọc secret master/runtime/migration hoặc assume role deploy. Nếu một người có cả quyền deploy và quyền xem DB, dùng session/role đúng mục đích. Role có quyền sửa workload/IAM có thể có khả năng nâng quyền, nên không coi SQL read-only là giới hạn tuyệt đối cho quản trị viên hạ tầng.

## 2. SSM qua node Managed Node Group của từng môi trường

```text
Windows → SSO/IAM → SSM tunnel → node Managed Node Group DEV/PROD
                                  → RDS MySQL private cùng môi trường:3306
GUI     → localhost:local-port    → tunnel trên
```

**Tái sử dụng EC2 node hiện có; không tạo EC2 quản trị riêng hoặc stack `db-access`:**

1. Trong stack EKS, bổ sung quyền SSM (ví dụ `AmazonSSMManagedInstanceCore`) vào **node IAM role của Managed Node Group**, không phải role Karpenter/controller. Kiểm tra SSM Agent đã cài, đang chạy và node báo `Online`; nếu AMI chưa đáp ứng, cấu hình qua launch template/bootstrap và rollout node có kiểm soát.
2. Node ở private subnet, kết nối HTTPS tới SSM qua NAT/VPC endpoints và DNS hiện có. Không mở SSH 22, không thêm public IP. Không siết egress node theo kiểu máy DB chuyên dụng làm hỏng workload EKS.
3. Data Plane cho phép TCP 3306 từ SG thực sự gắn với node Managed Node Group **cùng env**; kiểm tra rule hiện có trước khi thêm. Không gán SG dev cho DB prod hoặc dùng node dev để nối prod.
4. IAM/permission set SSO giới hạn `StartSession` theo node đúng account/cluster/node group và document được phép; chỉ quản lý phiên của mình. Dùng tag **thực sự có trên EC2**, không giả định tag EKS node group tự truyền xuống instance; nếu cần tag riêng thì dùng launch template. Chặn quyền shell/Run Command/tagging cho role chỉ truy cập DB.
5. Vì node chạy workload và có đường mạng rộng, dùng **custom SSM Session document** theo mẫu remote-host forwarding, giới hạn host đúng endpoint MySQL của env và port cố định 3306. Role DB-access không được sửa document hoặc gọi document forwarding tùy ý; tránh tunnel tới metadata/API/nội bộ khác. Chỉ giới hạn instance ID hoặc SQL read-only chưa đủ bảo vệ node.
6. Script kết nối nhận env/profile → tìm EC2 đang chạy thuộc đúng Managed Node Group → kiểm tra SSM Online → mở tunnel bằng document đã giới hạn. Local cần AWS CLI + Session Manager plugin. DBeaver/Workbench kết nối local port; cấu hình TLS/certificate database phù hợp.
7. Không lưu DB password lên node; dùng SQL user/secret người dùng riêng. Node có thể bị thay khi update/repair/scale: tunnel sẽ ngắt, script phải tìm node mới và kết nối lại, không hardcode instance ID.

Document/SSO access policy quản lý trong phần identity/access dùng chung cấu hình env; node role/Agent thuộc EKS; SG DB thuộc Data Plane. Tách ownership, không quản lý cùng rule ở hai nơi.

### PROD read-only được bảo đảm ở đâu?

**SSM chỉ mở kết nối TCP, không biết câu SQL nào là đọc/ghi.** Tạo MySQL user mới chỉ có `SELECT` trên database được phép; thêm `SHOW VIEW` nếu cần xem views. Không cấp DML/DDL, `GRANT OPTION`, quyền admin hoặc routine có khả năng ghi. Không dùng user master hoặc runtime qua tunnel PROD.

| Loại user DB | DEV | PROD |
|---|---|---|
| Human/test | Một bộ credential/người, xem và đọc/ghi cả `catalogdb` và `ordersdb` theo quyền test | Một bộ credential/người, chỉ SELECT cả `catalogdb` và `ordersdb` |
| Application runtime | Quyền nghiệp vụ cần thiết | Quyền nghiệp vụ cần thiết, vẫn có thể ghi |
| Migration | DDL cần thiết | DDL riêng cho job migration được duyệt |

Không bật read-only toàn bộ RDS vì ứng dụng vẫn cần ghi. IAM `ReadOnlyAccess` không tự tạo SQL read-only. Dùng CloudTrail cho sự kiện phiên và DB audit cho câu SQL; tunnel SSM không ghi nội dung SQL vào session logs.

## 3. Chỉ dùng RDS MySQL

**Chốt thiết kế: một RDS MySQL instance cho mỗi môi trường, dùng chung cho các database của môi trường đó.** DEV và PROD không dùng chung instance. Tổng cộng hai RDS instances chính (chưa tính standby nếu bật Multi-AZ).

```text
RDS MySQL DEV                 RDS MySQL PROD
├── catalogdb → user Catalog  ├── catalogdb → user Catalog
└── ordersdb  → user Orders   └── ordersdb  → user Orders
```

Catalog/Orders cùng env dùng chung endpoint/port nhưng khác database name, user và secret. Mỗi runtime user chỉ có quyền trên database của service mình; user người dùng PROD chỉ SELECT trên database được cấp. Redis/DynamoDB/SQS giữ vai trò riêng.

**Khi người dùng đăng nhập GUI:** dùng một host và một bộ username/password của mình để thấy cả `catalogdb` lẫn `ordersdb`, nhờ GRANT trên cả hai database. Không cần hai connection với hai credential riêng cho hai DB. DEV/PROD vẫn có endpoint và credential riêng; “một bộ credential” không có nghĩa mọi người dùng chung tài khoản, cũng không áp dụng cho hai ứng dụng Catalog/Orders.

**Đánh đổi:** tiết kiệm instance nhưng chia sẻ CPU/RAM/I/O, lịch bảo trì và phạm vi ảnh hưởng khi RDS lỗi. Tách database không tạo cô lập tài nguyên; backup/khôi phục RDS ở cấp instance cần tính đến cả hai database.

**Điểm bắt buộc xử lý:** Orders hiện dùng PostgreSQL; chart local có điều kiện `provider == postgres`, helper PostgreSQL và secret mount tương ứng. Không thể chỉ đổi `engine = "mysql"` hoặc values là xong.

1. Bổ sung/kiểm tra hỗ trợ MySQL trong code Orders: JDBC driver/URL, datasource/provider, SQL/migrations, kiểu dữ liệu và transaction; build image riêng và test với MySQL. Tài liệu upstream hiện mô tả Orders dùng PostgreSQL; chưa xác nhận image `1.3.0` hỗ trợ MySQL.
2. Sửa chart Orders: configmap/helper, Deployment, SecretProviderClass, values và template database local còn phụ thuộc PostgreSQL. Giữ secret username/password nhưng trỏ credential MySQL mới.
3. Terraform gọi module RDS MySQL **một lần mỗi env**, cấu hình identifier/sizing/backup/HA ở cấp instance. Tạo `catalogdb`, `ordersdb`, SQL users và GRANT qua bootstrap/migration job có đường mạng tới RDS; `aws_db_instance.db_name` chỉ khai báo một database ban đầu, không tạo được cả danh sách. Secret runtime vẫn riêng từng service/env; không đưa master credential vào Pod. Cập nhật Helm: endpoint chung, database/secret riêng; bỏ cổng 5432 sau chuyển đổi.
4. Với DEV đã tồn tại: đánh giá dùng RDS MySQL Catalog hiện có làm instance chung, tạo thêm `ordersdb`, migrate/test dữ liệu PostgreSQL rồi chuyển Orders. Giữ PostgreSQL để rollback trong thời gian thống nhất; chỉ xóa sau backup và xác nhận. Không đổi engine trực tiếp trên resource PostgreSQL cũ. PROD tạo một instance chung riêng bằng state/config prod.

Nguồn: [Orders upstream README](https://github.com/aws-containers/retail-store-sample-app/blob/main/src/orders/README.md). Phần chuyển engine là thay đổi cả application và infrastructure.

### Dung lượng và scaling của instance chung

- Cả hai database dùng chung storage của RDS; không chia cứng dung lượng riêng từng DB trong thiết kế này.
- Terraform khai báo `allocated_storage` (GiB ban đầu) và `max_allocated_storage` (trần autoscaling), parameterize theo env. Ví dụ minh họa: `20` và `100` GiB; không phải sizing production đã chốt.
- Khi bật autoscaling, AWS quyết định thời điểm/mức tăng theo điều kiện dịch vụ, trong trần bạn đặt; ứng dụng không phải gọi API để tăng disk. Storage tăng không tự giảm; tăng storage không tự tăng CPU/RAM.
- CPU/RAM của RDS MySQL thông thường do `instance_class` quyết định; nâng class là thay đổi hạ tầng có kế hoạch, không do HPA/Karpenter điều khiển.
- Theo dõi free storage, CPU, memory, I/O và cảnh báo khi gần trần. Khi hết trần cần review/tăng giới hạn; autoscaling không bảo đảm tránh đầy disk trong mọi đợt nạp dữ liệu lớn.
- Source hiện tại: MySQL có `allocated_storage = 20`, chưa khai báo `max_allocated_storage`; PostgreSQL cũ có `20`/`100`. Cần cấu hình autoscaling rõ ràng cho MySQL đích, không suy ra từ cấu hình PostgreSQL.

Nguồn: [AWS RDS storage autoscaling](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.Autoscaling.html).

## 4. Cấu trúc code ít lặp

```text
infra/
  modules/
    vpc/                      # Tái sử dụng module đang có
    rds-mysql/                # Một instance/env, chứa catalogdb + ordersdb
  stacks/                     # Mỗi stack có state riêng
    vpc/
    eks/
    karpenter/
    karpenter-config/         # Apply sau controller/CRDs
    identity-access/         # SSO access policies + SSM document giới hạn DB đích
    dataplane/               # MySQL, Redis, DynamoDB, SQS, IAM workload
  environments/
    dev/                     # <stack>.tfvars + <stack>.backend.hcl
    prod/                    # Chỉ khác config, không copy resource code
helm/
  charts/                    # Một chart/service được version hóa
  values/common/             # <service>.yaml
  values/dev/
  values/prod/
.github/workflows/
  infra.yml                  # Workflow chung: environment + stack
  app.yml                    # Build một lần, promote artifact
scripts/                     # Script chung nhận environment
```

Các stack là code chung cho hai môi trường; chỉ tạo module khi cần tái sử dụng, không thêm lớp wrapper cho mọi file. DEV/PROD dùng VPC, cluster, database, state riêng; namespace không phải ranh giới cô lập duy nhất.

| Parameterize | Nội dung |
|---|---|
| Identity | Environment, account ID đích, region, IAM deployment/access roles; không chứa SSO token |
| Backend | Bucket/key/region/locking từng env và stack; remote-state references cùng env |
| EKS/VPC | CIDR, tên, API access, versions, sizing, subnet/SG selectors |
| Karpenter | Cluster tags, node role, NodePool limits; bỏ hardcode `retail-dev-*` |
| Data Plane | Một MySQL identifier/env; database names/users/secrets theo service; sizing/HA/backup chung cấp instance; table/queue/cache names, DynamoDB region |
| Quyền workload | Secret ARN riêng service/env, namespace + ServiceAccount + Pod Identity khớp nhau |
| SSM người dùng | Node group/tag selector, SSO principals/permission sets, document ARN, DB endpoints được phép và SQL read-only secret PROD |
| Helm | Endpoints, secret names, domain/TLS, resource/HPA, chart/image digest |

Backend dùng partial config `backend "s3" {}` và `init -backend-config=...`; không nội suy biến Terraform trong backend. Repo đang có bucket `...trongpq-eks` và `...jpjtof`: xác minh state thật trước khi chuyển. Các tfvars dev/prod hiện có chưa thay thế việc tách backend/IAM. Không tự nạp file `terraform.tfvars` còn hardcode dev vào job prod.

## 5. CI/CD và thứ tự triển khai

1. Bootstrap backend/OIDC/deployment roles bằng danh tính được tổ chức cho phép. Tách quyền bootstrap với deploy thường ngày; không cấp `dev-ops` quyền prod chỉ để tiện tạo role.
2. DEV deploy bằng quyền `dev-ops`; PROD chỉ bằng quyền triển khai `prod-role`/role CI tương ứng, có protected environment và approval. OIDC trust khớp repo/environment; dev không được assume prod.
3. Mỗi job dùng working directory sạch, chọn đúng backend và var-file; validate → plan → review → apply đúng saved plan. Khóa/concurrency theo env/stack. Không dùng cùng thư mục đã init để chạy đồng thời hai env.
4. Dependencies: VPC → EKS → Karpenter controller → NodeClass/NodePool. Data Plane đọc VPC/EKS outputs; identity-access đọc EKS/Data Plane outputs để giới hạn node và endpoint trong SSM document. Không để EKS/Data Plane đọc ngược identity-access tạo vòng phụ thuộc. Bootstrap deployment roles vẫn làm trước các stack này.
5. Build/test image một lần → DEV → kiểm thử → approval → PROD với **cùng digest**, values khác nhau. Chart hỗ trợ digest; endpoint lấy từ outputs đúng env. Migration dùng user/job riêng, không dùng user human read-only.
6. Runner deploy Helm/migration cần đường mạng vào API EKS/DB đúng env; prod private API cần runner/CodeBuild có kết nối VPC. Không biến node làm đầu tunnel SSM thành runner dùng chung hai môi trường.

**Thứ tự làm thực tế:** xác minh ba SSO identities → refactor config/state DEV → bổ sung/test Orders MySQL → thêm SSM hai env và SQL permissions → dựng PROD riêng → nối CI/CD. Khi refactor dùng `moved`/migration phù hợp; không copy state dev thành prod, không đổi env trên state đang quản lý dev.

**Nghiệm thu:** mỗi env có một RDS MySQL chứa `catalogdb`/`ordersdb`; runtime user không truy cập chéo database; Orders chạy MySQL; SSM đi qua đúng node Managed Node Group từng env; SSO dev không vào node/DB prod; SSO được cấp quyền prod mở tunnel được nhưng SQL human chỉ SELECT, DML/DDL bị từ chối; shell/forwarding tới host khác bị chặn; node thay thế thì tìm node mới kết nối lại được; runtime vẫn ghi được; `dev-ops` không deploy prod; job PROD dùng đúng role, state, secret và image đã qua DEV.

Tham khảo: [SSM remote-host forwarding](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html), [GitHub OIDC/AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).
