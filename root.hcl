# This is the root terragrunt configuration file.
# In a real project, this is where you would configure your remote state backend
# (e.g., S3, GCS, Azure Blob) and any global variables shared across all environments.

# For this POC, it can remain empty or contain just comments, but its presence
# allows the `find_in_parent_folders()` function in child configurations to work correctly.

# Example of what could go here later:
# remote_state {
#   backend = "local"
#   config = {
#     path = "${get_terragrunt_dir()}/terraform.tfstate"
#   }
# }
