output lb_dns {
  value = "${aws_elb.cluster_lb.dns_name}"
}

output bastion_ip {
  value = "${aws_instance.bastion.public_ip}"
}

output master_priv_ip {
  value = "${aws_instance.master.private_ip}"
}

output node_priv_ips {
  value = ["${aws_instance.node1.private_ip}","${aws_instance.node2.private_ip}","${aws_instance.node3.private_ip}"]
}