# Fetch the latest GitHub Actions runner version if not specified
if ($null -eq $env:RUNNER_VERSION) {
  Write-Host "Fetching latest GitHub Actions runner version..."
  try {
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest" -Headers @{ "User-Agent" = "PowerShell" }
    $RUNNER_VERSION = $latestRelease.tag_name.TrimStart('v')
    Write-Host "Latest runner version: $RUNNER_VERSION"
  } catch {
    Write-Error "Failed to fetch latest runner version: $($_.Exception.Message)"
    Write-Host "Falling back to default version 2.311.0"
    $RUNNER_VERSION = "2.311.0"
  }
} else {
  $RUNNER_VERSION = $env:RUNNER_VERSION
  Write-Host "Using specified runner version: $RUNNER_VERSION"
}

Write-Host "Downloading GitHub Actions runner v$RUNNER_VERSION..."
Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-win-x64-$RUNNER_VERSION.zip" -OutFile "actions-runner.zip"
Expand-Archive -Path ".\\actions-runner.zip" -DestinationPath '.'