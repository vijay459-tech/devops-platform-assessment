# Placeholders: replace project ids for your own sandbox. No secret values here.
project_id   = "example-dev-project"
region       = "us-central1"
environment  = "dev"
service_name = "demo-api"

cpu             = "1"
memory          = "512Mi"
timeout_seconds = 30
max_concurrency = 80
min_instances   = 0 # scale to zero in dev to save cost
max_instances   = 2

# Dev: callers must present a Google identity token. Developers are granted invoker
# explicitly; nothing is public.
ingress             = "INGRESS_TRAFFIC_ALL"
invoker_members     = ["group:platform-dev@example.com"]
deletion_protection = false
