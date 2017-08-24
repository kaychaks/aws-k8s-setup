provider "aws"{
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region_code}"
}


resource "aws_key_pair" "nodes" {
  key_name = "k8s_node_key"
  public_key = "${var.aws_key_pair_pub}"
}

resource "aws_vpc" "cluster" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags {
    Name = "CLUSTER"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.cluster.id}"
  tags {
    Name = "CLUSTER_IGW"
  }
}

resource "aws_eip" "nat" {
  vpc = true  
}

resource "aws_eip" "elb" {
  vpc = true
}


resource "aws_subnet" "private" {
  vpc_id = "${aws_vpc.cluster.id}"
  availability_zone = "${var.aws_az}"
  cidr_block = "10.0.1.0/24"

  tags {
    Name = "CLUSTER_PRIVATE_SUBNET"
  }
}

resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.cluster.id}"
  availability_zone = "${var.aws_az}"
  cidr_block = "10.0.0.0/24"
  map_public_ip_on_launch = true

  tags {
    Name = "CLUSTE_PUBLIC_SUBNET"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.nat.id}"
  subnet_id = "${aws_subnet.public.id}"
}

resource "aws_security_group" "elb" {
  name = "elb"
  description = "redirect all http traffic towards master k8s node"
  vpc_id = "${aws_vpc.cluster.id}"
  
  ingress {
    from_port = "${var.lb_app_port}"
    to_port = "${var.lb_app_port}"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags {
    Name = "elb"
  }
}

resource "aws_security_group" "kubernetes" {
  name = "kubernetes"
  description = "allow all ssh traffic"
  vpc_id = "${aws_vpc.cluster.id}"
  
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["${aws_vpc.cluster.cidr_block}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags {
    Name = "kubernetes"
  }
}

resource "aws_security_group" "kubernetes_master" {
  name = "kubernetes_master"
  description = "allow http requests only from elb"
  vpc_id = "${aws_vpc.cluster.id}"
  
  ingress {
    from_port = "${var.node_port}"
    to_port = "${var.node_port}"
    protocol = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }  
  
  tags {
    Name = "kubernetes_master"
  }
}

resource "aws_elb" "cluster_lb" {
  name = "cluster-master-node-lb"
  security_groups = ["${aws_security_group.elb.id}"]
  subnets = ["${aws_subnet.public.id}"]
  instances = ["${aws_instance.master.id}"]

  listener {
    instance_port = "${var.node_port}"
    instance_protocol = "HTTP"
    lb_port = "${var.lb_app_port}"
    lb_protocol = "HTTP"    
  }
  
  tags {
    Name = "cluster-master-node-lb"
  }
}

resource "aws_route_table" "main" {
  vpc_id = "${aws_vpc.cluster.id}"
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat.id}"
  }
  tags {
    Name = "main"
  }  
}

resource "aws_route_table" "custom" {
  vpc_id = "${aws_vpc.cluster.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
  tags {
    Name = "custom"
  }  
}

resource "aws_route_table_association" "main" {
  subnet_id = "${aws_subnet.private.id}"
  route_table_id = "${aws_route_table.main.id}"
}

resource "aws_route_table_association" "custom" {
  subnet_id = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.custom.id}"
}

/*
** Instances
*/

data "aws_ami" "ubuntu" {
  
  owners = ["099720109477"] #canonical
  most_recent = true 


  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }
}

data "template_file" "master-userdata" {
  template = "${file("${var.master_setup_data_file}")}"

  vars {
    k8s_token = "${var.k8s_token}"
    helm_yml = "${file("${var.helm_rbac_data_file}")}"
  }
}

data "template_file" "node-userdata" {
  template = "${file("${var.node_setup_data_file}")}"

  vars {
    k8stoken = "${var.k8s_token}"
    masterIP = "${aws_instance.master.private_ip}"
  }
}

resource "aws_instance" "bastion" {
  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "${var.aws_ami_type["node"]}"
  subnet_id = "${aws_subnet.public.id}"
  key_name = "${aws_key_pair.nodes.key_name}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]

  tags {
    Name = "bastion"
  }
}


resource "aws_instance" "master" {
  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "${var.aws_ami_type["master"]}"
  subnet_id = "${aws_subnet.private.id}"
  key_name = "${aws_key_pair.nodes.key_name}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.kubernetes.id}", "${aws_security_group.kubernetes_master.id}"]
  user_data = "${data.template_file.master-userdata.rendered}"

  root_block_device {
    volume_type = "gp2"
    volume_size = 10    
  }

  ebs_block_device {
    device_name = "/dev/sdh"
    volume_type = "gp2"
    volume_size = 50
    delete_on_termination = false
  }

  tags {
    Name = "master"
  }
}

resource "aws_instance" "node1" {
  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "${var.aws_ami_type["node"]}"
  subnet_id = "${aws_subnet.private.id}"
  key_name = "${aws_key_pair.nodes.key_name}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
  user_data = "${data.template_file.node-userdata.rendered}"

  root_block_device {
    volume_type = "gp2"
    volume_size = 10    
  }

  ebs_block_device {
    device_name = "/dev/sdh"
    volume_type = "gp2"
    volume_size = 50
    delete_on_termination = false
  }


  tags {
    Name = "node1"
  }
}

resource "aws_instance" "node2" {
  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "${var.aws_ami_type["node"]}"
  subnet_id = "${aws_subnet.private.id}"
  key_name = "${aws_key_pair.nodes.key_name}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
  user_data = "${data.template_file.node-userdata.rendered}"

  root_block_device {
    volume_type = "gp2"
    volume_size = 10    
  }

  ebs_block_device {
    device_name = "/dev/sdh"
    volume_type = "gp2"
    volume_size = 50
    delete_on_termination = false
  }
  
  tags {
    Name = "node2"
  }
}

resource "aws_instance" "node3" {
  ami = "${data.aws_ami.ubuntu.id}"
  instance_type = "${var.aws_ami_type["node"]}"
  subnet_id = "${aws_subnet.private.id}"
  key_name = "${aws_key_pair.nodes.key_name}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
  user_data = "${data.template_file.node-userdata.rendered}"

  root_block_device {
    volume_type = "gp2"
    volume_size = 10    
  }

  ebs_block_device {
    device_name = "/dev/sdh"
    volume_type = "gp2"
    volume_size = 50
    delete_on_termination = false
  }
  
  tags {
    Name = "node3"
  }
}