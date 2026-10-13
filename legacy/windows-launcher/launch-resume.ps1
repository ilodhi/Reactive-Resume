#Requires -Version 5.1
<#
.SYNOPSIS
  Offline desktop lifecycle for Reactive Resume on Windows 11.

.DESCRIPTION
  1. Finds and starts the local PostgreSQL Windows service (postgresql* pattern).
  2. Starts `pnpm start` (production Node server) with a hidden window.
  3. Waits until http://localhost:3000/api/health (or APP_URL) is ready.
  4. Opens Edge (preferred) or Chrome in chromeless --app mode.
  5. When that browser window/process exits: stops the Node process tree we
     started, then stops the PostgreSQL Windows service for zero footprint.

.NOTES
  Place this script (and run-app.vbs) in the Reactive Resume repository root —
  the same folder as package.json — OR set $AppRoot below.

  Production start reads the root `.env` file (not `.env.local`).
  Build once first:  pnpm install && pnpm build

  Run elevated (Administrator) so Start-Service / Stop-Service work.
  The desktop shortcut to run-app.vbs should have "Run as administrator" enabled.

  ZERO-FOOTPRINT POSTGRES:
  On browser close this script ALWAYS stops the detected PostgreSQL Windows
  service so nothing keeps running in the background. If you also use that
  same Postgres instance for other apps, they will lose the DB until you start
  the service again (Services.msc or launch this script).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Configuration (edit if needed)
# =============================================================================

# Leave empty to auto-detect: script directory if it contains Reactive Resume's
# package.json; otherwise the parent of this script. Override with an absolute
# path if these launcher files live outside the app checkout.
$AppRoot = ''

# Must match PORT / APP_URL in .env (Reactive Resume production default: 3000).
$AppPort = 3000
$AppUrl = "http://localhost:$AppPort"
$HealthUrl = "$AppUrl/api/health"

# How long to wait for the Node server after launch.
$ReadyTimeoutSec = 120
$ReadyPollMs = 500

# Dedicated Chromium profile so the --app window is isolated and easier to track.
$BrowserProfileDirName = 'reactive-resume-desktop-profile'

# Log file (hidden launch has no console). Same folder as this script.
$LogPath = Join-Path $PSScriptRoot 'launch-resume.log'

