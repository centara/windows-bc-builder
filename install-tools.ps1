# Installs the tools pinned in tools.lock.json (produced by resolve-tools.ps1).
# Runs inside docker build under Windows PowerShell 5.1 - keep 5.1-compatible.
# Downloads are retried; SHA256 is verified whenever the vendor publishes one.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-DownloadWithRetry([string]$Uri, [string]$OutFile) {
    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            return
        } catch {
            if ($attempt -eq $maxAttempts) { throw }
            $delay = 15 * $attempt
            Write-Host "Download failed (attempt $attempt/$maxAttempts): $($_.Exception.Message). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Assert-Sha256([string]$Path, [string]$Expected, [string]$Name) {
    if (-not $Expected) {
        Write-Host "  no vendor checksum published for $Name, skipping verification"
        return
    }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $Expected.ToLower()) {
        throw "SHA256 mismatch for ${Name}: expected $Expected, got $actual"
    }
    Write-Host "  sha256 verified"
}

function Invoke-Installer([string]$FilePath, [string[]]$InstallerArgs) {
    $proc = Start-Process -FilePath $FilePath -ArgumentList $InstallerArgs -Wait -PassThru
    # 3010 = success, reboot required (fine inside an image build)
    if ($proc.ExitCode -notin 0, 3010) {
        throw "Installer $FilePath exited with code $($proc.ExitCode)"
    }
}

function Add-MachinePath([string]$Dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($current -notlike "*$Dir*") {
        [Environment]::SetEnvironmentVariable('Path', "$current;$Dir", 'Machine')
    }
}

$lock = Get-Content -Path "$PSScriptRoot\tools.lock.json" -Raw | ConvertFrom-Json
$downloadDir = Join-Path $env:TEMP 'tool-installers'
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

foreach ($tool in $lock.tools) {
    Write-Host "Installing $($tool.name) $($tool.version)..."
    $file = Join-Path $downloadDir ([IO.Path]::GetFileName(([Uri]$tool.url).LocalPath))
    Invoke-DownloadWithRetry -Uri $tool.url -OutFile $file
    Assert-Sha256 -Path $file -Expected $tool.sha256 -Name $tool.name

    switch ($tool.name) {
        'powershell' {
            Invoke-Installer 'msiexec.exe' @('/i', $file, '/qn', '/norestart')
        }
        'git' {
            Invoke-Installer $file @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-')
            # bash.exe lives in Git\bin, which the installer does not put on PATH;
            # workflows using `shell: bash` need it resolvable
            Add-MachinePath 'C:\Program Files\Git\bin'
        }
        'gh' {
            Invoke-Installer 'msiexec.exe' @('/i', $file, '/qn', '/norestart')
        }
        'docker' {
            $extractDir = Join-Path $downloadDir 'docker-cli'
            Expand-Archive -Path $file -DestinationPath $extractDir
            $target = 'C:\Program Files\DockerCLI'
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            # Only the client is needed; dockerd from the zip stays out of the image
            Copy-Item -Path (Join-Path $extractDir 'docker\docker.exe') -Destination $target
            Add-MachinePath $target
        }
        'python' {
            Invoke-Installer $file @('/quiet', 'InstallAllUsers=1', 'PrependPath=1')
        }
        default {
            throw "Unknown tool '$($tool.name)' in tools.lock.json"
        }
    }
    Write-Host "  $($tool.name) $($tool.version) installed"
}

Remove-Item -Path $downloadDir -Recurse -Force
