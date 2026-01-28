
<# 
.SYNOPSIS
  MECM Task Sequence friendly installer for winget:
  - Checks if winget exists; if missing, re-registers App Installer,
    then installs App Installer (with dependencies) online or offline.
  - Non-interactive, logs to SMSTS log path when available.

.PARAMETER Mode
  Auto (default) = Try online (aka.ms → GitHub). If offline content present, fallback to Offline.
  Online         = Force online flow.
  Offline        = Use local content only (see -ContentPath).

.PARAMETER ContentPath
  Folder containing:
    - Microsoft.DesktopAppInstaller_*.msixbundle
    - DesktopAppInstaller_Dependencies.zip
  (Files can be downloaded from the official winget GitHub Releases.) 

.PARAMETER Force
  Force re-install attempt even if winget is detected.

.NOTES
  Run as SYSTEM inside TS (post-OS). 
  Winget is delivered via App Installer (Microsoft.DesktopAppInstaller_8wekyb3d8bbwe). 
#>

[CmdletBinding()]
param(
  [ValidateSet('Auto','Online','Offline')]
  [string]$Mode = 'Auto',
  [string]$ContentPath,
  [switch]$Force
)

# --- Logging setup ------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$LogRoot = if ($env:SMSTSLogPath) { $env:SMSTSLogPath } else { 'C:\Windows\Temp' }
$LogFile = Join-Path $LogRoot 'Winget-Install.log'
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

$script:LogLock = New-Object object
function Write-Log {
  param([string]$Message, [ValidateSet('INFO','WARN','ERROR')] [string]$Level='INFO')
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $line = "[$ts][$Level] $Message"
  # Console (TS will capture stdout)
  Write-Host $line
  # File
  [System.Threading.Monitor]::Enter($script:LogLock)
  try { Add-Content -Path $LogFile -Value $line } finally { [System.Threading.Monitor]::Exit($script:LogLock) }
}

function Test-AdminOrSystem {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return $true }
  } catch {}
  return $false
}

if (-not (Test-AdminOrSystem)) {
  Write-Log "This script must run elevated. (In TS it runs as SYSTEM.)" 'ERROR'
  exit 1
}

# --- Utility checks -----------------------------------------------------------
function Test-Winget {
  try {
    $v = & winget --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $v) { return $true }
  } catch {}
  # Fallback: search the WindowsApps install path
  try {
    $cand = Get-ChildItem "C:\Program Files\WindowsApps" -Recurse -Filter winget.exe -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand -and (Test-Path $cand.FullName)) {
      $v2 = & "$($cand.FullName)" --version 2>$null
      if ($LASTEXITCODE -eq 0 -and $v2) { return $true }
    }
  } catch {}
  return $false
}

function ReRegister-AppInstaller {
  Write-Log "Re-registering App Installer (Microsoft.DesktopAppInstaller_8wekyb3d8bbwe) ..."
  Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
}

function Install-FromAka {
  Write-Log "Installing/Updating App Installer via aka.ms/getwinget ..."
  Add-AppxPackage https://aka.ms/getwinget
}

function Get-GitHubReleaseAssets {
  Write-Log "Querying latest winget release assets (GitHub API) ..."
  $rel = Invoke-RestMethod https://api.github.com/repos/microsoft/winget-cli/releases/latest
  return $rel.assets
}

function Install-DependenciesZip {
  param(
    [Parameter(Mandatory=$true)][string]$DownloadDir,
    [Parameter(Mandatory=$true)][Object[]]$Assets
  )
  $dep = $Assets | Where-Object { $_.name -match 'Dependencies\.zip$' } | Select-Object -First 1
  if (-not $dep) { throw "Dependencies.zip asset not found in release." }

  $zip = Join-Path $DownloadDir $dep.name
  Invoke-WebRequest $dep.browser_download_url -OutFile $zip -UseBasicParsing

  $ext = Join-Path $DownloadDir 'deps'
  if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $ext

  $pkgs = Get-ChildItem $ext -Recurse -Include *.appx,*.msix -ErrorAction SilentlyContinue
  foreach ($p in $pkgs) {
    try {
      Write-Log "Installing dependency: $($p.Name)"
      Add-AppxPackage $p.FullName
    } catch {
      Write-Log "Dependency install warning ($($p.Name)): $($_.Exception.Message)" 'WARN'
    }
  }
}

