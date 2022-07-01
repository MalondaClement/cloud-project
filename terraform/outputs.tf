#data "openstack_identity_auth_scope_v3" "info" {
#  name = "info"
#}

#output "user" {
#  value = "Connected with ${data.openstack_identity_auth_scope_v3.info.user_name}"
#}

output "bastion-ip" {
  value = openstack_networking_floatingip_v2.floatip-bastion.address
}

output "web-server-ip" {
  value = openstack_compute_instance_v2.web-server[*].access_ip_v4
}

output "load-balancer-ip" {
  value = openstack_networking_floatingip_v2.floatip-load-balancer.address
}
