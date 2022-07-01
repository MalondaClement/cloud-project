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
resource "openstack_networking_floatingip_v2" "floatip-bastion" {
  pool = "external-net"
}

resource "openstack_compute_floatingip_associate_v2" "floatip_bastion" {
  floating_ip = "${openstack_networking_floatingip_v2.floatip-bastion.address}"
  instance_id = "${openstack_compute_instance_v2.bastion.id}"
}

# ssh security group for web-server
resource "openstack_networking_secgroup_v2" "allow-ssh-web-server" {
  name = "allow-ssh-web-server"
  description = "allow ssh for web servers but only from bastion"
}

# ssh rule for web server (only from bastion)
resource "openstack_networking_secgroup_rule_v2" "allow-ssh-web-server-rule1" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 22
  port_range_max = 22
  remote_ip_prefix = "${openstack_compute_instance_v2.bastion.access_ip_v4}"
  security_group_id = "${openstack_networking_secgroup_v2.allow-ssh-web-server.id}"
}

# create web server cluster
resource "openstack_compute_instance_v2" "web-server" {
    count = var.nb-web-server
    name = "web-server-${count.index}"
    image_name = "Debian-11-GenericCloud-20220502-997"
    flavor_name = "m1.tiny"
    key_pair = "${var.paire-ssh}"
    security_groups = ["default", openstack_networking_secgroup_v2.allow-ssh-web-server.name]
    network {
      name = openstack_networking_network_v2.private-net.name
    }
    user_data = "${file("web-server-init.sh")}"
}

# create a container
resource "openstack_objectstorage_container_v1" "web-servers-container" {
  name = "web-servers-container"
}

# add index.html to the container
resource "openstack_objectstorage_object_v1" "doc-1" {
  name = "index.html"
  container_name = "${openstack_objectstorage_container_v1.web-servers-container.name}"
  source = "index.html"
}

# add style.css to the container
resource "openstack_objectstorage_object_v1" "doc-2" {
  name = "style.css"
  container_name = "${openstack_objectstorage_container_v1.web-servers-container.name}"
  source = "style.css"
}

# float ip for load balancer
resource "openstack_networking_floatingip_v2" "floatip-load-balancer" {
  pool = "external-net"
}
