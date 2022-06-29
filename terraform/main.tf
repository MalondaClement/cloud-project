provider "openstack" {
  cloud = "openstack"
  use_octavia = true
}

data "openstack_networking_network_v2" "external-net" {
  name = "external-net"
}

data "openstack_networking_subnet_v2" "external-subnet" {
  network_id = "${data.openstack_networking_network_v2.external-net.id}"
}

#create private network
resource "openstack_networking_network_v2" "private-net" {
  name = "private-net"
  mtu = 1400
  shared = false
}

#create subnet
resource "openstack_networking_subnet_v2" "private-subnet" {
  name = "private-subnet"
  network_id = "${openstack_networking_network_v2.private-net.id}"
  cidr = "10.0.0.0/24"
  allocation_pool {
    start = "10.0.0.2"
    end = "10.0.0.254"
  }
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

# router
resource "openstack_networking_router_v2" "router-nat"{
  name = "router-nat"
  external_network_id = data.openstack_networking_network_v2.external-net.id
}

# router interface
resource "openstack_networking_router_interface_v2" "router-nat-interface" {
  router_id = "${openstack_networking_router_v2.router-nat.id}"
  subnet_id = "${openstack_networking_subnet_v2.private-subnet.id}"
}

# ssh security group
resource "openstack_networking_secgroup_v2" "allow-ssh" {
  name = "allow-ssh"
  description = "allow ssh for bastion"
}

# ssh rule
resource "openstack_networking_secgroup_rule_v2" "allow-ssh-rule1"{
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.allow-ssh.id}"
}

#create bastion
resource "openstack_compute_instance_v2" "bastion" {
  name = "bastion"
  image_name = "Debian-11-GenericCloud-20220502-997"
  flavor_name = "m1.tiny"
  key_pair = "${var.paire-ssh}"#"clement"
  security_groups = ["default", openstack_networking_secgroup_v2.allow-ssh.name]
  network {
    name = openstack_networking_network_v2.private-net.name
  }
}

# float ip for bastion
resource "openstack_networking_floatingip_v2" "floatip_bastion" {
  pool = "external-net"
}

resource "openstack_compute_floatingip_associate_v2" "floatip_bastion" {
  floating_ip = "${openstack_networking_floatingip_v2.floatip_bastion.address}"
  instance_id = "${openstack_compute_instance_v2.bastion.id}"
}