function Install-FromGitHubOnline {
  Write-Log "Installing App Installer (winget) from GitHub Releases ..."
  $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("winget_install_" + [guid]::NewGuid())) -Force
  try {
    $assets = Get-GitHubReleaseAssets
    $bundle = $assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1
    if (-not $bundle) { throw "No .msixbundle found in latest release." }

    $msix = Join-Path $tmp.FullName $bundle.name
    Invoke-WebRequest $bundle.browser_download_url -OutFile $msix -UseBasicParsing

    try {
      Add-AppxPackage -Path $msix
    } catch {
      Write-Log "Primary install failed ($($_.Exception.Message)); installing dependencies and retrying ..." 'WARN'
      Install-DependenciesZip -DownloadDir $tmp.FullName -Assets $assets
      Add-AppxPackage -Path $msix
    }
  } finally {
    try { Remove-Item $tmp.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
}

function Install-FromLocal {
  param([Parameter(Mandatory=$true)][string]$Path)
  Write-Log "Installing from local content: $Path"
  if (-not (Test-Path $Path)) { throw "ContentPath does not exist: $Path" }

  $bundle = Get-ChildItem $Path -Filter *.msixbundle -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $bundle) { throw "Missing Microsoft.DesktopAppInstaller_*.msixbundle in $Path" }

  $depsZip = Get-ChildItem $Path -Filter DesktopAppInstaller_Dependencies.zip -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($depsZip) {
    Write-Log "Found dependencies zip; installing dependencies first..."
    $tmp = Join-Path $env:TEMP ("winget_deps_" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
      Copy-Item $depsZip.FullName (Join-Path $tmp $depsZip.Name)
      Expand-Archive -Path (Join-Path $tmp $depsZip.Name) -DestinationPath (Join-Path $tmp 'deps') -Force
      $pkgs = Get-ChildItem (Join-Path $tmp 'deps') -Recurse -Include *.appx,*.msix -ErrorAction SilentlyContinue
      foreach ($p in $pkgs) {
        try {
          Write-Log "Installing dependency: $($p.Name)"
          Add-AppxPackage $p.FullName
        } catch {
          Write-Log "Dependency install warning ($($p.Name)): $($_.Exception.Message)" 'WARN'
        }
      }
    } finally {
      try { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
  } else {
    Write-Log "No dependencies zip found; proceeding with bundle only..." 'WARN'
  }

  Write-Log "Installing App Installer bundle: $($bundle.Name)"
  Add-AppxPackage -Path $bundle.FullName
}

# --- MAIN --------------------------------------------------------------------
Write-Log "Winget install: Mode=$Mode; ContentPath=$ContentPath; Force=$Force"
if (-not $Force -and (Test-Winget)) {
  $v = & winget --version
  Write-Log "winget already present (version: $v). Exiting."
  exit 0
}

# Step 1: Re-register App Installer
try {
  ReRegister-AppInstaller
  Start-Sleep -Seconds 2
  if (Test-Winget) { Write-Log "winget available after re-register."; & winget --info | Out-Null; exit 0 }
} catch {
  Write-Log "Re-register failed: $($_.Exception.Message)" 'WARN'
}

# Resolve execution path for install
$didInstall = $false
switch ($Mode) {
  'Online' {
    try { Install-FromAka; $didInstall = $true } catch { Write-Log "aka.ms/getwinget failed: $($_.Exception.Message)" 'WARN' }
    if (-not (Test-Winget)) {
      try { Install-FromGitHubOnline; $didInstall = $true } catch { Write-Log "GitHub install failed: $($_.Exception.Message)" 'WARN' }
    }
  }
  'Offline' {
    if (-not $ContentPath) { Write-Log "Offline mode requires -ContentPath." 'ERROR'; exit 1 }
    try { Install-FromLocal -Path $ContentPath; $didInstall = $true } catch { Write-Log "Local install failed: $($_.Exception.Message)" 'ERROR' }
  }
  default { # Auto
    # Try online first
    try { Install-FromAka; $didInstall = $true } catch { Write-Log "aka.ms/getwinget failed: $($_.Exception.Message)" 'WARN' }
    if (-not (Test-Winget)) {
      try { Install-FromGitHubOnline; $didInstall = $true } catch { Write-Log "GitHub install failed: $($_.Exception.Message)" 'WARN' }
    }
    # Fallback to local if provided
    if (-not (Test-Winget) -and $ContentPath) {
      try { Install-FromLocal -Path $ContentPath; $didInstall = $true } catch { Write-Log "Local install failed: $($_.Exception.Message)" 'ERROR' }
    }
  }
}

Start-Sleep -Seconds 2
if (Test-Winget) {
  Write-Log "SUCCESS: winget is installed and callable."
  & winget --info 2>&1 | ForEach-Object { Write-Log $_ }
  exit 0
} else {
  Write-Log "FAILED: winget is still not available after all attempts." 'ERROR'
  exit 1
}
