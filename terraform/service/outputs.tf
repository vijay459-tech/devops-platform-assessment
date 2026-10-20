output "service_name" { value = module.service.service_name }
output "service_url" { value = module.service.service_url }
output "latest_ready_revision" { value = module.service.latest_ready_revision }
output "runtime_service_account_email" { value = module.service.runtime_service_account_email }
output "deployed_image" { value = module.service.deployed_image }
output "ingress" { value = module.service.ingress }
output "project_id" { value = var.project_id }
output "region" { value = var.region }
