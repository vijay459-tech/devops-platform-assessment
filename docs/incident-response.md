# Runbook: pipeline succeeded, new revision shows elevated latency and intermittent errors

**Premise:** "pipeline green" only proves the revision became Ready on the intended digest. It says nothing about
behavior under real traffic. Treat the deploy as the prime suspect, but prove it rather than assume it.

**Roles:** Incident Commander (IC) owns decisions and comms; Platform engineer drives Cloud Run/Terraform actions;
App owner interprets application evidence. One person executes changes at a time.

## 0. First 2 minutes: stabilise the decision, not the system

1. Declare the incident, name the IC, open a timeline doc (UTC timestamps for every action).
2. Set `DEPLOY_FREEZE=true` (repo variable) so nothing else is promoted during triage.
3. Note deploy time T0 and the symptom start. Did the symptom start at T0 or later?

## 1. Evidence to gather in the first 10-15 minutes

| Evidence | How | What it tells you |
|---|---|---|
| **What changed** | `deployment-evidence-prod-<sha>.json`, release manifest, the retained `tfplan`/`plan.txt`, `gcloud run revisions list`, Cloud Audit Logs (Cloud Run, IAM, Secret Manager) | exact digest/commit, config diff, any out-of-band change or secret rotation near T0 |
| **Errors and latency per revision** | Cloud Monitoring `run.googleapis.com/request_count` by `response_code_class` and `revision_name`; `request_latencies` p50/p95/p99 by revision | does the problem follow the new revision? (single most useful split) |
| **Logs** | Logs Explorer: `resource.type="cloud_run_revision" resource.labels.service_name="demo-api-prod" severity>=ERROR`, grouped by `resource.labels.revision_name`; also platform-level lines (`run.googleapis.com/requests`, container terminated, OOM, startup probe failed) | app exceptions vs platform symptoms (503 no instance, 429, timeouts) |
| **Capacity/scaling** | `container/instance_count`, `container/cpu/utilizations`, `container/memory/utilizations`, `container/max_request_concurrencies`, startup latency | hitting `max_instances`, CPU throttling, concurrency saturation, cold starts, OOM |
| **Traces** | Cloud Trace / client spans for slow requests | where time goes: app code vs dependency vs queueing |
| **Dependencies** | dependency dashboards (DB connections/latency, downstream 5xx, quotas) | slowness that is not ours |
| **Front door** (if an LB exists) | LB logs: `statusDetails`, backend latency, 502/504 | edge vs backend, Cloud Armor blocks |
| **Platform status** | Google Cloud Status Dashboard, Personalized Service Health | regional/platform incident |

Example filters/commands:

```bash
gcloud run revisions list --service demo-api-prod --region REGION --project PROJECT
gcloud run services describe demo-api-prod --region REGION --project PROJECT --format=yaml > svc-before.yaml
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="demo-api-prod" AND severity>=ERROR' \
  --project PROJECT --freshness=30m --limit=200 --format=json > errors-30m.json
```

## 2. Separating the hypotheses

| Hypothesis | Pointing toward it | Pointing away | Quick discriminating test |
|---|---|---|---|
| **Application** (new code) | errors/latency only on the new revision; stack traces; `/version` commit matches the change | old revision equally bad | shift a small % to the previous revision and compare |
| **Configuration** | plan diff touched cpu/memory/concurrency/timeout/min instances/env/secret version; behavior changed exactly at T0 on any code | config identical to previous revision | `revisions describe` old vs new; diff the YAMLs |
| **Identity** | `PERMISSION_DENIED`/`401`/`403` in logs; secret access or downstream auth failures; audit-log denials; a secret `latest` rotated | no auth errors | read the audit log for the runtime SA; test the secret version manually |
| **Networking** | connect/DNS timeouts, 502/504 at LB, errors to specific egress targets; recent ingress/VPC/firewall change | errors are 5xx from app code | compare errors by destination; check ingress setting; LB backend latency |
| **Scaling** | `instance_count` at `max_instances`, 429/503 "no available instance", latency scaling with load, CPU > 80%, memory near limit/OOM, many cold starts | steady instance count and low utilization | temporarily raise max/min instances (a *config* change: record it) |
| **Downstream dependency** | traces show time in a client span; dependency metrics degraded; both revisions affected | dependency healthy | check dependency dashboards; call it directly from a safe context |

