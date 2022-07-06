##############
#### MAIN ####
##############

provider "openstack" {
  cloud = "openstack"
  use_octavia = true
}

##############################
#### DATA FOR THE PROJECT ####
##############################

data "openstack_networking_network_v2" "external-net" {
  name = "external-net"
}

data "openstack_networking_subnet_v2" "external-subnet" {
  network_id = "${data.openstack_networking_network_v2.external-net.id}"
}

##############################################
#### Add private network for all instance ####
##############################################

#create private network
resource "openstack_networking_network_v2" "private-net" {
  name = "private-net"
  mtu = 1400
  shared = false
}

#create subnet for our private network
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

###############################
#### Add Bastion for admin ####
###############################

# ssh security group for bastion : it allows only ssh
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

#create bastion with allow-ssh security group (the key paire is set during plan and apply)
resource "openstack_compute_instance_v2" "bastion" {
  name = "bastion"
  image_name = "Debian-11-GenericCloud-20220502-997"
  flavor_name = "m1.tiny"
  key_pair = "${var.paire-ssh}"
  security_groups = ["default", openstack_networking_secgroup_v2.allow-ssh.name]
  network {
    name = openstack_networking_network_v2.private-net.name
  }
}

# float ip for bastion that will be use by an admin for ssh connection
resource "openstack_networking_floatingip_v2" "floatip-bastion" {
  pool = "external-net"
}

resource "openstack_compute_floatingip_associate_v2" "floatip-bastion" {
  floating_ip = "${openstack_networking_floatingip_v2.floatip-bastion.address}"
  instance_id = "${openstack_compute_instance_v2.bastion.id}"
}

#######################################
#### Create a group of web servers ####
#######################################

# ssh security group for web-server
resource "openstack_networking_secgroup_v2" "allow-ssh-web-server" {
  name = "allow-ssh-web-server"
  description = "allow ssh for web servers but only from web servers"
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

# security group for port 80 on web servers but only from private network ip (load balancer)
resource "openstack_networking_secgroup_v2" "allow-web-server-http" {
  name = "allow-web-server-http"
  description = "allow port 80 on web server"
}

resource "openstack_networking_secgroup_rule_v2" "allow-web-server-http-rule1" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol = "tcp"
  port_range_min = 80
  port_range_max = 80
  remote_ip_prefix = "10.0.0.0/24"
  security_group_id = "${openstack_networking_secgroup_v2.allow-web-server-http.id}"
}

# create web server cluster default number is 3
resource "openstack_compute_instance_v2" "web-server" {
    count = var.nb-web-server
    name = "web-server-${count.index}"
    image_name = "Debian-11-GenericCloud-20220502-997"
    flavor_name = "m1.tiny"
    key_pair = "${var.paire-ssh}"
    security_groups = ["default", openstack_networking_secgroup_v2.allow-ssh-web-server.name, openstack_networking_secgroup_v2.allow-web-server-http.name]
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

##############################
#### Create Load Balancer ####
##############################

# float ip for load balancer
resource "openstack_networking_floatingip_v2" "floatip-load-balancer" {
  pool = "external-net"
}

# port 80 security group for load balancer from all ip in external network
resource "openstack_networking_secgroup_v2" "lb-allow-http" {
  name = "lb-allow-http"
  description = "allow ssh for bastion"
}

# port 80 rule
resource "openstack_networking_secgroup_rule_v2" "lb-allow-http-rule1"{
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = "${openstack_networking_secgroup_v2.lb-allow-http.id}"
}

# load balancer
resource "openstack_lb_loadbalancer_v2" "load-balancer" {
  name = "load-balancer"
  vip_subnet_id = "${openstack_networking_subnet_v2.private-subnet.id}"
  security_group_ids = [openstack_networking_secgroup_v2.lb-allow-http.id]
}

# add listener to the load balancer
resource "openstack_lb_listener_v2" "load-balancer-listener" {
  name = "load-balancer-listener"
  protocol = "HTTP"
  protocol_port = 80
  loadbalancer_id = "${openstack_lb_loadbalancer_v2.load-balancer.id}"

  insert_headers = {
      X-Forwarded-For = "true"
      X-Forwarded-Proto = "true"
  }
}

# create a pool for load balancer
resource "openstack_lb_pool_v2" "load-balancer-pool" {
  name = "load-balancer-pool"
  protocol = "HTTP"
  lb_method = "ROUND_ROBIN"
  listener_id = "${openstack_lb_listener_v2.load-balancer-listener.id}"
}

# add monitoring on the pool
resource "openstack_lb_monitor_v2" "web-servers-monitor" {
  name = "web-servers-monitor"
  pool_id     = "${openstack_lb_pool_v2.load-balancer-pool.id}"
  type        = "HTTP"
  delay       = 20
  timeout     = 10
  max_retries = 5
}

# add all the web servers to the load balancer
resource "openstack_lb_member_v2" "web-servers-members" {
  count = var.nb-web-server
  pool_id = "${openstack_lb_pool_v2.load-balancer-pool.id}"
  address = "${element(openstack_compute_instance_v2.web-server.*.access_ip_v4, count.index)}"
  protocol_port = 80
}

# add an ip to the load balancer
resource "openstack_networking_floatingip_associate_v2" "floatip-load-balancer" {
  floating_ip = "${openstack_networking_floatingip_v2.floatip-load-balancer.address}"
  port_id = "${openstack_lb_loadbalancer_v2.load-balancer.vip_port_id}"
  depends_on = [openstack_networking_floatingip_v2.floatip-load-balancer]
}

##################################################
#### DNS record for bastion and load balancer ####
##################################################

# create a DNS zone (format is <project>.upec.dip-tcs.com.)
resource "openstack_dns_zone_v2" "my-zone-dns" {
    name = "c01.upec.dip-tcs.com."
    email = "email@example.com"
    description = "dns zone for bastion and load balancer"
    ttl = 3600
    type = "PRIMARY"
}

# add a record to the DNS zone for the load balancer
resource "openstack_dns_recordset_v2" "lb_record" {
    zone_id = "${openstack_dns_zone_v2.my-zone-dns.id}"
    name = "lb.${openstack_dns_zone_v2.my-zone-dns.name}"
    ttl = 3600
    type = "A"
    records = ["${openstack_networking_floatingip_v2.floatip-load-balancer.address}"]
}

# add a record to the DNS zone for the bastion
resource "openstack_dns_recordset_v2" "bastion_record" {
  zone_id = "${openstack_dns_zone_v2.my-zone-dns.id}"
  name = "bastion.${openstack_dns_zone_v2.my-zone-dns.name}"
  ttl = 3600
  type = "A"
  records = ["${openstack_networking_floatingip_v2.floatip-bastion.address}"]
}

###########################################
#### snapshot for the first web server ####
###########################################

# snapshot
resource "openstack_blockstorage_volume_v3" "snapshot-volume-1" {
  name        = "snapshot-volume-1"
  description = "first test volume"
  size        = 10
}

# attache the volume to the first web server
resource "openstack_compute_volume_attach_v2" "attached" {
  instance_id = "${openstack_compute_instance_v2.web-server[1].id}"
  volume_id   = "${openstack_blockstorage_volume_v3.snapshot-volume-1.id}"
}
