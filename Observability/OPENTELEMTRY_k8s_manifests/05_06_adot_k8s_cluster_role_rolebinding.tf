# ADOT Collector RBAC Resources
# Purpose: Grant OpenTelemetry Collector permissions to scrape metrics from Kubernetes API
resource "kubernetes_service_account_v1" "adot_collector" {
  metadata {
    name      = "adot-collector"
    namespace = "default"
    labels = {
      "app.kubernetes.io/name"      = "adot-collector"
      "app.kubernetes.io/component" = "opentelemetry-collector"
    }
  }
}

# cấu hình RBAC (Role-Based Access Control) trong Kubernetes, cụ thể là cấp quyền cho ADOT Collector (thông qua ServiceAccount của nó)
#  được phép đọc thông tin từ toàn bộ cụm Kubernetes để phục vụ cho việc thu thập metrics và telemetry.


# Kubernetes Cluster Role
# Định nghĩa các quyền truy cập (permissions) mà ADOT Collector cần để thu thập dữ liệu từ Kubernetes API.
resource "kubernetes_cluster_role_v1" "otel_collector" {
  metadata {
    name = "otel-collector-cluster-role"
  }

  # Core Kubernetes resources
  # nodes, nodes/proxy: Thu thập số liệu hiệu năng phần cứng của các Worker Node (CPU, RAM).
  # services, endpoints, pods, namespaces: Lấy danh sách các service, pod và namespace đang chạy để 
  #         biết ứng dụng nào đang tồn tại trên cụm mà gom metrics.
  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/proxy", "services", "endpoints", "pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  # Apps resources
  # Lấy thông tin cấu hình và trạng thái của các workload để gắn nhãn (metadata) cho các metrics (ví dụ: metric này thuộc deployment nào, pod nào).
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets", "deployments", "daemonsets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }

  # Extensions resources
  # Đọc thông tin về các luật Ingress để giám sát lưu lượng hoặc trạng thái đường truyền.
  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  # Metrics endpoint
  # Cho phép thu thập các metrics hệ thống được phơi bày trực tiếp qua đường dẫn /metrics (ví dụ từ Kubelet hoặc các component cốt lõi).
  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

# Gắn quyền cho "Chủ thể" (Subject) là ServiceAccount của ADOT Collector để nó có thể thực thi các quyền đã định nghĩa trong ClusterRole.
# Kubernetes Cluster Role Binding
resource "kubernetes_cluster_role_binding_v1" "otel_collector" {
  metadata {
    name = "otel-collector-cluster-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.otel_collector.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.adot_collector.metadata[0].name
    namespace = kubernetes_service_account_v1.adot_collector.metadata[0].namespace
  }
}