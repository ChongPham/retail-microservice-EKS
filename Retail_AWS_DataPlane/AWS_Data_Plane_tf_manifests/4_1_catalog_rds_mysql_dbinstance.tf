# RDS MySQL Database Instance 
resource "aws_db_instance" "catalog_rds" {
  # định danh và engine của cơ sở dữ liệu
  identifier              = "mydb3"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  # cấu hình csdl và xác thực
  db_name                 = "catalogdb"
  username                = local.retailstore_secret_json.username
  password                = local.retailstore_secret_json.password
  # Bảo mật và Mạng (Networking & Security)
  db_subnet_group_name    = aws_db_subnet_group.rds_private.name
  # Áp dụng một Security Group riêng cho MySQL (chỉ cho phép các resource trong cụm EKS truy cập vào cổng database).
  vpc_security_group_ids  = [aws_security_group.rds_mysql_sg.id]
  # Bỏ qua việc tạo bản snapshot cuối cùng khi xóa database
  skip_final_snapshot     = true
  # Tắt quyền truy cập công khai. Database hoàn toàn bị cô lập khỏi internet và chỉ có thể truy cập nội bộ trong VPC.
  publicly_accessible     = false
  # Tự động xóa các bản backup tự động khi database bị xóa.
  delete_automated_backups = true
  # Database chỉ chạy trên 1 AZ duy nhất
  multi_az                = false
  # Giữ lại lịch sử backup tự động trong vòng 1 ngày.
  backup_retention_period = 1

  tags = {
    Name = "${local.name}-catalog-rds-mysql"
  }
}


# Outputs
output "catalog_rds_endpoint" {
  description = "RDS endpoint for Catalog microservice"
  value       = aws_db_instance.catalog_rds.address
}

output "catalog_rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds_mysql_sg.id
}