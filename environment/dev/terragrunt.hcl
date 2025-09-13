# Include this block to automatically find and include parent terragrunt.hcl files.
# While not strictly necessary for this simple setup, it's a core Terragrunt concept.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point Terragrunt to the Terraform module we just created.
terraform {
  source = "../../modules/k3d-cluster"
}

# Define the inputs for the module's variables for this specific environment.
inputs = {
  cluster_name = "wikimedia-poc-dev"
  agents       = 2
  host_port    = "8081"
}
