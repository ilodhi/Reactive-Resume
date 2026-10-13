#Requires -Version 5.1
<#
.SYNOPSIS
  LEGACY / ABANDONED — Offline Windows installer for Reactive Resume.

.DESCRIPTION
  This path is no longer supported. Deploy the web app on Vercel instead
  (see the repository root README).

  The last maintained full installer lived in git history on the previous
  launcher-only main branch of ilodhi/Resume-builder (setup.ps1 + setup.cmd).
  It had PowerShell parse / elevation issues for Adam and was replaced by the
  Vercel web deployment of Reactive Resume v6.

.NOTES
  Do not run this as a primary install path.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host 'This Windows offline installer is abandoned.' -ForegroundColor Yellow
Write-Host 'Use the Vercel web app instead — see README.md at the repo root.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  https://github.com/ilodhi/Resume-builder' -ForegroundColor Cyan
Write-Host ''
exit 1
