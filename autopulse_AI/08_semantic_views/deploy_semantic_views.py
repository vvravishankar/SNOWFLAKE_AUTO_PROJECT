#!/usr/bin/env python3
# ============================================================================
# AUTOPULSE AI | SEMANTIC VIEW DEPLOYER
# ============================================================================
# Deploys all 3 semantic views from YAML files using
# SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML.
#
# Usage (run from CoCo bash or local terminal):
#   python3 /workspace/autopulse_AI/08_semantic_views/deploy_semantic_views.py
#
# What it does:
#   1. Reads each .sv.yaml file from the same directory
#   2. Escapes single quotes for SQL string embedding
#   3. Calls SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('AUTOPULSE_AI.CURATED', yaml)
#      via `snow sql`
#   4. Reports pass/fail for each semantic view
#
# Prerequisites:
#   - snow CLI authenticated
#   - SYSADMIN role has CREATE SEMANTIC VIEW on AUTOPULSE_AI.CURATED
#   - Base tables referenced in YAML must exist
# ============================================================================

import subprocess
import sys
import os

SCHEMA = "AUTOPULSE_AI.CURATED"
ROLE = "SYSADMIN"
WAREHOUSE = "AUTOPULSE_WH"

# YAML files to deploy (order does not matter)
YAML_DIR = os.path.dirname(os.path.abspath(__file__))
YAML_FILES = [
    "battery_intelligence.sv.yaml",
    "dq_intelligence.sv.yaml",
    "ops_intelligence.sv.yaml",
]

def deploy_semantic_view(yaml_path):
    """Read a YAML file and deploy it as a semantic view."""
    with open(yaml_path, "r") as f:
        yaml_content = f.read()

    # Extract the view name from the YAML for logging
    view_name = "UNKNOWN"
    for line in yaml_content.splitlines():
        if line.startswith("name:"):
            view_name = line.split(":", 1)[1].strip()
            break

    # Escape single quotes for SQL string literal
    escaped = yaml_content.replace("'", "''")

    # Build the SQL — snow sql does NOT support $$ dollar-quoting,
    # so we use single-quoted strings with escaped content.
    sql = (
        f"USE ROLE {ROLE}; "
        f"USE WAREHOUSE {WAREHOUSE}; "
        f"CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('{SCHEMA}', '{escaped}');"
    )

    result = subprocess.run(
        ["snow", "sql", "-q", sql],
        capture_output=True,
        text=True,
        timeout=120,
    )

    success = result.returncode == 0 and "successfully created" in result.stdout.lower()

    return view_name, success, result.stdout, result.stderr


def main():
    print("=" * 60)
    print("AUTOPULSE AI — Semantic View Deployment")
    print("=" * 60)

    results = []
    for filename in YAML_FILES:
        yaml_path = os.path.join(YAML_DIR, filename)
        if not os.path.exists(yaml_path):
            print(f"\n  SKIP  {filename} — file not found")
            results.append((filename, "SKIP", "File not found"))
            continue

        print(f"\n  Deploying {filename} ...", end=" ", flush=True)
        view_name, success, stdout, stderr = deploy_semantic_view(yaml_path)

        if success:
            print(f"PASS  →  {view_name}")
            results.append((filename, "PASS", view_name))
        else:
            # Extract the error line
            err_msg = ""
            for line in stderr.splitlines():
                if "error" in line.lower() or "invalid" in line.lower():
                    err_msg = line.strip().strip("│").strip()
                    break
            print(f"FAIL  →  {view_name}")
            print(f"         {err_msg}")
            results.append((filename, "FAIL", err_msg))

    # Summary
    print("\n" + "=" * 60)
    passed = sum(1 for _, s, _ in results if s == "PASS")
    total = len(results)
    print(f"Result: {passed}/{total} semantic views deployed")
    for filename, status, detail in results:
        print(f"  [{status}] {filename}  —  {detail}")
    print("=" * 60)

    # Exit with failure if any didn't pass
    if passed < total:
        sys.exit(1)


if __name__ == "__main__":
    main()
