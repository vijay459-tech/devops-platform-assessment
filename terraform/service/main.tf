module "service" {
  source = "../modules/cloud_run_service"

  project_id          = var.project_id
  region              = var.region
  environment         = var.environment
  service_name        = var.service_name
  image               = var.image
  cpu                 = var.cpu
  memory              = var.memory
  timeout_seconds     = var.timeout_seconds
  max_concurrency     = var.max_concurrency
  min_instances       = var.min_instances
  max_instances       = var.max_instances
  ingress             = var.ingress
  invoker_members     = var.invoker_members
  env_vars            = var.env_vars
  secret_env          = var.secret_env
  deletion_protection = var.deletion_protection
}
