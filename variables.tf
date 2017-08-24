variable "aws_access_key" {
  default = "" 
}

variable "aws_secret_key" {
  default  = ""
}

# this is different from the region code mentioned in the aws-cli configuration
variable "aws_region_code" {
  default = "us-west-1"
}

variable "aws_az" {
  default = "us-west-1b"
}

# Paste the complete public key here or you can pass the same as command line argument to `terraform apply`
# for details check Terraform CLI documentation
variable "aws_key_pair_pub" {
  default = ""
}

variable "aws_ami_type" {
  default = {
    master = "m3.medium"
    node = "m3.medium"
  }
}

# Run to gen token:
# python -c 'import random; print "%0x.%0x" % (random.SystemRandom().getrandbits(3*8), random.SystemRandom().getrandbits(8*8))'
variable "k8s_token" {
  default = ""
}

variable "master_setup_data_file" {
  default = "master_setup.sh"
}

variable "node_setup_data_file" {
  default = "nodes_setup.sh"
}

variable "helm_rbac_data_file" {
  default = "helm-rbac.yml"
}

variable "node_port" {
  default = "30001"
}

variable "lb_app_port" {
  default = "80"
}