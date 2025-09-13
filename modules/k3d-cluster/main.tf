# This resource doesn't create anything itself, but acts as a trigger
# for running local shell commands to create and destroy the K3d cluster.
resource "null_resource" "k3d_cluster" {

  # This is critical. The 'triggers' block tells Terraform that if any of
  # these input variables change, the resource must be "replaced".
  # Replacing it will re-run the create and destroy provisioners.
  triggers = {
    cluster_name = var.cluster_name
    agents       = var.agents
    servers      = var.servers
    host_port    = var.host_port
  }

  # This provisioner runs when you execute `terragrunt apply`.
  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      k3d cluster create ${var.cluster_name} \
        --agents ${var.agents} \
        --servers ${var.servers} \
        --port ${var.host_port}:80@loadbalancer \
        --kubeconfig-update-default \
        --kubeconfig-switch-context
    EOT
  }

  # This provisioner runs when you execute `terragrunt destroy`.

  provisioner "local-exec" {
    when    = destroy
    # We reference the cluster_name from the 'triggers' map of the resource itself.
    # This is a valid reference during the destroy phase.
    command = "k3d cluster delete ${self.triggers.cluster_name}"
  }
}
