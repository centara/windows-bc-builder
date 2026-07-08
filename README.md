# Windows Docker GitHub Runner

This repository is a Windows version of the [myoung34/docker-github-actions-runner](https://github.com/myoung34/docker-github-actions-runner) runner for Linux. Tried has been to keep the usage as close as possible.

This repository will run the [self-hosted github actions runners](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/hosting-your-own-runners) for Windows.

## Included tools

PowerShell 7, Git for Windows (incl. bash), GitHub CLI, Python and the Docker CLI are baked into the image, downloaded directly from each vendor's release channel — not from the Chocolatey community feed, whose throttling repeatedly broke scheduled builds (and once shipped an image without pwsh).

The build works in two steps:

1. `resolve-tools.ps1` runs in the workflow (authenticated GitHub API access via `GH_TOKEN`) and writes `tools.lock.json` with the latest version, download URL and vendor SHA256 for each tool. It also resolves the latest runner version, passed to the build as `RUNNER_VERSION`.
2. `install-tools.ps1` runs inside `docker build`, downloads each tool with retries, verifies checksums where the vendor publishes them, and installs.

The Dockerfile ends with a smoke test that fails the build if any tool is missing, and each workflow run uploads `tools.lock.json` as an artifact so you can see exactly what shipped. To build locally, run `./resolve-tools.ps1` first (set `GH_TOKEN` to avoid API rate limits), then `docker build`.

## Environment variables

| Environment Variable | Description |
| -------------------- | ----------- |
| `RUNNER_NAME` | The name of the runner to use. Overrides `RUNNER_NAME_PREFIX` |
| `RUNNER_NAME_PREFIX` | A prefix for runner name. Note: will be overridden by `RUNNER_NAME` if provided. Defaults to `windows-runner` |
| `ACCESS_TOKEN` | A [github PAT](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token) to use to generate `RUNNER_TOKEN` dynamically at container start. Not using this requires a valid `RUNNER_TOKEN` |
| `RUNNER_TOKEN` | If not using a PAT for `ACCESS_TOKEN` this will be the runner token provided by the Add Runner UI (a manual process). Note: This token is short lived and will change frequently. `ACCESS_TOKEN` is likely preferred. |
| `RUNNER_SCOPE` | The scope the runner will be registered on. Valid values are `repo`, `org` and `enterprise`. For 'org' and 'enterprise' the `REPO_URL` is unnecessary. If 'org', requires `ORG_NAME`; if 'enterprise', requires `ENTERPRISE_NAME`. Default is 'repo'. |
| `ORG_NAME` | The organization name for the runner to register under. Requires `RUNNER_SCOPE` to be 'org'. No default value. |
| `ENTERPRISE_NAME` | The enterprise name for the runner to register under. Requires `RUNNER_SCOPE` to be 'enterprise'. No default value. |
| `LABELS` | A comma separated string to indicate the labels. Default is 'default' |
| `REPO_URL` | If using a non-organization runner this is the full repository url to register under such as 'https://github.com/tiobe/repo' |
| `RUNNER_GROUP` | Name of the runner group to add this runner to (defaults to the default runner group) |
| `GITHUB_HOST` | Optional URL of the Github Enterprise server e.g github.mycompany.com. Defaults to `github.com`. |
| `DISABLE_AUTO_UPDATE` | Optional environment variable to [disable auto updates](https://github.blog/changelog/2022-02-01-github-actions-self-hosted-runners-can-now-disable-automatic-updates/). Auto updates are enabled by default to preserve past behavior. Any value is considered truthy and will disable them. |