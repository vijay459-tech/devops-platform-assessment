import copy
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))

import validate_workflows as vw  # noqa: E402

GOOD = {
    "name": "x",
    "on": {"push": {"branches": ["main"]}},
    "permissions": {"contents": "read"},
    "jobs": {
        "j": {
            "runs-on": "ubuntu-24.04",
            "steps": [{"uses": "actions/checkout@v4", "with": {"persist-credentials": False}}],
        }
    },
}


def mutate(fn) -> list[str]:
    doc = copy.deepcopy(GOOD)
    fn(doc)
    return vw.check_workflow("t.yml", doc, str(doc))


class WorkflowPolicyTest(unittest.TestCase):
    def test_good_workflow_passes(self) -> None:
        self.assertEqual(vw.check_workflow("t.yml", GOOD, str(GOOD)), [])

    def test_missing_permissions_fails(self) -> None:
        self.assertTrue(any("permissions" in e for e in mutate(lambda d: d.pop("permissions"))))

    def test_write_all_string_fails(self) -> None:
        self.assertTrue(mutate(lambda d: d.update(permissions="write-all")))

    def test_workflow_wide_write_fails(self) -> None:
        self.assertTrue(mutate(lambda d: d["permissions"].update({"id-token": "write"})))

    def test_pull_request_target_fails(self) -> None:
        self.assertTrue(any("pull_request_target" in e for e in mutate(lambda d: d["on"].update(pull_request_target={}))))

    def test_service_account_key_fails(self) -> None:
        def add(d: dict) -> None:
            d["jobs"]["j"]["steps"].append({"uses": "google-github-actions/auth@v2", "with": {"credentials_json": "x"}})
        self.assertTrue(any("credentials_json" in e for e in mutate(add)))

    def test_gcp_auth_requires_wif_and_id_token(self) -> None:
        def add(d: dict) -> None:
            d["jobs"]["j"]["steps"].append({"uses": "google-github-actions/auth@v2", "with": {"service_account": "a"}})
        errs = mutate(add)
        self.assertTrue(any("workload_identity_provider" in e for e in errs))
        self.assertTrue(any("id-token" in e for e in errs))

    def test_script_injection_pattern_fails(self) -> None:
        def add(d: dict) -> None:
            d["jobs"]["j"]["steps"].append({"run": "echo ${{ inputs.reason }}"})
        self.assertTrue(any("untrusted context" in e for e in mutate(add)))

    def test_checkout_must_not_persist_credentials(self) -> None:
        def add(d: dict) -> None:
            d["jobs"]["j"]["steps"] = [{"uses": "actions/checkout@v4"}]
        self.assertTrue(any("persist-credentials" in e for e in mutate(add)))


def deploy_doc() -> dict:
    return {
        "jobs": {
            "plan": {"steps": [{"uses": "actions/upload-artifact@v4"}]},
            "apply": {
                "needs": "plan",
                "environment": "${{ inputs.environment }}",
                "concurrency": {"group": "terraform-apply-${{ inputs.environment }}", "cancel-in-progress": False},
                "steps": [{"run": "terraform apply tfplan"}],
            },
        }
    }


class DeployControlsTest(unittest.TestCase):
    def check(self, doc: dict) -> list[str]:
        return vw.check_deploy_controls({"deploy.yml": doc})

    def test_good_deploy_passes(self) -> None:
        self.assertEqual(self.check(deploy_doc()), [])

    def test_missing_concurrency_fails(self) -> None:
        d = deploy_doc()
        del d["jobs"]["apply"]["concurrency"]
        self.assertTrue(any("concurrency" in e for e in self.check(d)))

    def test_cancel_in_progress_true_fails(self) -> None:
        d = deploy_doc()
        d["jobs"]["apply"]["concurrency"]["cancel-in-progress"] = True
        self.assertTrue(self.check(d))

    def test_global_concurrency_group_fails(self) -> None:
        d = deploy_doc()
        d["jobs"]["apply"]["concurrency"]["group"] = "terraform-apply"
        self.assertTrue(any("per-environment" in e for e in self.check(d)))

    def test_missing_environment_fails(self) -> None:
        d = deploy_doc()
        del d["jobs"]["apply"]["environment"]
        self.assertTrue(any("approval boundary" in e for e in self.check(d)))

    def test_apply_must_use_saved_plan(self) -> None:
        d = deploy_doc()
        d["jobs"]["apply"]["steps"] = [{"run": "terraform apply -auto-approve"}]
        self.assertTrue(any("saved tfplan" in e for e in self.check(d)))

    def test_plan_must_be_retained(self) -> None:
        d = deploy_doc()
        d["jobs"]["plan"]["steps"] = []
        self.assertTrue(any("retain the plan" in e for e in self.check(d)))

    def test_plan_and_apply_must_be_separate(self) -> None:
        self.assertTrue(self.check({"jobs": {"deploy": {}}}))


class RepoWorkflowsTest(unittest.TestCase):
    def test_actual_repo_workflows_satisfy_policy(self) -> None:
        docs, raws = vw.load_all(vw.WORKFLOW_DIR)
        errors = vw.check_deploy_controls(docs)
        for name, doc in docs.items():
            errors += vw.check_workflow(name, doc, raws[name])
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
