# Resolves the latest version, download URL and SHA256 for each tool baked into
# the image, and writes tools.lock.json for install-tools.ps1 to consume.
# Runs in the workflow (not in docker build) so GitHub API calls are
# authenticated via GH_TOKEN; unauthenticated calls from shared CI IPs get
# rate-limited, which is the failure mode this replaces.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$apiHeaders = @{ 'User-Agent' = 'PowerShell' }
if ($env:GH_TOKEN) { $apiHeaders['Authorization'] = "Bearer $($env:GH_TOKEN)" }

function Get-LatestRelease([string]$Repo) {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $apiHeaders
}

function Get-AssetUrl($Release, [string]$Name) {
    $asset = $Release.assets | Where-Object { $_.name -eq $Name }
    if (-not $asset) { throw "Asset '$Name' not found in release $($Release.tag_name)" }
    $asset.browser_download_url
}

function Get-RemoteText([string]$Uri) {
    # BOM-aware decode; PowerShell's hashes.sha256 is UTF-16LE, which
    # Invoke-RestMethod would silently mangle
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $tmp -UseBasicParsing -Headers @{ 'User-Agent' = 'PowerShell' }
        [IO.File]::ReadAllText($tmp)
    } finally {
        Remove-Item $tmp -Force
    }
}

function Find-Sha256([string]$Text, [string]$AssetName) {
    # Matches "<hash> *<name>", "<hash>  <name>" and "<name> | <hash>"
    $escaped = [regex]::Escape($AssetName)
    foreach ($pattern in @("(?m)^([0-9a-fA-F]{64})\s+\*?$escaped\s*$", "(?m)$escaped\s*\|\s*([0-9a-fA-F]{64})")) {
        $m = [regex]::Match($Text, $pattern)
        if ($m.Success) { return $m.Groups[1].Value.ToLower() }
    }
    throw "SHA256 for '$AssetName' not found in checksum text"
}

$tools = @()

# --- PowerShell (MSI, hashes.sha256 asset) ---
$rel = Get-LatestRelease 'PowerShell/PowerShell'
$ver = $rel.tag_name.TrimStart('v')
$assetName = "PowerShell-$ver-win-x64.msi"
$hashText = Get-RemoteText (Get-AssetUrl $rel 'hashes.sha256')
$tools += @{ name = 'powershell'; version = $ver; url = (Get-AssetUrl $rel $assetName); sha256 = (Find-Sha256 $hashText $assetName) }

# --- Git for Windows (Inno Setup installer, SHA256 table in release notes) ---
$rel = Get-LatestRelease 'git-for-windows/git'
$ver = $rel.tag_name.TrimStart('v') -replace '\.windows\.\d+$', ''
$assetName = ($rel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1).name
if (-not $assetName) { throw "No 64-bit Git installer asset found in release $($rel.tag_name)" }
$tools += @{ name = 'git'; version = $ver; url = (Get-AssetUrl $rel $assetName); sha256 = (Find-Sha256 $rel.body $assetName) }

# --- GitHub CLI (MSI, checksums.txt asset) ---
$rel = Get-LatestRelease 'cli/cli'
$ver = $rel.tag_name.TrimStart('v')
$assetName = "gh_${ver}_windows_amd64.msi"
$hashText = Get-RemoteText (Get-AssetUrl $rel "gh_${ver}_checksums.txt")
$tools += @{ name = 'gh'; version = $ver; url = (Get-AssetUrl $rel $assetName); sha256 = (Find-Sha256 $hashText $assetName) }

# --- Docker CLI (static zip from download.docker.com; no checksum published) ---
$index = Invoke-WebRequest -Uri 'https://download.docker.com/win/static/stable/x86_64/' -UseBasicParsing
$latestZip = [regex]::Matches($index.Content, 'docker-(\d+\.\d+\.\d+)\.zip') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } | Select-Object -Last 1
$tools += @{ name = 'docker'; version = $latestZip; url = "https://download.docker.com/win/static/stable/x86_64/docker-$latestZip.zip"; sha256 = $null }

# --- Python (python.org full installer; python.org publishes no flat SHA256) ---
# The python.org FTP index lists every release directory in one response;
# prerelease-only versions are filtered out by HEAD-checking the final installer.
$index = Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/' -UseBasicParsing
$finalVersions = [regex]::Matches($index.Content, 'href="(3\.\d+\.\d+)/"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Unique -Descending
$pythonTool = $null
foreach ($ver in $finalVersions) {
    $url = "https://www.python.org/ftp/python/$ver/python-$ver-amd64.exe"
    try {
        Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing | Out-Null
        $pythonTool = @{ name = 'python'; version = $ver; url = $url; sha256 = $null }
        break
    } catch {
        Write-Host "No Windows installer for Python $ver yet, trying next"
    }
}
if (-not $pythonTool) { throw 'Could not resolve a Python version with a Windows installer' }
$tools += $pythonTool

# --- GitHub Actions runner version (consumed as a docker build arg) ---
$runnerVersion = (Get-LatestRelease 'actions/runner').tag_name.TrimStart('v')

$lock = @{ runner = $runnerVersion; tools = $tools }
$lock | ConvertTo-Json -Depth 5 | Set-Content -Path 'tools.lock.json' -Encoding UTF8

Write-Host "Resolved runner v$runnerVersion and tools:"
$tools | ForEach-Object {
    $sha = if ($_.sha256) { $_.sha256 } else { '<none published>' }
    Write-Host ("  {0,-12} {1,-12} sha256={2}" -f $_.name, $_.version, $sha)
}
