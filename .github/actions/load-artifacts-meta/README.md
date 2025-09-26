# Load Run Artifacts Metadata (Composite)

Loads and normalizes GitHub Actions run artifacts metadata so jobs can reuse it without repeating API calls.

## Inputs
- `repo` (optional): `owner/name` (defaults to `${{ github.repository }}`)
- `run_id` (optional): workflow run id (defaults to `${{ github.run_id }}`)
- `token` (optional): GitHub token (defaults to `${{ secrets.GITHUB_TOKEN }}`)
- `prefer_cache` (optional): prefer `$RUNNER_TEMP/artifacts_meta.json` if present; default `true`
- `output_path` (optional): write normalized JSON to this path

## Outputs
- `json`: normalized JSON
- `count`: number of artifacts

## Example
```yaml
- name: Load artifacts metadata
  id: meta
  uses: LabVIEW-Community-CI-CD/gha-pr-comment-and-artifacts/action-artifacts@v1
  with:
    prefer_cache: true
    output_path: telemetry/artifacts_meta.json

- name: Use metadata
  run: |
    jq -r '.artifacts | length' telemetry/artifacts_meta.json
```

## Install (external)
```yaml
- name: Load artifacts metadata
  id: meta
  uses: LabVIEW-Community-CI-CD/gha-pr-comment-and-artifacts/action-artifacts@v1
  with:
    prefer_cache: true
    output_path: telemetry/artifacts_meta.json
```

## Permissions
- The workflow token must allow reading Actions metadata:
  - `permissions:` should include at least:
    - `actions: read`
    - `contents: read`
- For private repositories, ensure the workflow run has access to the run’s artifacts.

## Troubleshooting
- Empty results/404: confirm `permissions: actions: read`, `run_id` is correct, and the run belongs to the same repository/visibility as the token.
- No direct links in downstream comments: token may lack `actions: read` or artifacts may be expired (`expired`/`expires_at` fields). Adjust retention or fetch earlier in the workflow.
- Public repos: archive download URLs require an authenticated browser; provide the run page link as a public fallback.

## Marketplace
- Listing (after publish): https://github.com/marketplace/actions/<artifacts-action-slug>
  - Replace `<artifacts-action-slug>` with the actual slug once listed.

