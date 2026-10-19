# Datasource: EKS Cluster Auth 
data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.id
}

# HELM Provider
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Terraform Kubernetes Provider
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Để Kubernetes Provider có thể kết nối được, nó bắt buộc phải biết địa chỉ truy cập (host), 
#     chứng chỉ bảo mật (cluster_ca_certificate), và token xác thực (token) của cụm EKS. 
#     Những thông tin này chỉ xuất hiện và có thật khi cụm EKS đã được khởi tạo xong trên AWS.
# Ngay khi cụm EKS hình thành, các Provider này mới có đủ dữ liệu từ các biến đầu ra (aws_eks_cluster.main.endpoint,...) 
#         để kích hoạt, từ đó cho phép các bước sau dùng cú pháp Kubernetes/Helm để dựng ứng dụng lên cụm.