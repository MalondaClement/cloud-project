#data "openstack_identity_auth_scope_v3" "info" {
#  name = "info"
#}

#output "user" {
#  value = "Connected with ${data.openstack_identity_auth_scope_v3.info.user_name}"
#}

output "bastion-ip" {
  value = openstack_networking_floatingip_v2.floatip_bastion.address
}