# =============================================================================
# Helpers
# =============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {
        # Logging must never abort teardown.
    }
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-AppRoot {
    param([string]$Configured)

    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
        $resolved = [System.IO.Path]::GetFullPath($Configured)
        if (-not (Test-Path -LiteralPath $resolved)) {
            throw "APP_ROOT does not exist: $resolved"
        }
        return $resolved
    }

    $candidates = @(
        $PSScriptRoot,
        (Split-Path -Parent $PSScriptRoot)
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($dir in $candidates) {
        $pkg = Join-Path $dir 'package.json'
        if (Test-Path -LiteralPath $pkg) {
            try {
                $json = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($json.name -eq 'reactive-resume') {
                    return [System.IO.Path]::GetFullPath($dir)
                }
            } catch {
                # Keep looking.
            }
            # package.json present — accept as app root even if name differs.
            return [System.IO.Path]::GetFullPath($dir)
        }
    }

    throw @"
Could not find the Reactive Resume app root.
Put launch-resume.ps1 in the cloned repo root (next to package.json),
or set `$AppRoot near the top of this script to that absolute path.
"@
}

function Find-PostgreSqlService {
    # Common Windows installer names: postgresql-x64-16, postgresql-16, etc.
    $services = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like 'postgresql*' -or $_.DisplayName -like '*PostgreSQL*'
    } | Sort-Object Name

    if (-not $services) {
        throw @"
No PostgreSQL Windows service matching 'postgresql*' was found.
Install PostgreSQL for Windows (official installer) so it registers a service,
or start your database another way and adjust this script.
"@
    }

    if (@($services).Count -gt 1) {
        Write-Log "Multiple PostgreSQL services found; using first: $($services[0].Name) ($($services[0].DisplayName))" 'WARN'
    }

    return $services[0]
}

function Start-PostgreSqlService {
    param([System.ServiceProcess.ServiceController]$Service)

    $Service.Refresh()
    if ($Service.Status -eq 'Running') {
        Write-Log "PostgreSQL service already running: $($Service.Name)"
        return $false
    }

    if (-not (Test-IsAdministrator)) {
        throw @"
Administrator rights are required to start Windows service '$($Service.Name)'.
Enable 'Run as administrator' on the desktop shortcut to run-app.vbs.
"@
    }

    Write-Log "Starting PostgreSQL service: $($Service.Name)"
    Start-Service -Name $Service.Name
    $Service.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
    Write-Log "PostgreSQL service is Running: $($Service.Name)"
    return $true
}

function Stop-PostgreSqlService {
    param([System.ServiceProcess.ServiceController]$Service)

    # ZERO FOOTPRINT (requested): always stop the local Postgres service when
    # the desktop window closes, even if it was already running before launch.
    # Tradeoff: other apps using this same Postgres instance lose the DB until
    # the service is started again.
    if (-not $Service) { return }

    try {
        $Service.Refresh()
        if ($Service.Status -eq 'Stopped') {
            Write-Log "PostgreSQL service already stopped: $($Service.Name)"
            return
        }

        if (-not (Test-IsAdministrator)) {
            Write-Log "Not elevated — cannot stop PostgreSQL service $($Service.Name). Stop it manually in services.msc." 'WARN'
            return
        }

        Write-Log "Stopping PostgreSQL service for zero footprint: $($Service.Name)"
        Stop-Service -Name $Service.Name -Force -ErrorAction Stop
        $Service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
        Write-Log "PostgreSQL service stopped: $($Service.Name)"
    } catch {
        Write-Log "Failed to stop PostgreSQL service: $($_.Exception.Message)" 'ERROR'
    }
}

function Test-AppReady {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        return $false
    }
}

function Wait-ForAppReady {
    param(
        [string]$Url,
        [int]$TimeoutSec,
        [int]$PollMs
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-AppReady -Url $Url) {
            return $true
        }
        Start-Sleep -Milliseconds $PollMs
    }
    return $false
}

function Find-PnpmCommand {
    # Elevated sessions often lose user-scoped PATH (fnm/nvm-windows/pnpm).
    $cmd = Get-Command pnpm.cmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:APPDATA 'npm\pnpm.cmd'),
        (Join-Path $env:LOCALAPPDATA 'pnpm\pnpm.cmd'),
        (Join-Path $env:ProgramFiles 'nodejs\pnpm.cmd'),
        (Join-Path ${env:ProgramFiles(x86)} 'nodejs\pnpm.cmd')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    if ($candidates) { return $candidates[0] }

    throw @"
pnpm was not found on PATH (common when the shortcut runs elevated).
Fix: add Node.js and pnpm to the *system* PATH, or install pnpm globally
with an elevated terminal:  npm install -g pnpm
"@
}

function Start-HiddenNodeServer {
    param(
        [string]$Root,
        [string]$PnpmPath
    )

    $serverEntry = Join-Path $Root 'apps\server\dist\index.mjs'
    if (-not (Test-Path -LiteralPath $serverEntry)) {
        throw @"
Production build not found: $serverEntry
From the Reactive Resume root run:
  pnpm install
  pnpm build
Then try again.
"@
    }

    $envFile = Join-Path $Root '.env'
    if (-not (Test-Path -LiteralPath $envFile)) {
        throw "Missing .env in $Root — copy .env.example to .env and configure it first."
    }

    # Prefer invoking node on the built server so the tracked root PID is the
    # actual Node process (not a pnpm wrapper). Still use pnpm if node missing.
    $nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
    $fileName = $null
    $arguments = $null

    if ($nodeCmd) {
        $fileName = $nodeCmd.Source
        $arguments = "`"$serverEntry`""
    } else {
        $fileName = $PnpmPath
        $arguments = 'start'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $fileName
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    # Ensure production mode for `pnpm start` / single-port listen on PORT.
    # Windows PowerShell 5.1 uses EnvironmentVariables; PowerShell 7+ also accepts it.
    $psi.EnvironmentVariables['NODE_ENV'] = 'production'

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $null = $proc.Start()
    Write-Log "Started Node server PID $($proc.Id) ($fileName $arguments)"

    # Async drain so the process cannot block on full stdout/stderr pipes.
    $outLog = Join-Path $PSScriptRoot 'launch-resume-server.out.log'
    Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action {
        if ($EventArgs.Data) {
            Add-Content -LiteralPath $Event.MessageData -Value $EventArgs.Data -Encoding UTF8
        }
    } -MessageData $outLog | Out-Null
    Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data) {
            Add-Content -LiteralPath $Event.MessageData -Value $EventArgs.Data -Encoding UTF8
        }
    } -MessageData $outLog | Out-Null
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    return $proc
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if (-not $Process) { return }

    $pidToKill = $Process.Id
    try {
        if ($Process.HasExited) {
            Write-Log "Node process $pidToKill already exited"
            return
        }
    } catch {
        # Process object may be stale.
    }

    Write-Log "Stopping Node process tree rooted at PID $pidToKill"
    try {
        # /T = kill child processes as well. Scoped to our tracked root PID only.
        & taskkill.exe /PID $pidToKill /T /F 2>$null | Out-Null
    } catch {
        Write-Log "taskkill failed for PID $pidToKill : $($_.Exception.Message)" 'WARN'
        try { Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Find-BrowserExecutable {
    $edgeCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
    )
    foreach ($path in $edgeCandidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return @{ Name = 'Edge'; Path = $path }
        }
    }

    $chromeCandidates = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($path in $chromeCandidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return @{ Name = 'Chrome'; Path = $path }
        }
    }

    throw 'Neither Microsoft Edge nor Google Chrome was found. Install one of them.'
}

