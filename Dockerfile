FROM mcr.microsoft.com/windows/servercore:ltsc2025

# Optional: Override runner version (defaults to latest if not specified)
ARG RUNNER_VERSION

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop';"]

# Set working directory
WORKDIR /actions-runner

# Tools are downloaded directly from vendor release channels as resolved in
# tools.lock.json (see resolve-tools.ps1), with SHA256 verification where the
# vendor publishes checksums
COPY install-tools.ps1 tools.lock.json ./
RUN .\install-tools.ps1; Remove-Item .\install-tools.ps1, .\tools.lock.json -Force

# Add MSBuild to the path
RUN [Environment]::SetEnvironmentVariable(\"Path\", $env:Path + \";C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\", \"Machine\")

COPY install-runner.ps1 .
RUN .\install-runner.ps1; Remove-Item .\install-runner.ps1 -Force

COPY entrypoint.ps1 .

# Fail the build if any tool is missing or not on PATH - an install step that
# exits 0 without delivering its package must not produce a pushable image
RUN pwsh -Command '$PSVersionTable.PSVersion'; git --version; bash --version; gh --version; python --version; pip --version; docker --version

ENTRYPOINT ["pwsh.exe", ".\\entrypoint.ps1"]
