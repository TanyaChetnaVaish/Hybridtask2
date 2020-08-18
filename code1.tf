#Specify IAM User specs
provider "aws" {
	region  = "ap-south-1"
	profile = "tanya1"
}
#Key
resource "tls_private_key" "task2key" {
  algorithm   = "RSA"
}
resource "aws_key_pair" "gen_key" {
  key_name   = "task2key" 
  public_key = tls_private_key.task2key.public_key_openssh
}
resource "local_file" "key-file" {
  	content  = tls_private_key.task2key.private_key_pem
  	filename = "task2key.pem"
}

resource "aws_vpc" "t2vpc" {
  cidr_block = "10.1.0.0/16"
  instance_tenancy = "default"
  
  tags = {
	name = "t2vpc"
	}
}
#VPC
resource "aws_subnet" "t2subnet" {
  vpc_id     = aws_vpc.t2vpc.id
  availability_zone = "ap-south-1a"
  cidr_block = "10.1.0.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "t2subnet"
  }
}
resource "aws_internet_gateway" "t2gw" {
  vpc_id = aws_vpc.t2vpc.id

  tags = {
    Name = "t2gw"
  }
}
resource "aws_route_table" "t2route" {
  vpc_id = aws_vpc.t2vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.t2gw.id
  }

  tags = {
    Name = "t2route"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.t2subnet.id
  route_table_id = aws_route_table.t2route.id
}
#Security Group
resource "aws_security_group" "task2secgrp" {
  name        = "task2secgrp"
  description = "sec group for ssh and httpd"
  vpc_id      = aws_vpc.t2vpc.id

    ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "task2secgrp"
  }
}
#EC2
resource "aws_instance"  "task2in"  {
 	ami = "ami-0447a12f28fddb066" 
  	instance_type = "t2.micro"
  	key_name = "task2key"
  	security_groups = [ "${aws_security_group.task2secgrp.id}" ]
    availability_zone = "ap-south-1a"
    subnet_id = "${aws_subnet.t2subnet.id}"
   tags = {
    	  Name = "task2os" 
  	}
        
	
}
#EFS
resource "aws_efs_file_system" "t2efs" {
  creation_token = "t2efs"
  performance_mode = "generalPurpose"

  tags = {
    Name = "itst2-efs"
  }
}
#Moutning EFS
resource "aws_efs_mount_target" "alpha" {
  file_system_id = aws_efs_file_system.t2efs.id
  subnet_id      = aws_subnet.t2subnet.id
  security_groups = ["${aws_security_group.task2secgrp.id}"]
}
resource "null_resource" "mount_efs_volume" {


	connection {
  	  type     = "ssh"
   	  user     = "ec2-user"
   	  private_key = "${tls_private_key.task2key.private_key_pem}" 
   	  host = "${aws_instance.task2in.public_ip}"
  }

 	provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install httpd php git amazon-efs-utils nfs-utils -y",
      "sudo setenforce 0",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo echo '${aws_efs_file_system.t2efs.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
      "sudo mount ${aws_efs_file_system.t2efs.id}:/ /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/TanyaChetnaVaish/Hybridtask2.git /var/www/html/"
	]
  }
}
#S3 Bucket
resource "aws_s3_bucket" "htaskbucket3" {
   bucket = "htaskbucket3"
  acl    = "private"
 }
 resource "aws_s3_bucket_public_access_block" "access_to_bucket" {
  bucket = aws_s3_bucket.htaskbucket3.id

  block_public_acls   = true
  block_public_policy = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_object" "bucketObject" {
bucket = "${aws_s3_bucket.htaskbucket3.bucket}"
key = "download"
acl = "public-read"
source = "C:/Users/TANYA/Downloads/task2/download.png"
etag = filemd5("C:/Users/TANYA/Downloads/task2/download.png")
tags = {
  Name = "My_bucket"
  Environment = "Dev"
}
}
locals {
	s3_origin_id = "tasks2origin"
}
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
	comment = "htaskbucket3"
}

#CREATING CLOUD DISTRIBUTION USING S3 BUCKET  ORIGIN
resource "aws_cloudfront_distribution" "s3distribution" {

  origin {
    domain_name = "${aws_s3_bucket.htaskbucket3.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
}
enabled             = true
is_ipv6_enabled     = true
comment             = "Tanya Access Identity"
default_cache_behavior {
allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = "${local.s3_origin_id}"

forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
viewer_protocol_policy = "allow-all"
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
}
#Cache behavior with precendence 0
ordered_cache_behavior {
path_pattern     = "/content/immutable/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD", "OPTIONS"]
target_origin_id = "${local.s3_origin_id}"

forwarded_values {
query_string = false
headers      = ["Origin"]
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 86400
max_ttl                = 31536000
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
# Cache behavior with precedence 1
ordered_cache_behavior {
path_pattern     = "/content/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = "${local.s3_origin_id}"

forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
price_class = "PriceClass_200"
#PUTTING RESTRICTIONS
restrictions {
geo_restriction {
restriction_type = "whitelist"
locations        = ["IN"]
}
}
tags = {
  Name = "taskdistribution"
Environment = "production"
}
viewer_certificate {
cloudfront_default_certificate = true
}
depends_on=[
	aws_s3_bucket.htaskbucket3
]
#ADDING THE CLOUDFRONT URL TO THE INDEX.HTML FILE AND THUS RUNNING THE PAGE
connection {
        type    = "ssh"
        user    = "ec2-user"
        private_key = "${tls_private_key.task2key.private_key_pem}"
    	host     = "${aws_instance.task2in.public_ip}"
    }

provisioner "remote-exec" {
        inline  = [
            
            "sudo su << EOF",
            "echo \"<center><img src='http://${self.domain_name}/${aws_s3_bucket_object.bucketObject.key}' height='400' width='400'></center>\" >> /var/www/html/index.html",
            "EOF"
        ]
    }
#SHOWING WEBSITE ON CHROME USINF IP OF INSTANCE
provisioner "local-exec" {
command = "start chrome ${aws_instance.task2in.public_ip}"
}


}






