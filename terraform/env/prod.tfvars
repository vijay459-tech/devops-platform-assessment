# Placeholders: replace with the real production project. No secret values here.
project_id   = "example-prod-project"
region       = "us-central1"
environment  = "prod"
service_name = "demo-api"

cpu             = "1"
memory          = "512Mi"
timeout_seconds = 30
max_concurrency = 80
min_instances   = 1 # keep one warm instance: avoids cold-start latency on first request
max_instances   = 10

# Prod: only reachable via a load balancer. Until one exists the service is
# intentionally unreachable from the internet. See docs/terraform.md.
ingress             = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
invoker_members     = [] # the future LB / API gateway identity is added here via reviewed PR
deletion_protection = true