function Start-AppBrowser {
    param(
        [string]$Url,
        [string]$ProfileDir
    )

    $browser = Find-BrowserExecutable
    if (-not (Test-Path -LiteralPath $ProfileDir)) {
        New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    }

    # Chromeless standalone window. Dedicated --user-data-dir keeps this
    # process distinct from the user's everyday browser sessions.
    $args = @(
        "--app=$Url",
        "--user-data-dir=$ProfileDir",
        '--no-first-run',
        '--no-default-browser-check'
    )

    Write-Log "Opening $($browser.Name) app window: $Url"
    $proc = Start-Process -FilePath $browser.Path -ArgumentList $args -PassThru
    return $proc
}

function Read-PortFromEnv {
    param([string]$Root, [int]$Fallback)

    $envPath = Join-Path $Root '.env'
    if (-not (Test-Path -LiteralPath $envPath)) { return $Fallback }

    try {
        foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8) {
            if ($line -match '^\s*PORT\s*=\s*"?(\d+)"?\s*$') {
                return [int]$Matches[1]
            }
        }
    } catch {
        Write-Log "Could not parse PORT from .env; using $Fallback" 'WARN'
    }
    return $Fallback
}

# =============================================================================
# Main
# =============================================================================

$postgresService = $null
$nodeProcess = $null
$startedNode = $false
$browserProcess = $null
$exitCode = 0

try {
    Write-Log '=== launch-resume starting ==='

    if (-not (Test-IsAdministrator)) {
        Write-Log 'Not running as Administrator — service start/stop may fail.' 'WARN'
    }

    $root = Resolve-AppRoot -Configured $AppRoot
    Write-Log "App root: $root"

    $AppPort = Read-PortFromEnv -Root $root -Fallback $AppPort
    $AppUrl = "http://localhost:$AppPort"
    $HealthUrl = "$AppUrl/api/health"
    Write-Log "Target URL: $AppUrl (health: $HealthUrl)"

    $postgresService = Find-PostgreSqlService
    Write-Log "Using PostgreSQL service: $($postgresService.Name)"
    $null = Start-PostgreSqlService -Service $postgresService

    $alreadyReady = Test-AppReady -Url $HealthUrl
    if ($alreadyReady) {
        Write-Log 'App already responding — reusing existing server (will not kill it on exit).'
    } else {
        $pnpm = Find-PnpmCommand
        Write-Log "pnpm: $pnpm"
        $nodeProcess = Start-HiddenNodeServer -Root $root -PnpmPath $pnpm
        $startedNode = $true

        if (-not (Wait-ForAppReady -Url $HealthUrl -TimeoutSec $ReadyTimeoutSec -PollMs $ReadyPollMs)) {
            throw @"
Reactive Resume did not become ready at $HealthUrl within ${ReadyTimeoutSec}s.
Check launch-resume.log and launch-resume-server.out.log, confirm PostgreSQL
is reachable via DATABASE_URL, and that `pnpm build` has been run.
"@
        }
        Write-Log 'App is ready.'
    }

    $profileDir = Join-Path $env:LOCALAPPDATA $BrowserProfileDirName
    $browserProcess = Start-AppBrowser -Url $AppUrl -ProfileDir $profileDir

    Write-Log "Waiting for browser PID $($browserProcess.Id) to exit..."
    Wait-Process -Id $browserProcess.Id
    Write-Log 'Browser window closed.'
}
catch {
    $exitCode = 1
    $msg = $_.Exception.Message
    Write-Log $msg 'ERROR'
    try {
        # Visible error when launched via silent VBS.
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            $msg,
            'Reactive Resume launcher failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {
        # Last resort: still leave the log.
    }
}
finally {
    if ($startedNode) {
        Stop-ProcessTree -Process $nodeProcess
    } else {
        Write-Log 'Skipped Node teardown (server was already running before this launch).'
    }

    Stop-PostgreSqlService -Service $postgresService
    Write-Log "=== launch-resume finished (exit $exitCode) ==="
}

exit $exitCode