**Key signal:** if old and new revisions are *both* degraded, stop blaming the deploy and move toward dependency/platform/capacity;
rolling back will not help and wastes time.

## 3. Owners and what each needs

| Owner | Brought in when | Give them |
|---|---|---|
| Application team | always (comms + code) | digest/commit and diff, error samples with revision names, trace IDs, time window |
| Platform (us) | always | n/a: drives revision config, rollback, Terraform reconciliation |
| Security / IAM | auth errors, secret changes | runtime SA email, denied method/resource from audit log, time of denial |
| Network team | LB/VPC/egress symptoms | LB/backend, error class (502/504), egress targets, recent network changes |
| Dependency owner (DB/vendor) | downstream suspected | their client's error/latency data, connection counts, time window, our request rate |
| Incident Commander / comms | always | one-line status every ~15 min: impact, hypothesis, next decision |
| Google Cloud support | platform-level evidence | project, region, service, revision, request IDs, status-page correlation |

## 4. Decision triggers

| Condition | Action |
|---|---|
| Errors or latency are clearly worse on the new revision (e.g. 5xx > 1% **or** p95 > 2x baseline for 5 min, SLO burning) and a known-good revision exists | **Rollback**: `scripts/rollback.sh shift ...` to the previous revision immediately; investigate afterwards |
| Impact is severe or growing and the cause is unclear, but the previous revision is healthy | **Traffic shift**: move 50%, then 100% away from the new revision while evidence is gathered; compare per revision |
| Both revisions degraded, or the signal tracks load/dependency/platform | **Continue investigating**; do *not* roll back; consider scaling limits, shedding load, or dependency mitigation |
| Impact is minor, stable, and below SLO thresholds | **Continue investigating** with a deadline (e.g. 30 min) and a pre-agreed rollback trigger |
| Any security or data-integrity suspicion | rollback/contain first, then escalate to security; preserve everything |

After any manual shift, run the **Rollback** workflow for the same digest so Terraform matches reality, because the next apply would otherwise undo the shift.

## 5. Preserve evidence while restoring service

- **Before changing anything:** save `svc-before.yaml` and `revisions describe` for old and new; export the log window (Logs Explorer saved query or a sink to GCS/BigQuery); screenshot or export metric charts; copy the `tfplan`, plan text, release manifest and deployment evidence artifacts (already retained).
- **Keep the failing revision.** Shifting traffic to 0% does not delete it; tag it (`gcloud run services update-traffic ... --set-tags failing=REVISION`) so it can be reproduced and inspected later. Never delete revisions or `terraform destroy` during an incident.
- Take actions through the **governed** path where possible (rollback workflow); emergency manual actions go in the timeline with who/when/why.
- Record the digest and commit of both the bad and good releases. Retain artifacts beyond normal retention for the postmortem.

## 6. One improvement to reduce recurrence

**Progressive delivery with an SLO gate and automatic rollback.** Today a deploy sends 100% of traffic to the new revision at once.
Deploy the new revision with `--no-traffic` and a tag, run synthetic checks against the tagged URL, then step traffic 5% -> 25% -> 100%,
at each step comparing the new revision's error rate and p95 latency against the previous revision (Cloud Monitoring alert policies
or Cloud Deploy canary + verification); breach of the threshold shifts traffic back automatically and fails the pipeline. This converts "green means Ready"
into "green means healthy under real traffic", and limits blast radius to a small percentage.
Complementary (not scoped here): alert on per-revision error/latency ratio, and a deploy annotation on dashboards.

## Postmortem checklist

Timeline, detection time vs impact start, why the pipeline was green, why detection was manual or automatic, the
trigger/decision timeline, action items with owners (improvement above), and whether the runbook's thresholds were right.
