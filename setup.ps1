#Requires -Version 7.0
<#
.SYNOPSIS
    Stand-alone workstation setup. Copy this one folder and run it under
    PowerShell 7.

.DESCRIPTION
    PowerShell 7 is the baseline, not a target. This script does not install
    it and does not fall back to Windows PowerShell 5.1. Install PowerShell 7
    from the Microsoft Store first, then run this from a pwsh prompt.

    ASCII-only. No non-ASCII character appears anywhere in this file, so it
    parses the same whether it is saved with a BOM or without one. Line endings
    are CRLF throughout.

    Nothing here reaches outside this folder. The certificate seed, the corp
    root, the docker hook and the skills all ship in the tree next to this
    file, so a copy of the folder onto a USB stick is a complete installer.

    Phases:
      0. Preflight     - pwsh version, payload, winget, admin check
      1. CA bundle     - asked for with Y/N at launch, then bake certs\ into
                         one PEM and set the cert env vars
      2. Programs      - Python 3.12 (pinned), git, Node.js LTS, via winget
      3. Libraries     - requirements.txt into the pinned Python
      4. Claude Code   - user profile, never elevated
      5. User PATH     - %USERPROFILE%\.local\bin
      6. Terminal      - Windows Terminal font, and a shortcut that opens it
      7. Claude wiring - skills, docker hook, settings.json, permission mode
      8. Plugins       - claude plugin marketplace add + install; retire the old skill copy
      9. Verify        - a real HTTPS request through the bundle

    Certificates come first on purpose. Everything after phase 1 that reaches
    the network - the git clone of the plugin marketplace above all - crosses
    the corporate SSL inspection appliance, and on a machine whose trust is not
    yet established those transfers fail.

    Running it twice is safe. Every phase skips what is already done.

.PARAMETER BundleDir
    Where the CA bundle and the hook script are kept.
    Defaults to %LOCALAPPDATA%\corp-certs.

.PARAMETER VerifyUrl
    The address the last phase actually connects to.

.PARAMETER SettingsPath
    settings.json to merge into. Defaults to the user profile copy. Tests point
    this at a throwaway file.

.PARAMETER ClaudeJsonPath
    .claude.json to record the bypassPermissions acceptance in. Defaults to the
    user profile copy. Tests point this at a throwaway file. Without that key
    Claude Code downgrades the permission mode back to 'default'.

.PARAMETER Ssl
    Whether to install the corporate certificates. 'Auto', the default, decides
    by measurement: it opens a real TLS connection and checks whether the
    certificate chains to a public root. If something is inspecting HTTPS, the
    certificates go in; if not, they are skipped. Nobody is asked.

    'Yes' and 'No' override the measurement. A machine that later moves behind
    the appliance is fixed by running this again - the whole script is
    idempotent, so a second run costs nothing.

.PARAMETER SkipPrograms
    Skip Python 3.12, git and Node.js. Without git no plugin marketplace can be
    cloned, and without python or node the last phase cannot verify.

.PARAMETER SkipPythonLibs
    Skip the requirements.txt install. The document-formats skill (installed
    as the kw-doc-formats plugin in phase 8) calls the tools listed there, so a
    machine set up this way cannot read .pptx, .docx or .pdf even though
    every other phase went green.

.PARAMETER SkipClaudeInstall
    Skip Claude Code.

.PARAMETER SkipHooks
    Do not register the docker command hook.

.PARAMETER SkipSkills
    Do not copy skills into the personal skills folder.

.PARAMETER SkipTerminal
    Leave Windows Terminal alone: no font settings and no shortcut. Nothing
    else depends on that phase, so this costs only the convenience.

.PARAMETER SkipPlugins
    Do not install any Claude Code plugin.

.PARAMETER RespectExecutionPolicy
    Make Claude Code honor the machine execution policy instead of its own
    process-scope bypass. Leaving this off is the working default.

.PARAMETER WhatIfOnly
    Print what would happen. Write nothing, install nothing.

.PARAMETER AsModule
    Define the functions and return without running a phase. Tests dot-source
    with this.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -WhatIfOnly
#>

[CmdletBinding()]
param(
    [string]$BundleDir    = '',
    [string]$VerifyUrl    = 'https://data.krx.co.kr',
    [string]$ClaudeUrl    = 'https://api.anthropic.com',
    [string]$SettingsPath = '',
    [string]$ClaudeJsonPath = '',

    [string]$MemoryPath = '',

    [ValidateSet('Auto', 'Yes', 'No')]
    [string]$Ssl = 'Auto',

    [switch]$SkipPrograms,
    [switch]$SkipPythonLibs,
    [switch]$SkipClaudeInstall,
    [switch]$SkipHooks,
    [switch]$SkipSkills,
    [switch]$SkipTerminal,
    [switch]$SkipPlugins,

    [switch]$RespectExecutionPolicy,
    [switch]$WhatIfOnly,
    [switch]$AsModule
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot can be empty while parameter defaults are being computed, so
# the paths are resolved here in the body instead.
$ScriptDir = $PSScriptRoot ?? (Split-Path -Parent $MyInvocation.MyCommand.Definition)

if (-not $BundleDir)    { $BundleDir    = Join-Path $env:LOCALAPPDATA 'corp-certs' }
if (-not $SettingsPath)   { $SettingsPath   = Join-Path $env:USERPROFILE '.claude/settings.json' }
if (-not $ClaudeJsonPath) { $ClaudeJsonPath = Join-Path $env:USERPROFILE '.claude.json' }
if (-not $MemoryPath)     { $MemoryPath     = Join-Path $env:USERPROFILE '.claude/CLAUDE.md' }

$SeedPem      = Join-Path $ScriptDir 'certs/combined_cacert.pem'
$CorpRootCrt  = Join-Path $ScriptDir 'certs/ePrism-SSL-ROOT-CA.crt'
$HookSource   = Join-Path $ScriptDir 'hooks/docker-cert-reminder.ps1'
$SkillsDir    = Join-Path $ScriptDir 'skills'
$RequirementsPath = Join-Path $ScriptDir 'requirements.txt'

# The shortcut picture. It ships as a PNG because that is what it was drawn
# as, and the .ico a Windows shortcut needs is built from it at install time.
# Building rather than shipping both keeps one copy of the artwork in the
# payload; two would drift the first time somebody redrew only one of them.
# The built copy goes on the local disk because a shortcut pointing at the
# share would lose its picture the moment the machine left the network.
# Also where phase 8 leaves the backup of a retired skill: the one folder this installer owns.
$IconPng = Join-Path $ScriptDir 'claudecode-color.png'
$IconDir = Join-Path ($env:LOCALAPPDATA ?? $env:TEMP) 'kw-install'

# The two things a non-developer actually reads: what to do next, and who to
# contact when it goes wrong. They are Korean, and therefore not in this file.
# setup.ps1 is ASCII only because a BOM-less .ps1 carrying non-ASCII text is
# read in the system code page by Windows PowerShell and stops parsing there.
# Keeping the wording in UTF-8 files next to the script sidesteps that, and
# lets somebody reword it without touching code.
$ClosingKo     = Join-Path $ScriptDir 'templates/closing-ko.txt'
$SupportKo     = Join-Path $ScriptDir 'templates/support-ko.txt'

# The personal memory that tells Claude who it is talking to. Shipped as a
# template and merged into the user's CLAUDE.md, which is why the filename is
# ASCII even though the contents are Korean: this file cannot name it otherwise.
$MemoryTemplate = Join-Path $ScriptDir 'templates/personal-memory-ko.md'

$script:SupportContact = 'chshin84@gmail.com'

$claudeBin = Join-Path $env:USERPROFILE '.local/bin'
$claudeExe = Join-Path $claudeBin 'claude.exe'

$script:CertEnvNames = @('REQUESTS_CA_BUNDLE', 'SSL_CERT_FILE', 'PIP_CERT', 'NODE_EXTRA_CA_CERTS')
# Hosts the verdict is taken from. The appliance seen here intercepts
# selectively, so one host cannot answer for the rest: pypi.org arrives
# untouched on a network that rewrites api.anthropic.com. The API host leads
# because Claude Code cannot work without it, and because stopping at the
# first interception makes it the cheapest place to find one.
$script:ProbeHosts = @('api.anthropic.com', 'pypi.org', 'registry.npmjs.org')


# The permission posture is one line: defaultMode 'auto'. Tool calls run without
# a prompt and a classifier checks them in the background instead of a person.
#
# Nothing else is customised, on purpose. Earlier versions carried a wide allow
# list, an SSL ask gate, and a wholesale deletion of deny. All of it is gone:
#
#   - Broad allow rules did nothing anyway. On entering auto mode Claude Code
#     DROPS rules that open arbitrary execution - blanket Bash(*) and
#     PowerShell(*) among them - so the list looked like it granted something
#     and granted nothing.
#   - Rules are a second place the posture lives, and ours drifted from what
#     the product actually does. The product maintains its own; we did not.
#   - Deleting somebody's deny list is not this installer's decision to make.
#
# So what auto mode blocks - curl-pipe-shell, force push, production deploys,
# irreversible deletes of pre-existing files - is the product's call, not ours.
# `claude auto-mode defaults` prints the full list.

# Python is pinned. Libraries are installed into this version and the document
# tooling calls a bare `python`, so a different version arriving first on PATH
# means the libraries are invisible even though every install step went green.
$script:PythonVersion = '3.12'

# Order matters only in that python comes first; it is the one the CA bundle
# bake prefers (certifi) and the one the verification step reaches for.
$script:Programs = @(
    @{ Name = "Python $script:PythonVersion"; Command = 'python'; Id = "Python.Python.$script:PythonVersion"; Pinned = $true }
    @{ Name = 'git';                          Command = 'git';    Id = 'Git.Git';            Pinned = $false }
    @{ Name = 'Node.js LTS';                  Command = 'node';   Id = 'OpenJS.NodeJS.LTS';  Pinned = $false }

    # Claude Code renders a PDF page into an image with pdftoppm before it can
    # look at one. Without poppler it refuses outright - "pdftoppm is not
    # installed" - and the only way left to read a PDF is pulling the text out,
    # which loses tables and layout exactly where they matter most.
    #
    # This is what makes the cheap reading path possible: pull the text with
    # pypdf to find which pages matter, then have Claude look at only those.
    @{ Name = 'Poppler (PDF pages)';          Command = 'pdftoppm'; Id = 'oschwartz10612.Poppler'; Pinned = $false }
)

# One row per plugin. Both the settings.json declaration and the CLI install
# are generated from this list, so adding a plugin is one line and the two
# cannot drift apart.
# Three of the five come from the one official marketplace on purpose.
# superpowers and frontend-design are also published by their own marketplaces,
# and taking them from there meant a machine ended up carrying the same plugin
# twice under two marketplace names - two copies of the same skills loaded, and
# the same name listed twice for the user to pick between. Sourcing them from
# claude-plugins-official collapses that. document-skills is not in that
# marketplace, so it keeps its own. kw-doc-formats is our own document skill,
# published from its own repo; AutoUpdate is set because third-party
# marketplaces default to no auto-update and the whole point of shipping the
# skill as a plugin is that a fix reaches installed machines without a rerun.
$script:Plugins = @(
    @{ Id = 'superpowers@claude-plugins-official';      Marketplace = 'claude-plugins-official'; Repo = 'anthropics/claude-plugins-official'   }
    @{ Id = 'document-skills@anthropic-agent-skills';   Marketplace = 'anthropic-agent-skills';  Repo = 'anthropics/skills'                    }
    @{ Id = 'playwright@claude-plugins-official';       Marketplace = 'claude-plugins-official'; Repo = 'anthropics/claude-plugins-official'   }
    @{ Id = 'frontend-design@claude-plugins-official';  Marketplace = 'claude-plugins-official'; Repo = 'anthropics/claude-plugins-official'   }
    @{ Id = 'kw-doc-formats@kw-doc-formats';            Marketplace = 'kw-doc-formats';          Repo = 'KiwoomAX/KW-doc-formats'; AutoUpdate = $true }
)

# Plugin ids this installer used to declare and no longer does. Merge-ClaudeSettings
# only ever adds, so a machine that ran an earlier version keeps the old entry
# alongside the new one - which is the duplication above, still present. Naming
# them here lets the merge take exactly those back out and nothing else: a plugin
# somebody chose for themselves is never touched.
$script:RetiredPlugins = @(
    'superpowers@superpowers-marketplace'
    'frontend-design@claude-code-plugins'
)

# The one skill this installer used to copy into the personal skills folder
# and now installs as a plugin instead. A personal copy left behind loads
# twice under the same name, so phase 8 removes it - but only once the
# replacing plugin is confirmed on disk, and only if the folder holds nothing
# but the SKILL.md this installer wrote. A single record, not a list: the
# other shipped skill (register-corp-certs) stays a personal skill by design.
# ReplacedBy names the plugin id phase 8 waits for.
$script:RetiredSkill = @{ Name = 'document-formats'; ReplacedBy = 'kw-doc-formats@kw-doc-formats' }

# ---------------------------------------------------------------
# Output
# ---------------------------------------------------------------
function Write-Step  { param($m) Write-Host "`n[*] $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "    OK   $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "    WARN $m" -ForegroundColor Yellow }
function Write-Err2  { param($m) Write-Host "    FAIL $m" -ForegroundColor Red }

function Write-Banner {
    param([string[]]$Lines, [string]$Color = 'Yellow')
    $bar = '=' * 72
    Write-Host ""
    Write-Host $bar -ForegroundColor $Color
    foreach ($l in $Lines) { Write-Host "  $l" -ForegroundColor $Color }
    Write-Host $bar -ForegroundColor $Color
    Write-Host ""
}

$script:Warnings = [System.Collections.Generic.List[string]]::new()
function Add-Warning { param($m) $script:Warnings.Add($m) }

# ---------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------

# A process inherits environment variables as a snapshot taken at launch. After
# an installer edits the registry PATH, this session still holds the old value,
# so a freshly installed tool stays invisible until PATH is re-read.
function Update-SessionPath {
    $parts = @(
        [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        [Environment]::GetEnvironmentVariable('PATH', 'User')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $env:PATH = ($parts -join ';')
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    [Security.Principal.WindowsPrincipal]::new($id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# One place that knows how to drive winget, so every install phase reports
# success the same way.
function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$WingetPath,
        [switch]$Elevate
    )
    $wgArgs = @(
        'install', '--id', $Id, '--source', 'winget',
        '--exact', '--silent',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    Write-Host "     Running: winget $($wgArgs -join ' ')"
    try {
        if ($Elevate) {
            # Elevate winget alone. Elevating this whole script would install
            # Claude Code into a different administrator profile.
            Write-Host "     A UAC prompt will appear. Approve it." -ForegroundColor Yellow
            $proc = Start-Process -FilePath $WingetPath -ArgumentList $wgArgs -Verb RunAs -Wait -PassThru
            $rc = $proc.ExitCode
        } else {
            & $WingetPath @wgArgs
            $rc = $LASTEXITCODE
        }
    } catch {
        Write-Err2 "winget failed to run: $($_.Exception.Message)"
        return $false
    }

    # 0 = installed, 0x8A15002B = already current.
    if ($rc -eq 0) { Write-Ok 'winget completed (exit 0)'; return $true }
    if ($rc -eq -1978335189) { Write-Ok 'Already up to date (exit 0x8A15002B)'; return $true }
    Write-Warn2 "winget exit code $rc - install may not have completed."
    return $false
}

# Reports the minor version an interpreter answers with, as '3.12'. Silence
# means the executable did not really run - on Windows that is usually the
# Microsoft Store alias stub, which resolves and then prints an advert.
function Get-PythonMinor {
    param([string]$Exe, [string[]]$Prefix = @())
    try {
        $out = & $Exe @Prefix --version 2>&1 | Out-String
    } catch {
        return $null
    }
    if ($out -match 'Python (\d+\.\d+)') { return $Matches[1] }
    return $null
}

# The path to a specific Python version, or nothing.
#
# A `python` on PATH does not prove that python is the pinned version: another
# one may sit ahead of it. The py launcher can select a version outright, so it
# is asked first and PATH is only consulted as a fallback.
function Resolve-PinnedPython {
    param([string]$Version)
    if (Get-Command 'py' -ErrorAction SilentlyContinue) {
        if ((Get-PythonMinor -Exe 'py' -Prefix @("-$Version")) -eq $Version) {
            $exe = & py "-$Version" -c 'import sys; print(sys.executable)' 2>$null | Select-Object -First 1
            if ($exe -and (Test-Path $exe)) { return $exe }
        }
    }
    if (Get-Command 'python' -ErrorAction SilentlyContinue) {
        if ((Get-PythonMinor -Exe 'python') -eq $Version) {
            $exe = & python -c 'import sys; print(sys.executable)' 2>$null | Select-Object -First 1
            if ($exe -and (Test-Path $exe)) { return $exe }
        }
    }
    return $null
}

function Test-ProgramPresent {
    param([hashtable]$Program)
    if ($Program.Pinned) { return [bool](Resolve-PinnedPython -Version $script:PythonVersion) }
    return [bool](Get-Command $Program.Command -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------
# Python libraries
# ---------------------------------------------------------------

# requirements.txt is the source of truth for the library list; this only
# reduces it to bare distribution names so the result can be reported and
# checked. Split on "`n" alone - PowerShell's line splitting also breaks on
# U+2028 and U+2029, which a comment could legally contain.
#
# Assign the result before counting it. The `,@(...)` return keeps an empty or
# single-item list from being unrolled away, but it also means a caller writing
# @(Get-RequirementNames ...) nests the array and always counts 1.
function Get-RequirementNames {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return ,@() }
    $names = foreach ($line in ([IO.File]::ReadAllText($Path) -split "`n")) {
        $bare = ($line -split '#')[0].Trim()
        if (-not $bare) { continue }
        ($bare -split '[\[<>=!~;]')[0].Trim()
    }
    return ,@($names)
}

# Which interpreter receives the libraries is pinned here. Calling a bare
# `python` would install into whichever version PATH happens to answer with,
# and the install then reports success while the document tooling sees nothing.
function Install-PythonLibraries {
    param([string]$RequirementsPath, [string]$Version, [switch]$WhatIfOnly)

    $names = Get-RequirementNames -Path $RequirementsPath
    if ($names.Count -eq 0) {
        return @{ Status = 'skipped'; Names = @(); Detail = "no requirements found at $RequirementsPath" }
    }
    $py = Resolve-PinnedPython -Version $Version
    if (-not $py) {
        return @{ Status = 'skipped'; Names = $names; Detail = "Python $Version is not available, so there is nowhere to put them" }
    }
    if ($WhatIfOnly) {
        return @{ Status = 'skipped'; Names = $names; Detail = "[WhatIf] would install $($names -join ', ') into $py" }
    }

    # No --upgrade. On a machine already using one of these, raising the version
    # breaks whatever depended on the old one and pip still exits 0.
    & $py -m pip install --quiet --requirement $RequirementsPath
    if ($LASTEXITCODE -ne 0) {
        return @{ Status = 'failed'; Names = $names; Python = $py
                  Detail = 'pip exited non-zero. If it reported SSL, rerun so phase 1 rebakes the bundle first.' }
    }

    # A version clash swallowed here surfaces weeks later somewhere unrelated.
    $conflicts = @(& $py -m pip check 2>&1 | Where-Object { $_ -and $_ -notmatch 'No broken requirements' })
    return @{ Status = 'installed'; Names = $names; Python = $py; Conflicts = $conflicts; Detail = $py }
}

# Windows keeps a `python` on the user PATH of every fresh machine that is not
# an interpreter: the Microsoft Store alias stub under WindowsApps. It answers
# first, opens the Store, and the libraries installed above are never found.
# Putting the pinned interpreter at the very front of the user PATH settles
# that, and settles an earlier version left on the machine along with it.
#
# The PATH goes in and comes back as a string, so the decision can be tested
# without touching the registry. Scripts\ travels with the interpreter because
# that is where pip puts the commands those libraries come with.
function Merge-PythonUserPath {
    param([string]$UserPath, [string]$PythonDir)

    $dir    = $PythonDir.TrimEnd('\')
    $wanted = @($dir, "$dir\Scripts")
    $parts  = @(($UserPath ?? '') -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # Wrapped, because Select-Object hands back a bare string when it picks one
    # and indexing that returns a character.
    $head = @($parts | Select-Object -First 2)
    if ($head.Count -eq 2 -and
        $head[0].TrimEnd('\') -eq $wanted[0] -and
        $head[1].TrimEnd('\') -eq $wanted[1]) {
        return @{ Path = $UserPath; Changed = $false; Entries = $wanted }
    }

    # Dropped from the tail before being prepended, so a rerun cannot stack up
    # a second copy of either directory.
    $rest = @($parts | Where-Object { $wanted -notcontains $_.TrimEnd('\') })
    return @{ Path = [string](@($wanted + $rest) -join ';'); Changed = $true; Entries = $wanted }
}
# The document tooling calls a bare `python`. If PATH answers with a version
# other than the one that received the libraries, every phase is green and only
# the first document job fails, which reads as an unrelated fault.
function Test-PathPython {
    param([string]$Wanted)
    if (-not (Get-Command 'python' -ErrorAction SilentlyContinue)) {
        return @{ Ok = $false; Reported = ''; Detail = 'python is not on PATH - the terminal may predate the install' }
    }
    $reported = Get-PythonMinor -Exe 'python'
    if (-not $reported) {
        return @{ Ok = $false; Reported = ''; Detail = 'python on PATH answers with no version - probably the Microsoft Store alias stub' }
    }
    if ($reported -ne $Wanted) {
        return @{ Ok = $false; Reported = $reported; Detail = "python on PATH is $reported, but the libraries went into $Wanted" }
    }
    return @{ Ok = $true; Reported = $reported; Detail = "python on PATH is $reported" }
}

# ---------------------------------------------------------------
# Certificates
# ---------------------------------------------------------------
function ConvertTo-PemBlock {
    param([byte[]]$Der, [string]$Label)
    $b64 = [Convert]::ToBase64String($Der, [Base64FormattingOptions]::InsertLineBreaks)
    $sb = [System.Text.StringBuilder]::new()
    if ($Label) { [void]$sb.AppendLine("# $Label") }
    [void]$sb.AppendLine('-----BEGIN CERTIFICATE-----')
    [void]$sb.AppendLine($b64)
    [void]$sb.AppendLine('-----END CERTIFICATE-----')
    return $sb.ToString()
}

# Every root in the Windows stores, taken wholesale. The corp root is not
# matched by name, so the day the company adds another one this follows along.
function Get-WindowsRootPem {
    $sb = [System.Text.StringBuilder]::new()
    foreach ($store in @('Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root')) {
        $certs = @()
        try { $certs = @(Get-ChildItem $store) } catch { $certs = @() }
        foreach ($c in $certs) {
            [void]$sb.Append((ConvertTo-PemBlock -Der $c.RawData -Label $c.Subject))
        }
    }
    return $sb.ToString()
}

# Prefer the machine's own certifi, fall back to the seed shipped in certs\.
function Get-PublicRootPem {
    param([string]$SeedPem)
    foreach ($exe in @('python', 'py')) {
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        $found = $null
        try {
            $found = & $exe -c 'import certifi;print(certifi.where())' 2>$null | Select-Object -First 1
        } catch {
            $found = $null
        }
        if ($found -and (Test-Path $found)) {
            return @{ Text = [IO.File]::ReadAllText($found); Source = "certifi ($found)" }
        }
    }
    if (Test-Path $SeedPem) {
        return @{ Text = [IO.File]::ReadAllText($SeedPem); Source = "bundled seed ($SeedPem)" }
    }
    throw "NO_PUBLIC_ROOTS: no certifi, and the bundled seed $SeedPem is unreadable."
}

# The corp root is optional now. certs\ ships none, and on a machine whose
# Windows store already holds the root - which is how IT deploys it - the store
# supplies it and this file is never needed. A missing file is therefore not an
# error; Build-CaBundle checks the result instead of the ingredients.
function Get-CorpRootPem {
    param([string]$CrtPath)
    if (-not $CrtPath -or -not (Test-Path $CrtPath)) { return '' }
    $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CrtPath)
    return (ConvertTo-PemBlock -Der $c.RawData -Label $c.Subject)
}

# Is there anything to build a bundle out of? The public roots ship as a seed
# and the corp root does not, so this answers "can this run do certificates at
# all" before anything tries.
function Test-CertMaterial {
    param([string]$SeedPem, [string]$CorpRootCrt)

    $hasSeed = [bool]($SeedPem -and (Test-Path $SeedPem))
    $hasCorp = [bool]($CorpRootCrt -and (Test-Path $CorpRootCrt))
    $hasCertifi = $false
    foreach ($exe in @('python', 'py')) {
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        try {
            $p = & $exe -c 'import certifi;print(certifi.where())' 2>$null | Select-Object -First 1
            if ($p -and (Test-Path $p)) { $hasCertifi = $true; break }
        } catch { }
    }
    return @{
        PublicRoots = ($hasSeed -or $hasCertifi)
        CorpRoot    = $hasCorp
        Detail      = "seed=$hasSeed certifi=$hasCertifi corp=$hasCorp"
    }
}

function Get-PemCertificates {
    param([string]$Text)
    $out = @()
    $pattern = '(?s)-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----'
    foreach ($m in [regex]::Matches($Text, $pattern)) {
        $b64 = $m.Groups[1].Value -replace '\s', ''
        try {
            $der = [Convert]::FromBase64String($b64)
            $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([byte[]]$der)
            $out += [pscustomobject]@{ Thumbprint = $c.Thumbprint; Subject = $c.Subject; Der = $c.RawData }
        } catch {
            # One malformed block must not stop the bake. A certificate that
            # goes missing this way is caught by the verification phase.
        }
    }
    return ,$out
}

function Get-PemThumbprints {
    param([string]$Text)
    return ,@(Get-PemCertificates -Text $Text | ForEach-Object { $_.Thumbprint })
}

# If the ingredients cannot all be gathered, throw and leave any existing
# bundle untouched. A half-baked bundle is worse than a stale one.
function Build-CaBundle {
    param([string]$BundlePath, [string]$SeedPem, [string]$CorpRootCrt)

    $public = Get-PublicRootPem -SeedPem $SeedPem
    $corp   = Get-CorpRootPem  -CrtPath $CorpRootCrt
    $win    = Get-WindowsRootPem

    $publicCerts = Get-PemCertificates -Text $public.Text
    $corpCerts   = Get-PemCertificates -Text $corp
    $winCerts    = Get-PemCertificates -Text $win

    if ($publicCerts.Count -eq 0) { throw "EMPTY_PUBLIC_ROOTS: read zero certificates from the public roots ($($public.Source))." }
    # No check on the corp root. It is optional: certs\ ships none, and the
    # Windows store supplies it on a machine where IT deployed it. What matters
    # is the result, and phase 8 proves that by opening a real connection.

    # The Windows store enumerates in a different order run to run. Sorting by
    # thumbprint and dropping duplicates makes the output deterministic, which
    # is what lets the idempotence check below compare text.
    $seen = @{}
    $sb = [System.Text.StringBuilder]::new()
    foreach ($c in (@($publicCerts + $winCerts + $corpCerts) | Sort-Object Thumbprint)) {
        if ($seen.ContainsKey($c.Thumbprint)) { continue }
        $seen[$c.Thumbprint] = $true
        [void]$sb.Append((ConvertTo-PemBlock -Der $c.Der -Label $c.Subject))
    }
    $text = $sb.ToString()

    foreach ($c in $corpCerts) {
        if (-not $seen.ContainsKey($c.Thumbprint)) { throw 'CORP_ROOT_LOST: the corp root did not make it into the bundle.' }
    }

    $dir = Split-Path -Parent $BundlePath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $changed = $true
    if (Test-Path $BundlePath) {
        if ([IO.File]::ReadAllText($BundlePath) -eq $text) { $changed = $false }
    }
    if ($changed) {
        $tmp = "$BundlePath.tmp"
        [IO.File]::WriteAllText($tmp, $text, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $BundlePath -Force
    }

    return @{ Path = $BundlePath; Count = $seen.Count; Changed = $changed; PublicSource = $public.Source }
}

# Registry (User scope) and this session together. Already-running processes do
# not pick this up; they need a restart.
function Set-CertEnvironment {
    param(
        [string]$BundlePath,
        [ValidateSet('User', 'Process')] [string]$Scope = 'User'
    )
    $results = @()
    foreach ($name in $script:CertEnvNames) {
        $old = [Environment]::GetEnvironmentVariable($name, $Scope)
        if ($Scope -eq 'User') { [Environment]::SetEnvironmentVariable($name, $BundlePath, 'User') }
        Set-Item -Path "Env:$name" -Value $BundlePath
        $results += @{ Name = $name; Old = $old; New = $BundlePath; Changed = ($old -ne $BundlePath) }
    }
    return ,$results
}

# curl is the one tool the environment variables above cannot reach. It reads
# its roots from the Windows certificate store, so it finds the corporate root
# without help - and refuses the connection anyway. That root publishes no CRL
# or OCSP address, so schannel cannot ask whether it was revoked, and curl
# treats an unanswerable question as a no. Only inspected hosts fail, which is
# precisely the ones that matter here: api.anthropic.com and google.com go
# down while pypi.org and github.com sail through. Handing curl our bundle
# with --cacert changes nothing; the certificate was never the complaint.
#
# --ssl-revoke-best-effort lets an unanswerable revocation question pass while
# still honouring an answer wherever one exists. It lives in a config file
# because curl has no environment variable for it. Both curls on a machine
# this script sets up - the mingw one inside Git Bash and Windows own
# curl.exe - read %USERPROFILE%\.curlrc, checked by removing that file and
# watching api.anthropic.com fail again.
#
# The file may already be somebody elses, so the option is appended and an
# existing one is left alone: a second run adds nothing.
function Set-CurlRevocationConfig {
    param([string]$ConfigPath = (Join-Path $env:USERPROFILE '.curlrc'))

    $option = '--ssl-revoke-best-effort'
    $lines  = @()
    if (Test-Path -LiteralPath $ConfigPath) {
        $lines = @([IO.File]::ReadAllLines($ConfigPath))
        foreach ($line in $lines) {
            if ($line.Trim() -eq $option) {
                return @{ Path = $ConfigPath; Changed = $false }
            }
        }
    }
    $lines += '# added by kw_install: the corporate root publishes no revocation'
    $lines += '# endpoint, so curl cannot check one and rejects inspected hosts.'
    $lines += $option
    [IO.File]::WriteAllLines($ConfigPath, [string[]]$lines, [Text.UTF8Encoding]::new($false))
    return @{ Path = $ConfigPath; Changed = $true }
}

function Invoke-CheckScript {
    param([string]$Exe, [string]$Code, [string]$Extension, [string]$BundlePath, [string]$Url, [string]$Tool)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("certcheck-$([guid]::NewGuid().ToString('N')).$Extension")
    [IO.File]::WriteAllText($tmp, $Code, [System.Text.UTF8Encoding]::new($false))
    try {
        $out = & $Exe $tmp $BundlePath $Url 2>&1
        return @{ Ok = ($LASTEXITCODE -eq 0); Tool = $Tool; Detail = (($out | Out-String).Trim()) }
    } catch {
        return @{ Ok = $false; Tool = $Tool; Detail = $_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
}

# Given a bundle, trust it and nothing else. That replaces the default trust
# list, so a wrong bundle is guaranteed to fail rather than quietly pass on
# system trust.
#
# Given no bundle, connect on the machine's own default trust instead of
# refusing to run. A machine that needs no corporate certificates still has to
# answer "can python reach HTTPS from here", and that is the question the person
# actually cares about. The returned Forced flag says which of the two was
# tested, so a pass on default trust is never reported as a verified bundle.
function Test-BundleAgainstUrl {
    param([string]$BundlePath, [string]$Url)

    $forced = [bool]($BundlePath -and (Test-Path -LiteralPath $BundlePath))
    if (-not $forced) { $BundlePath = '' }

    $py = @'
import ssl, sys, urllib.request
bundle, url = sys.argv[1], sys.argv[2]
ctx = ssl.create_default_context(cafile=bundle) if bundle else ssl.create_default_context()
with urllib.request.urlopen(url, timeout=20, context=ctx) as r:
    print(r.status)
'@

    $js = @'
const https = require('https'), fs = require('fs');
const bundle = process.argv[2], url = process.argv[3];
const opts = bundle ? { ca: fs.readFileSync(bundle) } : {};
https.get(url, opts, r => { console.log(r.statusCode); process.exit(0); })
     .on('error', e => { console.error(e.message); process.exit(1); });
'@

    # Do not stop at the first candidate that fails. On Windows, python.exe is
    # often the Microsoft Store alias stub: Get-Command finds it, and running
    # it prints an advert instead of executing. One success is a pass; if all
    # fail, report the last failure rather than claiming nothing was tried.
    $candidates = @(
        @{ Exe = 'python'; Code = $py; Ext = 'py'; Tool = 'python (python)' }
        @{ Exe = 'py';     Code = $py; Ext = 'py'; Tool = 'python (py)' }
        @{ Exe = 'node';   Code = $js; Ext = 'js'; Tool = 'node' }
    )
    $last = $null
    foreach ($c in $candidates) {
        if (-not (Get-Command $c.Exe -ErrorAction SilentlyContinue)) { continue }
        $r = Invoke-CheckScript -Exe $c.Exe -Code $c.Code -Extension $c.Ext -BundlePath $BundlePath -Url $Url -Tool $c.Tool
        $r['Forced'] = $forced
        if ($r.Ok) { return $r }
        $last = $r
    }
    return $last ?? @{ Ok = $false; Tool = 'none'; Forced = $forced; Detail = 'neither python nor node is available, so nothing was verified.' }
}

# The check above is answered by python where python exists, and python on
# Windows reads the Windows certificate store. On a machine whose store holds
# the corporate root that line is green whatever node can do - and Claude Code
# runs on node, which trusts neither that store nor certifi, only its own
# roots plus NODE_EXTRA_CA_CERTS. So node is asked separately.
function Test-NodeTrust {
    param([string]$BundlePath, [string]$Url)

    if (-not (Get-Command 'node' -ErrorAction SilentlyContinue)) {
        return @{ Available = $false; Ok = $false; Tool = 'node'; Forced = $false; Detail = 'node is not on this machine' }
    }
    $forced = [bool]($BundlePath -and (Test-Path -LiteralPath $BundlePath))
    if (-not $forced) { $BundlePath = '' }

    # Given a bundle, trust it and nothing else, so a bundle missing the roots
    # this host needs fails here rather than passing on node own list.
    $js = @'
const https = require('https'), fs = require('fs');
const bundle = process.argv[2], url = process.argv[3];
const opts = bundle ? { ca: fs.readFileSync(bundle) } : {};
const req = https.get(url, opts, r => { console.log(r.statusCode); process.exit(0); });
req.on('error', e => { console.error(e.message); process.exit(1); });
req.setTimeout(20000, () => { console.error('timed out'); process.exit(1); });
'@

    $r = Invoke-CheckScript -Exe 'node' -Code $js -Extension 'js' -BundlePath $BundlePath -Url $Url -Tool 'node'
    $r['Available'] = $true
    $r['Forced']    = $forced
    return $r
}

# ---------------------------------------------------------------
# Claude Code wiring
# ---------------------------------------------------------------

# Skills are listed to the model as one description line each; the body is read
# only when the skill is invoked. A session that never touches docker therefore
# pays nothing for these being installed.
function Install-ClaudeSkills {
    param([string]$SourceDir, [string]$DestRoot = '', [switch]$WhatIfOnly)

    if (-not (Test-Path $SourceDir)) {
        return @{ Status = 'skipped'; Detail = "no skills directory at $SourceDir" }
    }
    $destRoot  = if ($DestRoot) { $DestRoot } else { Join-Path $env:USERPROFILE '.claude/skills' }
    $installed = @()
    $unchanged = @()
    $empty     = @()

    foreach ($dir in @(Get-ChildItem -LiteralPath $SourceDir -Directory -ErrorAction SilentlyContinue)) {
        $src = Join-Path $dir.FullName 'SKILL.md'
        if (-not (Test-Path $src)) { $empty += $dir.Name; continue }

        $destDir  = Join-Path $destRoot $dir.Name
        $destFile = Join-Path $destDir 'SKILL.md'

        $new = [IO.File]::ReadAllText($src)
        if ((Test-Path $destFile) -and ([IO.File]::ReadAllText($destFile) -eq $new)) {
            $unchanged += $dir.Name
            continue
        }
        # Decide before touching the disk. Creating the destination directory
        # ahead of this check would leave empty folders behind under -WhatIfOnly.
        if ($WhatIfOnly) { $installed += $dir.Name; continue }

        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        [IO.File]::WriteAllText($destFile, $new, [System.Text.UTF8Encoding]::new($false))
        $installed += $dir.Name
    }

    return @{ Status = 'ok'; Installed = $installed; Unchanged = $unchanged; Empty = $empty }
}

# Removes the personal copy of a skill that now ships as a plugin. Status is
# absent (nothing there), removed, kept (the folder holds more than SKILL.md,
# so it is somebody's work), or skipped (WhatIf). The SKILL.md is copied to
# BackupDir before the folder goes, as every other file this installer
# rewrites is backed up. Only the named folder is ever removed; DestRoot is
# never touched.
function Remove-RetiredClaudeSkill {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$DestRoot,
        [Parameter(Mandatory)][string]$BackupDir,
        [switch]$WhatIfOnly
    )
    # Name is one folder under DestRoot, never a path: a separator or '..' would point Remove-Item elsewhere.
    if ($Name -match '[\\/]' -or $Name -match '\.\.') { throw "Remove-RetiredClaudeSkill: Name must be a bare folder name, got '$Name'" }
    $dir = Join-Path $DestRoot $Name
    if (-not (Test-Path $dir)) { return @{ Status = 'absent'; Detail = "no old copy at $dir" } }

    $files   = @(Get-ChildItem -LiteralPath $dir -Recurse -Force -File)
    $subdirs = @(Get-ChildItem -LiteralPath $dir -Recurse -Force -Directory)
    $onlySkill = ($subdirs.Count -eq 0) -and ($files.Count -eq 1) -and ($files[0].Name -eq 'SKILL.md')
    if (-not $onlySkill) {
        return @{ Status = 'kept'; Detail = "$dir holds more than the SKILL.md this installer wrote; left in place" }
    }

    $backup = Join-Path $BackupDir "$Name.SKILL.md.bak"
    if ($WhatIfOnly) {
        return @{ Status = 'skipped'; Detail = "[WhatIf] would back up $($files[0].FullName) to $backup and remove $dir" }
    }
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
    Copy-Item -LiteralPath $files[0].FullName -Destination $backup -Force
    Remove-Item -LiteralPath $dir -Recurse -Force
    return @{ Status = 'removed'; Detail = "old copy removed: $dir (backup at $backup)"; Backup = $backup }
}

# Which PowerShell Claude Code runs cannot be set. There is no settings key for
# it - the binary carries no powershellPath and no CLAUDE_CODE_POWERSHELL_PATH.
# It probes these three places in order and, finding no pwsh 7, falls back to
# Windows PowerShell 5.1.
#
# So the way to "pin" version 7 is to make sure one of these holds it. This
# script already runs under 7 because of the #Requires line, but its own pwsh
# could sit somewhere Claude never looks, so the answer is checked rather than
# assumed.
function Test-ClaudePowerShell {
    $probes = @(
        (Join-Path ($env:ProgramFiles ?? 'C:\Program Files') 'PowerShell\7\pwsh.exe')
        (Join-Path ($env:LOCALAPPDATA  ?? '') 'Microsoft\WindowsApps\pwsh.exe')
        (Join-Path ($env:USERPROFILE   ?? '') '.dotnet\tools\pwsh.exe')
    )
    $found = @($probes | Where-Object { $_ -and (Test-Path $_) })
    if ($found.Count -gt 0) { return @{ Ok = $true;  Path = $found[0]; Probes = $probes } }
    return                        @{ Ok = $false; Path = '';        Probes = $probes }
}


# --- Windows Terminal ------------------------------------------------------
# Two things live here: the font every profile gets, and one shortcut that
# opens the PowerShell 7 profile. Claude Code does not need either, which is
# why nothing in this section is allowed to stop the run.

# Terminal keeps settings.json in one of three places depending on how it was
# installed. The Store package is the ordinary case on a corporate machine;
# the unpackaged path is what a zip install leaves behind.
function Get-TerminalSettingsPath {
    $local = $env:LOCALAPPDATA
    if (-not $local) { return '' }
    $packages = @(
        (Join-Path $local 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe')
        (Join-Path $local 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe')
    )
    foreach ($p in $packages) {
        $f = Join-Path $p 'LocalState\settings.json'
        if (Test-Path -LiteralPath $f) { return $f }
    }
    $unpackaged = Join-Path $local 'Microsoft\Windows Terminal\settings.json'
    if (Test-Path -LiteralPath $unpackaged) { return $unpackaged }
    # Installed but never opened: the package folder is there and the file is
    # not. Writing it now is still right - Terminal reads this file at launch
    # and generates its own profiles around whatever it finds.
    foreach ($p in $packages) {
        if (Test-Path -LiteralPath $p) { return (Join-Path $p 'LocalState\settings.json') }
    }
    return ''
}

# GulimChe is the name Windows registers for the Korean fixed-width face that
# reads as Gulimche on screen; asking for it by that ASCII name is what lets
# this file stay ASCII. Paired with aliased antialiasing, which is what keeps
# Korean strokes crisp instead of smeared at small sizes.
# The settings go under profiles.defaults rather than on one profile, so they
# also cover the profiles Terminal generates later for WSL or git bash. Only
# these three keys are touched and the rest of the file is carried across.
function Merge-TerminalDefaults {
    param([AllowEmptyString()][string]$Json)

    $settings = @{}
    if (-not [string]::IsNullOrWhiteSpace($Json)) {
        # Throws on malformed JSON on purpose: a file that cannot be read is
        # never written over. Terminal allows // comments in this file and
        # ConvertFrom-Json skips them, so a commented copy still parses.
        $settings = $Json | ConvertFrom-Json -AsHashtable
    }
    if ($settings -isnot [hashtable]) { $settings = @{} }

    # Terminal 0.x wrote profiles as a bare list. Turning that into an object
    # would throw the profiles away, so this refuses rather than guesses.
    if ($settings.ContainsKey('profiles') -and $settings['profiles'] -isnot [hashtable]) {
        throw 'TERMINAL_LEGACY_PROFILES: profiles is a list, not an object.'
    }
    if ($settings['profiles'] -isnot [hashtable]) { $settings['profiles'] = @{} }
    $profiles = $settings['profiles']
    if ($profiles.ContainsKey('defaults') -and $profiles['defaults'] -isnot [hashtable]) {
        throw 'TERMINAL_LEGACY_DEFAULTS: profiles.defaults is not an object.'
    }
    if ($profiles['defaults'] -isnot [hashtable]) { $profiles['defaults'] = @{} }
    $defaults = $profiles['defaults']

    # Read before the write, so a second run reports no change and leaves the
    # file alone even where somebody has reformatted it by hand.
    $font    = $defaults['font']
    $already = ($defaults['antialiasingMode'] -eq 'aliased') -and ($font -is [hashtable])
    if ($already) { $already = ($font['face'] -eq 'GulimChe') -and ($font['size'] -eq 10) }

    $defaults['antialiasingMode'] = 'aliased'
    if ($defaults['font'] -isnot [hashtable]) { $defaults['font'] = @{} }
    $defaults['font']['face'] = 'GulimChe'
    $defaults['font']['size'] = 10

    $out = ConvertTo-Canonical $settings | ConvertTo-Json -Depth 40
    # Refuse to hand back something that will not read again.
    try { $null = $out | ConvertFrom-Json }
    catch { throw 'TERMINAL_REWRITE_BROKEN: the merged settings do not round-trip as JSON.' }

    return @{ Json = $out; Changed = (-not $already) }
}


# The drawing sits in the middle of a much larger transparent canvas, and
# scaled straight down it would come out a speck with a wide empty border.
# This finds what is actually drawn so the caller can crop to it first.
function Get-OpaqueBounds {
    param([Parameter(Mandatory)]$Bitmap)
    $whole = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data  = $Bitmap.LockBits($whole, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                              [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $data.Stride
        $buf = [byte[]]::new($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    } finally { $Bitmap.UnlockBits($data) }

    # Nearly-transparent pixels are edge softening, not drawing, so the
    # threshold sits above zero rather than at it.
    $minX = $Bitmap.Width; $minY = $Bitmap.Height; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        $row = $y * $stride
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($buf[$row + ($x * 4) + 3] -gt 8) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    # A fully transparent image has no drawing to crop to, so the whole of it
    # is handed back rather than an empty rectangle nothing can be drawn into.
    if ($maxX -lt 0) { return $whole }
    return [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)
}

# Windows shortcuts will not take a PNG. They want an .ico, an .exe or a .dll,
# so the PNG is turned into a multi-size .ico here. The sizes are the ones the
# shell asks for: 16 in a list, 24 or 32 on the taskbar depending on the
# display scale, and the larger ones on the desktop and in the switcher.
function New-IconFromPng {
    param(
        [Parameter(Mandatory)][string]$PngPath,
        [Parameter(Mandatory)][string]$IcoDir,
        [string]$BaseName = 'claudecode',
        [int[]]$Sizes = @(16, 24, 32, 48, 64, 128, 256),
        [switch]$WhatIfOnly
    )

    Add-Type -AssemblyName System.Drawing
    # Named here rather than typed into the param list, because the colour type
    # only exists once the line above has run.
    $Background = [System.Drawing.Color]::Black
    $frames = @()
    $src = [System.Drawing.Bitmap]::new($PngPath)
    try {
        $box = Get-OpaqueBounds -Bitmap $src

        # A square canvas, because an icon is square and a wide drawing dropped
        # straight into one would be stretched. The margin keeps the drawing
        # off the edge without shrinking it the way a generous one would.
        # The canvas is filled black rather than left transparent, so the mark
        # sits on a solid tile instead of picking up whatever is behind it.
        $side = [int]([Math]::Max($box.Width, $box.Height) * 1.12)
        $square = [System.Drawing.Bitmap]::new($side, $side,
                      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $g = [System.Drawing.Graphics]::FromImage($square)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.Clear($Background)
                $g.DrawImage($src, [System.Drawing.Rectangle]::new(
                                 [int](($side - $box.Width) / 2),
                                 [int](($side - $box.Height) / 2),
                                 $box.Width, $box.Height),
                             $box, [System.Drawing.GraphicsUnit]::Pixel)
            } finally { $g.Dispose() }

            foreach ($s in $Sizes) {
                $frame = [System.Drawing.Bitmap]::new($s, $s,
                             [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                try {
                    $fg = [System.Drawing.Graphics]::FromImage($frame)
                    try {
                        $fg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $fg.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                        $fg.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                        # Black underneath as well, so the outermost pixels of a
                        # shrunk frame blend into the tile instead of fading out.
                        $fg.Clear($Background)
                        $fg.DrawImage($square, 0, 0, $s, $s)
                    } finally { $fg.Dispose() }
                    $ms = [IO.MemoryStream]::new()
                    $frame.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                    $frames += ,@($s, $ms.ToArray())
                    $ms.Dispose()
                } finally { $frame.Dispose() }
            }
        } finally { $square.Dispose() }
    } finally { $src.Dispose() }

    # A 6-byte header, then one 16-byte directory entry per size, then the
    # frames themselves. The frames are stored as PNG, which Windows has read
    # inside an .ico since Vista; 0 in the width and height byte means 256,
    # because one byte cannot hold that number.
    $out = [IO.MemoryStream]::new()
    $w = [IO.BinaryWriter]::new($out)
    try {
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$frames.Count)
        $offset = 6 + (16 * $frames.Count)
        foreach ($f in $frames) {
            $dim = if ($f[0] -ge 256) { 0 } else { $f[0] }
            $w.Write([byte]$dim); $w.Write([byte]$dim)
            $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32)
            $w.Write([uint32]$f[1].Length); $w.Write([uint32]$offset)
            $offset += $f[1].Length
        }
        foreach ($f in $frames) { $w.Write($f[1]) }
        $w.Flush()
        $bytes = $out.ToArray()
    } finally { $w.Dispose(); $out.Dispose() }

    # Windows keeps the picture it has already drawn for an icon path and goes
    # on drawing it after the file behind that path is replaced. Refreshing the
    # shell icon cache does not shift it, and neither does rewriting the
    # shortcut. So the name carries a stamp of the bytes: a redrawn icon lands
    # on a path nothing has cached yet, and an unchanged one lands on exactly
    # the path it landed on last time.
    $stamp = [Convert]::ToHexString(
                 [Security.Cryptography.SHA256]::HashData($bytes)[0..3]).ToLower()
    $IcoPath = Join-Path $IcoDir ('{0}-{1}.ico' -f $BaseName, $stamp)

    # Compared rather than stamped, so a second run reports no change. The
    # same PNG through the same code gives the same bytes every time.
    $existing = if (Test-Path -LiteralPath $IcoPath) { [IO.File]::ReadAllBytes($IcoPath) } else { @() }
    $same = ($existing.Length -eq $bytes.Length) -and
            (-not (Compare-Object $existing $bytes -SyncWindow 0))
    if (-not $same -and -not $WhatIfOnly) {
        $dir = Split-Path -Parent $IcoPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        [IO.File]::WriteAllBytes($IcoPath, $bytes)
    }
    return @{ Path = $IcoPath; Changed = (-not $same); Sizes = $Sizes; Bytes = $bytes.Length }
}

# wt.exe is an execution alias, a zero-byte stub the shell resolves. The alias
# path is preferred over the real one under WindowsApps because it carries no
# version number and so survives an update that the versioned path would not.
function Resolve-WindowsTerminal {
    $alias = Join-Path ($env:LOCALAPPDATA ?? '') 'Microsoft\WindowsApps\wt.exe'
    if ($alias -and (Test-Path -LiteralPath $alias)) { return $alias }
    $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return ''
}

# This cannot pin anything. Windows 11 took the pin-to-taskbar verb away from
# scripts - a shortcut there offers pin-to-Start and nothing else - and the
# taskbar's own pinned list is an undocumented binary that would take a
# person's existing pins with it the first time a rewrite was wrong. So the
# shortcut is put where it can be found and the last click is left to them.
function Install-TerminalShortcut {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Terminal,
        [string]$IconSource = '',
        [string]$ProfileName = 'PowerShell',
        [switch]$WhatIfOnly
    )

    $arguments = '-p "' + $ProfileName + '"'
    $icon      = if ($IconSource) { "$IconSource,0" } else { "$Terminal,0" }
    $shell     = New-Object -ComObject WScript.Shell

    # Read the existing one back rather than trusting a file of the right
    # name to be the right shortcut: a stale one left over from an earlier
    # run would otherwise never be corrected.
    $same = $false
    if (Test-Path -LiteralPath $Path) {
        $cur  = $shell.CreateShortcut($Path)
        $same = ($cur.TargetPath -eq $Terminal) -and ($cur.Arguments -eq $arguments) -and
                ($cur.IconLocation -eq $icon)
    }
    if ($same -or $WhatIfOnly) { return @{ Path = $Path; Changed = (-not $same) } }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $sc = $shell.CreateShortcut($Path)
    $sc.TargetPath       = $Terminal
    $sc.Arguments        = $arguments
    $sc.IconLocation     = $icon
    $sc.WorkingDirectory = $env:USERPROFILE
    $sc.Description      = 'Windows Terminal - PowerShell 7'
    $sc.Save()
    return @{ Path = $Path; Changed = $true }
}

# Containers do not inherit Windows user environment variables. Rather than
# nagging every session, this fires only when a docker command is actually
# issued; the 'if' filter keeps a process from being spawned otherwise.
function New-DockerHookEntries {
    param([string]$LocalScript)
    $baseArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $LocalScript)
    $mk = {
        param($ifRule)
        @{ type = 'command'; command = 'pwsh.exe'; args = $baseArgs; 'if' = $ifRule; timeout = 20 }
    }
    return @(
        @{ matcher = 'Bash';       hooks = @((& $mk 'Bash(docker *)')) }
        @{ matcher = 'PowerShell'; hooks = @((& $mk 'PowerShell(docker *)')) }
    )
}

function Test-IsOurHookEntry {
    param($Entry)
    foreach ($h in @($Entry.hooks)) {
        if ($h -isnot [hashtable]) { continue }
        if (-not $h.ContainsKey('args')) { continue }
        if ((@($h['args']) -join ' ') -match 'docker-cert-reminder\.ps1') { return $true }
    }
    return $false
}

# Hashtables do not preserve order, and .NET randomizes the string hash seed
# per process, so the same keys enumerate differently in a later run. Left
# alone that makes ConvertTo-Json emit a different byte sequence every time and
# the "did anything change" check below is true forever. Sorting the keys at
# every level makes the output depend only on content.
function ConvertTo-Canonical {
    param($InputObject)
    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($k in @($InputObject.Keys | Sort-Object)) {
            $ordered[$k] = ConvertTo-Canonical $InputObject[$k]
        }
        return $ordered
    }
    # Arrays keep their order: for hooks and permission rules the sequence is
    # part of the meaning.
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return ,@($InputObject | ForEach-Object { ConvertTo-Canonical $_ })
    }
    return $InputObject
}

# The single writer of settings.json. Everything Claude Code needs to know
# lands here in one pass so two writers cannot fight over the file.
function Merge-ClaudeSettings {
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [string]$HookScript = '',
        [switch]$RespectExecutionPolicy,
        [switch]$SkipPlugins,
        [switch]$WhatIfOnly
    )

    $dir = Split-Path -Parent $SettingsPath
    if ($dir -and -not (Test-Path $dir)) {
        if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    $settings = @{}
    $backup   = $null
    $original = ''
    if (Test-Path $SettingsPath) {
        $original = [IO.File]::ReadAllText($SettingsPath)
        if (-not [string]::IsNullOrWhiteSpace($original)) {
            # Throws on malformed JSON, and that is the point: never write over
            # a file that could not be read. The caller turns this into a
            # warning rather than losing somebody's hand-edited settings.
            $settings = $original | ConvertFrom-Json -AsHashtable
        }
    }
    if ($settings -isnot [hashtable]) { $settings = @{} }

    # --- env: turn on the PowerShell tool ---
    if ($settings['env'] -isnot [hashtable]) { $settings['env'] = @{} }
    $settings['env']['CLAUDE_CODE_USE_POWERSHELL_TOOL'] = '1'
    if ($RespectExecutionPolicy) {
        $settings['env']['CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY'] = '1'
    } else {
        $settings['env'].Remove('CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY')
    }

    # --- interactive ! commands go through PowerShell ---
    $settings['defaultShell'] = 'powershell'

    # Skills and custom slash commands may carry inline shell commands. This is
    # a flag rather than a permission rule, and when it is on the commands are
    # swapped for a placeholder instead of running. Stating it outright keeps a
    # changed default from quietly disabling them.
    $settings['disableSkillShellExecution'] = $false

    # --- permissions ---
    if ($settings['permissions'] -isnot [hashtable]) { $settings['permissions'] = @{} }
    # 'auto' only takes effect from user or managed settings. Claude Code
    # ignores it in a project's .claude/settings.json and falls back to the
    # built-in default, so a run pointed at a project file would go quiet
    # rather than fail. The installer writes the user copy, which is right.
    $settings['permissions']['defaultMode'] = 'auto'

    # And nothing else. allow, ask and deny are left exactly as found - whatever
    # is there belongs to the person or to their organisation's policy, not to
    # this installer. See the note above $script:PythonVersion for why the rules
    # this used to write were not worth carrying.

    # --- docker hook ---
    if ($HookScript) {
        if ($settings['hooks'] -isnot [hashtable]) { $settings['hooks'] = @{} }

        # Sweep out any entry pointing at this hook script first, across every
        # event, so an older layout's leftovers go too. Other people's hooks
        # are left alone and an event that empties out is removed entirely.
        foreach ($event in @($settings['hooks'].Keys)) {
            $kept = @(@($settings['hooks'][$event]) | Where-Object { -not (Test-IsOurHookEntry $_) })
            if ($kept.Count -gt 0) { $settings['hooks'][$event] = $kept }
            else { $settings['hooks'].Remove($event) }
        }

        $entries = New-DockerHookEntries -LocalScript $HookScript
        $settings['hooks']['PreToolUse'] = @(@($settings['hooks']['PreToolUse'] ?? @()) + $entries)
    }

    # --- plugins, declared ---
    # `claude plugin install` is what actually clones a marketplace. These keys
    # are the standing declaration, and the fallback for a machine where
    # claude.exe never ran.
    if (-not $SkipPlugins) {
        if ($settings['extraKnownMarketplaces'] -isnot [hashtable]) { $settings['extraKnownMarketplaces'] = @{} }
        if ($settings['enabledPlugins'] -isnot [hashtable]) { $settings['enabledPlugins'] = @{} }
        foreach ($pl in $script:Plugins) {
            $entry = @{ source = @{ source = 'github'; repo = $pl.Repo } }
            # autoUpdate is the user's once they have set it, on or off. It is
            # filled in only when absent, and only for rows that ask for it.
            $prior = $settings['extraKnownMarketplaces'][$pl.Marketplace]
            if ($prior -is [hashtable] -and $prior.ContainsKey('autoUpdate')) {
                $entry['autoUpdate'] = $prior['autoUpdate']
            } elseif ($pl.AutoUpdate) {
                $entry['autoUpdate'] = $true
            }
            $settings['extraKnownMarketplaces'][$pl.Marketplace] = $entry
            $settings['enabledPlugins'][$pl.Id] = $true
        }

        # Take back only what this installer itself declared in an earlier
        # version. Anything else in the list belongs to the user.
        foreach ($old in $script:RetiredPlugins) {
            if ($settings['enabledPlugins'].ContainsKey($old)) {
                $settings['enabledPlugins'].Remove($old)
            }
        }

        # A marketplace with nothing left pointing at it goes too, so the list
        # does not accumulate sources nothing uses.
        $live = @($script:Plugins | ForEach-Object { $_.Marketplace })
        foreach ($mkt in @($settings['extraKnownMarketplaces'].Keys)) {
            $stillUsed = @($settings['enabledPlugins'].Keys | Where-Object { ($_ -split '@')[1] -eq $mkt })
            if ($stillUsed.Count -eq 0 -and $live -notcontains $mkt) {
                $settings['extraKnownMarketplaces'].Remove($mkt)
            }
        }
    }

    $json = ConvertTo-Canonical $settings | ConvertTo-Json -Depth 40

    # Refuse to write something that will not read back.
    try { $null = $json | ConvertFrom-Json }
    catch { throw 'REWRITE_BROKEN: the merged settings do not round-trip as JSON. The original was left alone.' }

    $changed = ($json.Trim() -ne $original.Trim())

    if ($WhatIfOnly) {
        Write-Warn2 "[WhatIf] would write $SettingsPath"
    } elseif ($changed) {
        if ($original) {
            $backup = "$SettingsPath.bak"
            [IO.File]::WriteAllText($backup, $original, [System.Text.UTF8Encoding]::new($false))
        }
        [IO.File]::WriteAllText($SettingsPath, $json, [System.Text.UTF8Encoding]::new($false))
    }

    return @{ Settings = $settings; Json = $json; Backup = $backup; Changed = $changed }
}


# The CLI records every install it completed in installed_plugins.json, one
# key per plugin id. That file is the only evidence used: a marketplace can be
# added while the install fails, and a repo name can contain a marketplace
# name (KiwoomAX/KW-doc-formats holds kw-doc-formats, and -match ignores
# case), so the marketplace registry proves nothing about the plugin.
function Test-PluginInstalled {
    param([Parameter(Mandatory)][string]$RegistryPath, [Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path $RegistryPath)) { return $false }
    try { $reg = [IO.File]::ReadAllText($RegistryPath) | ConvertFrom-Json -AsHashtable -Depth 20 }
    catch { return $false }
    if ($reg -isnot [hashtable] -or $reg['plugins'] -isnot [hashtable]) { return $false }
    return [bool]$reg['plugins'].ContainsKey($Id)
}

# Third-party marketplaces have auto-update off by default; this switches it
# on for one named marketplace in the registry the /plugin toggle writes.
# Only that entry is touched, a value already present - true or false - is
# the user's and stays, a .bak is left, and the rewritten text is parsed
# again before it replaces the file. Not reached under -WhatIfOnly: the
# caller never installs then, so there is nothing to switch on.
function Set-MarketplaceAutoUpdate {
    param(
        [Parameter(Mandatory)][string]$RegistryPath,
        [Parameter(Mandatory)][string]$Marketplace
    )
    if (-not (Test-Path $RegistryPath)) { return @{ Status = 'failed'; Detail = "no registry at $RegistryPath" } }
    try { $reg = [IO.File]::ReadAllText($RegistryPath) | ConvertFrom-Json -AsHashtable -Depth 20 }
    catch { return @{ Status = 'failed'; Detail = "registry is not JSON: $($_.Exception.Message)" } }
    if ($reg -isnot [hashtable] -or -not $reg.ContainsKey($Marketplace) -or $reg[$Marketplace] -isnot [hashtable]) {
        return @{ Status = 'failed'; Detail = "$Marketplace is not in $RegistryPath" }
    }
    if ($reg[$Marketplace].ContainsKey('autoUpdate')) {
        return @{ Status = 'unchanged'; Detail = "autoUpdate already $($reg[$Marketplace]['autoUpdate']) for $Marketplace" }
    }
    $reg[$Marketplace]['autoUpdate'] = $true
    $json = $reg | ConvertTo-Json -Depth 20
    try { $null = $json | ConvertFrom-Json }
    catch { return @{ Status = 'failed'; Detail = 'rewritten registry did not parse; nothing written' } }
    try {
        Copy-Item -LiteralPath $RegistryPath -Destination "$RegistryPath.bak" -Force
        [IO.File]::WriteAllText($RegistryPath, $json, [Text.UTF8Encoding]::new($false))
    } catch { return @{ Status = 'failed'; Detail = "registry not written: $($_.Exception.Message)" } }
    return @{ Status = 'set'; Detail = "autoUpdate on for $Marketplace (backup at $RegistryPath.bak)" }
}

# The plugin cache and marketplace registry live outside settings.json, in
# ~\.claude\plugins. Only the CLI populates them, so declaring the keys is not
# the same as having the plugin on disk.
#
# Returns one result per plugin. A marketplace that fails must not stop the
# others: they are independent and a partial install beats none.
function Install-ClaudePlugins {
    param([string]$ClaudeExe, [switch]$WhatIfOnly)

    $blocked = ''
    if (-not (Test-Path $ClaudeExe)) {
        $blocked = "claude.exe not found at $ClaudeExe; the settings declaration will install these on first launch."
    } elseif (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $blocked = 'git is not available, and a marketplace is cloned with git.'
    }

    $pluginsDir = Join-Path $env:USERPROFILE '.claude/plugins'
    $installed  = Join-Path $pluginsDir 'installed_plugins.json'
    $registry   = Join-Path $pluginsDir 'known_marketplaces.json'
    $results = @()
    foreach ($pl in $script:Plugins) {
        if ($blocked) {
            $results += @{ Id = $pl.Id; Status = 'skipped'; Detail = $blocked }
            continue
        }
        if ($WhatIfOnly) {
            $results += @{ Id = $pl.Id; Status = 'skipped'; Detail = "[WhatIf] would add $($pl.Repo) and install $($pl.Id)" }
            continue
        }
        try {
            # Adding a marketplace that is already known is a success, not a
            # fault, so neither call's exit code is trusted. installed_plugins.json is.
            $out  = & $ClaudeExe plugin marketplace add $pl.Repo 2>&1 | Out-String
            $out += & $ClaudeExe plugin install $pl.Id 2>&1 | Out-String
        } catch {
            $results += @{ Id = $pl.Id; Status = 'failed'; Detail = $_.Exception.Message }
            continue
        }
        if (Test-PluginInstalled -RegistryPath $installed -Id $pl.Id) {
            $detail = "recorded in $installed"
            if ($pl.AutoUpdate) {
                $au = Set-MarketplaceAutoUpdate -RegistryPath $registry -Marketplace $pl.Marketplace
                $detail += "; $($au.Detail)"
                if ($au.Status -eq 'failed') { Add-Warning "auto-update not enabled for $($pl.Marketplace) - $($au.Detail)" }
            }
            $results += @{ Id = $pl.Id; Status = 'installed'; Detail = $detail }
        } else {
            $results += @{ Id = $pl.Id; Status = 'failed'; Detail = $out.Trim() }
        }
    }
    return ,$results
}


# Reads one of the Korean message files and returns its lines. Returns an empty
# array when the file is missing so a caller can fall back to English rather
# than printing nothing at all: an incomplete payload must not swallow the one
# instruction the person needs.
#
# The console is switched to UTF-8 first. setup.cmd already sets the code page,
# but a run started straight from a PowerShell window has not, and there the
# Korean would arrive as mojibake.
function Get-MessageLines {
    param([Parameter(Mandatory)][string]$Path)

    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
    if (-not (Test-Path $Path)) { return @() }
    return @([IO.File]::ReadAllLines($Path, [Text.UTF8Encoding]::new($false)) | Where-Object { $_.Trim() })
}

# Same idea, but the file is "key = value" lines. The keys are ASCII so this
# file can name them; the values are Korean. A key may repeat, and the values
# come back in the order they were written - that is how the multi-line notice
# is held without inventing a second file.
#
# An unknown key returns nothing rather than throwing: a missing line should
# cost one message, not the whole install.
function Get-MessageEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key
    )

    $out = @()
    foreach ($line in (Get-MessageLines -Path $Path)) {
        if ($line.TrimStart().StartsWith('#')) { continue }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        if ($line.Substring(0, $i).Trim() -ne $Key) { continue }
        $out += $line.Substring($i + 1).Trim()
    }
    # Callers must wrap this in @(). PowerShell unrolls a one-element result to
    # a bare string, and indexing that hands back its first letter rather than
    # the line - a prompt showing one syllable instead of the question.
    return $out
}

# Installs the personal memory into the user's CLAUDE.md.
#
# Merged, never replaced. The template is wrapped in "# BEGIN AX" and "# END AX"
# markers and only what sits between them is rewritten, so anything the person
# added themselves survives a rerun untouched. With no markers found the block
# is appended, and a machine with no CLAUDE.md gets a new one.
#
# The markers are matched on their ASCII prefix rather than the whole line. The
# rest of the line is Korean and cannot appear in this file, and matching a
# prefix also survives somebody rewording the parenthetical.
function Merge-PersonalMemory {
    param(
        [Parameter(Mandatory)][string]$MemoryPath,
        [Parameter(Mandatory)][string]$TemplatePath,
        [switch]$WhatIfOnly
    )

    if (-not (Test-Path $TemplatePath)) { throw "MEMORY_TEMPLATE_MISSING: $TemplatePath" }

    $utf8  = [Text.UTF8Encoding]::new($false)
    $block = ([IO.File]::ReadAllText($TemplatePath, $utf8)).Trim()

    # Without both markers a second run could not find its own region and would
    # append another copy every time. Better to stop than to grow the file.
    $reBegin = '(?m)^#\s*BEGIN AX\b'
    $reEnd   = '(?m)^#\s*END AX\b'
    if ($block -notmatch $reBegin -or $block -notmatch $reEnd) {
        throw 'MEMORY_TEMPLATE_UNMARKED: the template carries no BEGIN/END AX markers, so a rerun could not replace it.'
    }

    $dir = Split-Path -Parent $MemoryPath
    if ($dir -and -not (Test-Path $dir)) {
        if (-not $WhatIfOnly) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    $original = ''
    if (Test-Path $MemoryPath) { $original = [IO.File]::ReadAllText($MemoryPath, $utf8) }

    $reBlock = '(?ms)^#\s*BEGIN AX\b.*?^#\s*END AX[^\r\n]*'
    if ($original -match $reBlock) {
        # A scriptblock replacement, so a $ inside the template is never read as
        # a capture group reference.
        $merged = [regex]::Replace($original, $reBlock, { $block })
        $mode   = 'replaced'
    } elseif ($original.Trim()) {
        $merged = $original.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
        $mode   = 'appended'
    } else {
        $merged = $block + "`r`n"
        $mode   = 'created'
    }

    $changed = ($merged -ne $original)
    $backup  = $null

    if ($WhatIfOnly) {
        Write-Warn2 "[WhatIf] would $mode the memory block in $MemoryPath"
    } elseif ($changed) {
        if ($original) {
            $backup = "$MemoryPath.bak"
            [IO.File]::WriteAllText($backup, $original, $utf8)
        }
        [IO.File]::WriteAllText($MemoryPath, $merged, $utf8)
    }

    return @{ Path = $MemoryPath; Mode = $mode; Backup = $backup; Changed = $changed }
}


# Decides whether this machine sits behind an SSL inspection appliance, by
# opening a real TLS connection and judging the certificate it gets back.
#
# The judgement runs against the public root bundle, NOT the Windows store.
# That distinction is the whole point: pip and npm carry their own roots and
# never read the Windows store, so a machine whose store holds the corporate
# root passes a .NET check and still breaks on `pip install`. Measuring against
# the public roots measures what pip sees.
#
# Two mistakes cost an hour each while building this, so they are pinned here:
#
#   - X509Certificate2Collection.Import() reads only the FIRST certificate out
#     of a concatenated PEM. On this bundle that is 1 of 119, and every site
#     then reads as intercepted. ImportFromPemFile() reads them all.
#   - The chain needs the intermediates the handshake sends. Building from the
#     leaf alone cannot reach a public root, so genuine sites read as
#     intercepted too. They are collected in the callback and put in ExtraStore.
#
# A verdict of 'unknown' means the network could not be reached at all. The
# caller treats that as "install anyway": an unnecessary bundle costs nothing,
# a missing one breaks every later phase.
function Test-SslIntercepted {
    param(
        [string]$TargetHost = 'pypi.org',
        [int]$Port = 443,
        # AllowEmptyString because "there are no roots" is a real answer here,
        # not a caller mistake: the seed can be deleted and python may not be in yet.
        [Parameter(Mandatory)][AllowEmptyString()][string]$PublicRootPemText,
        [int]$TimeoutMs = 12000
    )

    if (-not $PublicRootPemText -or -not $PublicRootPemText.Trim()) {
        return @{ Verdict = 'unknown'; Detail = 'no public roots to judge against' }
    }

    $script:probeLeaf = $null
    $script:probeMids = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()

    $grab = [Net.Security.RemoteCertificateValidationCallback] {
        param($sender, $cert, $chain, $errors)
        try {
            $script:probeLeaf = [Security.Cryptography.X509Certificates.X509Certificate2]::new($cert)
            if ($chain) { foreach ($el in $chain.ChainElements) { [void]$script:probeMids.Add($el.Certificate) } }
        } catch { }
        return $true      # accept here; the verdict is formed below, on our terms
    }

    $tcp = [Net.Sockets.TcpClient]::new()
    try {
        if (-not $tcp.ConnectAsync($TargetHost, $Port).Wait($TimeoutMs)) {
            return @{ Verdict = 'unknown'; Detail = "timed out reaching $TargetHost" }
        }
        $ssl = [Net.Security.SslStream]::new($tcp.GetStream(), $false, $grab)
        $ssl.AuthenticateAsClient($TargetHost)
        $ssl.Dispose()
    } catch {
        return @{ Verdict = 'unknown'; Detail = 'handshake failed: ' + $_.Exception.Message.Split([char]10)[0] }
    } finally {
        $tcp.Dispose()
    }

    if (-not $script:probeLeaf) { return @{ Verdict = 'unknown'; Detail = 'no certificate captured' } }

    $roots = [Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
    $roots.ImportFromPem($PublicRootPemText)

    $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
    $chain.ChainPolicy.TrustMode = 'CustomRootTrust'
    $chain.ChainPolicy.RevocationMode = 'NoCheck'
    foreach ($r in $roots) { [void]$chain.ChainPolicy.CustomTrustStore.Add($r) }
    foreach ($m in $script:probeMids) { [void]$chain.ChainPolicy.ExtraStore.Add($m) }

    $ok  = $chain.Build($script:probeLeaf)
    $top = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Subject

    return @{
        Verdict = $(if ($ok) { 'clean' } else { 'intercepted' })
        Detail  = "root=$top"
        Roots   = $roots.Count
    }
}

# One clean host does not clear the network. Judging on pypi.org alone said
# 'not inspected' on a machine that was having api.anthropic.com rewritten,
# and the certificates the run exists to install were skipped there. Kept
# apart from the handshake so it can be exercised without a network.
function Resolve-SslVerdict {
    param([string[]]$Verdicts)
    if ($Verdicts -contains 'intercepted') { return 'intercepted' }
    if ($Verdicts -contains 'clean')       { return 'clean' }
    return 'unknown'
}

# Walks the probe list and stops at the first interception - the remaining
# handshakes cannot change the answer, so they are not paid for. Checked lists
# every host tried with what it gave, which is what makes a 'clean' verdict
# auditable instead of a bare claim.
function Test-SslInterceptedAcross {
    param(
        [string[]]$TargetHosts = $script:ProbeHosts,
        [Parameter(Mandatory)][AllowEmptyString()][string]$PublicRootPemText,
        [int]$TimeoutMs = 12000
    )
    $verdicts = @()
    $checked  = @()
    $roots    = 0
    foreach ($h in $TargetHosts) {
        $r = Test-SslIntercepted -TargetHost $h -PublicRootPemText $PublicRootPemText -TimeoutMs $TimeoutMs
        $verdicts += $r.Verdict
        $checked  += "$h=$($r.Verdict)"
        if ($r.Roots) { $roots = $r.Roots }
        if ($r.Verdict -eq 'intercepted') {
            return @{ Verdict = 'intercepted'; Detail = "$h $($r.Detail)"; Roots = $roots; Checked = ($checked -join ', ') }
        }
    }
    return @{ Verdict = (Resolve-SslVerdict -Verdicts $verdicts); Detail = ($checked -join ', '); Roots = $roots; Checked = ($checked -join ', ') }
}

# Turns the two facts - is there a public root list to judge against, and what
# did the handshake look like - into one of three answers: install, skip, or
# wait. Kept apart from the facts so it can be exercised without a network.
#
# Waiting exists because the list comes from certifi, and certifi arrives with
# python in phase 2. Judged before that on a machine with an empty certs\, the
# answer used to be "skip for lack of material" - which on the corporate
# network dropped the certificates the run existed to install, and off it told
# the person to export a root that was not there. -CanDefer says a later look
# is still coming; without it this is the last word.
function Resolve-SslDecision {
    param(
        [ValidateSet('Auto', 'Yes', 'No')]
        [string]$Ssl = 'Auto',
        [bool]$HasPublicRoots = $false,
        [string]$Verdict = 'unknown',
        [switch]$CanDefer
    )

    if ($Ssl -eq 'Yes') { return @{ Install = $true;  Deferred = $false; Reason = 'installed' } }
    if ($Ssl -eq 'No')  { return @{ Install = $false; Deferred = $false; Reason = 'forced off' } }

    if (-not $HasPublicRoots) {
        if ($CanDefer) { return @{ Install = $false; Deferred = $true;  Reason = 'deferred' } }
        return @{ Install = $false; Deferred = $false; Reason = 'no material' }
    }

    switch ($Verdict) {
        'clean'       { return @{ Install = $false; Deferred = $false; Reason = 'not needed' } }
        'intercepted' { return @{ Install = $true;  Deferred = $false; Reason = 'installed' } }
        # Cannot tell. Install rather than skip: a bundle nobody needs is
        # harmless, a missing one breaks every phase after this.
        default       { return @{ Install = $true;  Deferred = $false; Reason = 'installed' } }
    }
}

# Says out loud what the decision was and what it rested on. Both call sites
# report the same way, so the second look reads like the first one.
function Write-SslDecision {
    param($Decision, [string]$Ssl = 'Auto', [string]$Verdict = 'unknown', [string]$Detail = '')

    switch ($Decision.Reason) {
        'forced off' {
            Write-Warn2 'Corporate certificates: forced off (-Ssl No)'
            Add-Warning 'certificates skipped by -Ssl No'
            return
        }
        'deferred' {
            Write-Warn2 'Nothing to judge the network against yet - certifi arrives with python.'
            Write-Host  '     The certificates are decided in the programs phase instead.'
            return
        }
        'no material' {
            Write-Warn2 'No certificate material on hand, so certificates are skipped entirely.'
            Write-Host  '     If HTTPS later fails behind a corporate appliance, export the root'
            Write-Host  '     certificate from the Windows store into certs\ and run this again.'
            Add-Warning 'no certificate material - if HTTPS later fails, fill certs\ and run this again'
            return
        }
    }

    if ($Ssl -eq 'Yes') { Write-Ok 'Corporate certificates: forced on (-Ssl Yes)'; return }

    switch ($Verdict) {
        'clean'       { Write-Ok "HTTPS reaches the internet untouched, so no corporate certificates are needed ($Detail)" }
        'intercepted' { Write-Ok "HTTPS is being inspected on this network, so the certificates are needed ($Detail)" }
        default {
            Write-Warn2 "Could not test the network ($Detail); installing the certificates anyway"
            Add-Warning 'network test failed - corporate certificates installed without checking'
        }
    }
}

# Baking the bundle and pointing the environment variables at it. Two callers:
# phase 1, and the second look after python arrives when phase 1 had nothing to
# judge with. Returns $false when the ingredients could not be gathered - what
# that costs is the caller's call.
function Invoke-CertBundlePhase {
    param([string]$BundlePath, [string]$SeedPem, [string]$CorpRootCrt, [switch]$WhatIfOnly)

    if ($WhatIfOnly) {
        Write-Warn2 "[WhatIf] would bake $BundlePath, set $($script:CertEnvNames.Count) environment variables, and add the curl revocation line"
        return $true
    }

    try {
        $built = Build-CaBundle -BundlePath $BundlePath -SeedPem $SeedPem -CorpRootCrt $CorpRootCrt
    } catch {
        Write-Err2 "Could not gather the ingredients: $($_.Exception.Message)"
        Write-Host '     The existing bundle was left untouched.'
        return $false
    }

    Write-Ok "Bundle: $($built.Path)"
    Write-Ok "Certificates: $($built.Count)"
    Write-Ok "Public roots: $($built.PublicSource)"
    if ($built.Changed) { Write-Ok 'Baked fresh.' } else { Write-Ok 'Identical content; left as is.' }

    foreach ($e in (Set-CertEnvironment -BundlePath $BundlePath -Scope 'User')) {
        if ($e.Changed) { Write-Ok ('{0,-22} set' -f $e.Name) }
        else            { Write-Ok ('{0,-22} already correct' -f $e.Name) }
    }

    $curl = Set-CurlRevocationConfig
    if ($curl.Changed) { Write-Ok ('{0,-22} {1}' -f 'curl config', $curl.Path) }
    else               { Write-Ok ('{0,-22} already correct' -f 'curl config') }
    return $true
}

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------
function Invoke-Setup {

    Write-Host ""
    Write-Host "=== Workstation setup (PowerShell $($PSVersionTable.PSVersion)) ===" -ForegroundColor White
    Write-Host "    Source: $ScriptDir"
    if ($WhatIfOnly) {
        Write-Banner -Color Magenta -Lines @('WhatIf mode: nothing will be installed or written.')
    }

    # Nobody is asked. The machine is measured instead: open a real TLS
    # connection and see whether the certificate chains to a public root. That
    # is a fact, and it is one a non-developer could not answer anyway - the
    # honest answer changes with where they happen to be sitting.
    #
    # Wrong either way is cheap to recover from. The installer is idempotent,
    # so a machine that later moves behind the appliance is fixed by running it
    # again, and the closing notice says so.
    # The root list to judge against is the shipped seed, or certifi where python
    # is already on the machine. The seed exists because certifi arrives only in
    # phase 2: a new PC judged before that had nothing to measure with, skipped
    # the certificates altogether, and left node - which Claude Code runs on -
    # without a bundle. Waiting is kept for the case where the seed is gone too:
    # skipping there used to drop the certificates on the machines that needed them.
    $sslVerdict = 'unknown'
    $sslDetail  = ''
    $material   = Test-CertMaterial -SeedPem $SeedPem -CorpRootCrt $CorpRootCrt
    if ($Ssl -eq 'Auto' -and $material.PublicRoots) {
        $probe      = Test-SslInterceptedAcross -PublicRootPemText (Get-PublicRootPem -SeedPem $SeedPem).Text
        $sslVerdict = $probe.Verdict
        $sslDetail  = $probe.Detail
    }
    $sslDecision = Resolve-SslDecision -Ssl $Ssl -HasPublicRoots $material.PublicRoots `
                                       -Verdict $sslVerdict -CanDefer:(-not $SkipPrograms)
    $doSsl       = $sslDecision.Install
    $sslDeferred = $sslDecision.Deferred
    $sslReason   = $sslDecision.Reason
    Write-SslDecision -Decision $sslDecision -Ssl $Ssl -Verdict $sslVerdict -Detail $sslDetail

    # --- 0. Preflight ---
    Write-Step '0/9  Preflight'
    Write-Ok "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

    $isAdmin = Test-IsAdmin
    if ($isAdmin) {
        Write-Warn2 "Running elevated. Claude Code installs into $env:USERPROFILE."
        Write-Warn2 'If that is not the intended account, stop now and rerun as a normal user.'
        Add-Warning "Elevated session - install path pinned to $env:USERPROFILE"
    } else {
        Write-Ok 'Running as a normal user (recommended)'
    }

    # The public root seed ships; the corporate root does not, because it comes
    # from the Windows store on a machine where IT deployed it. So one of these
    # two files being absent is the ordinary case. This reports what is there
    # instead of grading it, which is why a machine off the corporate network no
    # longer sees a red line here.
    foreach ($p in @($SeedPem, $CorpRootCrt)) {
        if (Test-Path $p) { Write-Ok "Payload present: $(Split-Path $p -Leaf)" }
        else { Write-Ok "Payload not supplied, which is normal: $(Split-Path $p -Leaf)" }
    }

    $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        try {
            $wgVer = (& $wingetCmd.Path --version) 2>&1 | Select-Object -First 1
            Write-Ok "winget available: $wgVer"
        } catch {
            Write-Warn2 'winget found but not responding.'
            $wingetCmd = $null
        }
    } else {
        Write-Warn2 'winget.exe not found (App Installer missing or blocked by policy).'
    }

    # --- 1. CA bundle ---
    # First on purpose: every later phase that touches the network crosses the
    # inspection appliance.
    Write-Step '1/9  Corporate certificates'
    $bundlePath = Join-Path $BundleDir 'ca-bundle.pem'
    if (-not $doSsl) {
        switch ($sslReason) {
            'not needed'  { Write-Ok 'Nothing to do: this network is not inspecting HTTPS.' }
            'deferred'    { Write-Warn2 'Held over: python installs next, and the decision is taken there.' }
            'no material' { Write-Warn2 'Skipped: nothing to build a bundle from. See certs\README.txt.' }
            default       { Write-Warn2 'Skipped by -Ssl No. No bundle baked and no certificate variables set.' }
        }
    } elseif (-not (Invoke-CertBundlePhase -BundlePath $bundlePath -SeedPem $SeedPem `
                                           -CorpRootCrt $CorpRootCrt -WhatIfOnly:$WhatIfOnly)) {
        exit 2
    }

    # --- 2. Programs ---
    Write-Step '2/9  Programs'
    # Read PATH from the registry before deciding what is missing. This process
    # inherited its PATH from the parent shell, which may predate an install
    # done by an earlier run - and then every run reinstalls everything.
    Update-SessionPath
    $pythonArrived = $false
    if ($SkipPrograms) {
        Write-Warn2 '-SkipPrograms specified.'
        Add-Warning 'programs skipped'
    } else {
        foreach ($p in $script:Programs) {
            if (Test-ProgramPresent -Program $p) {
                Write-Ok "Already installed: $($p.Name)"
                continue
            }
            if (-not $wingetCmd) {
                Write-Warn2 "winget unavailable; install $($p.Name) by hand."
                Add-Warning "$($p.Name) not installed (no winget)"
                continue
            }
            if ($WhatIfOnly) {
                Write-Warn2 "[WhatIf] would install $($p.Id)"
                continue
            }

            # --source winget is not optional. Resolving from the msstore
            # source hands back a Store package whose alias stub is not a
            # working interpreter, and the install then reports success.
            #
            # No forced elevation here. Start-Process -Verb RunAs raises a UAC
            # window that stalls an unattended run, and these three install
            # per-user happily. winget asks for itself when it truly needs to.
            [void](Invoke-WingetInstall -Id $p.Id -WingetPath $wingetCmd.Path)
            Update-SessionPath

            if (Test-ProgramPresent -Program $p) {
                Write-Ok "Verified: $($p.Name)"
                if ($p.Pinned) { $pythonArrived = $true }
            } else {
                Write-Warn2 "$($p.Name) installed but does not run."
                Add-Warning "$($p.Name) install unverified"
            }
        }
    }

    # Phase 1 may have had nothing to judge the network with, because the root
    # list comes from certifi and certifi comes with python - which has only
    # just been installed. This is where that held-over decision gets taken.
    # Everything that needs the bundle runs after this point.
    if ($sslDeferred) {
        Write-Step 'Corporate certificates, held over from phase 1'
        $material = Test-CertMaterial -SeedPem $SeedPem -CorpRootCrt $CorpRootCrt
        $sslVerdict = 'unknown'
        $sslDetail  = 'python did not arrive, so nothing could be measured'
        if ($material.PublicRoots) {
            $probe      = Test-SslInterceptedAcross -PublicRootPemText (Get-PublicRootPem -SeedPem $SeedPem).Text
            $sslVerdict = $probe.Verdict
            $sslDetail  = $probe.Detail
        }
        # No -CanDefer: nothing else is coming that would change the answer.
        $sslDecision = Resolve-SslDecision -Ssl $Ssl -HasPublicRoots $material.PublicRoots -Verdict $sslVerdict
        $doSsl       = $sslDecision.Install
        $sslReason   = $sslDecision.Reason
        $sslDeferred = $false
        Write-SslDecision -Decision $sslDecision -Ssl $Ssl -Verdict $sslVerdict -Detail $sslDetail

        if ($doSsl -and -not (Invoke-CertBundlePhase -BundlePath $bundlePath -SeedPem $SeedPem `
                                                     -CorpRootCrt $CorpRootCrt -WhatIfOnly:$WhatIfOnly)) {
            exit 2
        }
    }

    # Phase 1 had to fall back to the shipped seed when no python existed. Now
    # that one does, rebake so the bundle rests on this machine's own certifi.
    # $doSsl guards this too. Without it a declined run would bake the bundle
    # here anyway, quietly undoing the answer given at the prompt.
    elseif ($doSsl -and $pythonArrived -and -not $WhatIfOnly) {
        Write-Ok 'Python arrived after the bundle was baked; rebaking against certifi.'
        try {
            $built = Build-CaBundle -BundlePath $bundlePath -SeedPem $SeedPem -CorpRootCrt $CorpRootCrt
            Write-Ok "Public roots: $($built.PublicSource)"
            if (-not $built.Changed) { Write-Ok 'Same content; left as is.' }
        } catch {
            Write-Warn2 "Rebake failed, keeping the existing bundle: $($_.Exception.Message)"
            Add-Warning 'bundle rebake after python install failed'
        }
    }

    # --- 3. Python libraries ---
    # These are not optional decoration. The document-formats skill, which
    # phase 8 installs as the kw-doc-formats plugin, calls `python -m
    # markitdown` and names pypdf, so without this the machine goes green
    # everywhere and still cannot open a .pptx.
    Write-Step '3/9  Python libraries'
    if ($SkipPythonLibs) {
        Write-Warn2 '-SkipPythonLibs specified. Reading .pptx, .docx and .pdf will not work.'
        Add-Warning 'python libraries skipped - the document skill cannot run'
    } else {
        # Before pip, not after. Run the other way round and the first install
        # spends a warning per library on a Scripts folder that cannot be
        # reached, and the check further down calls a machine that was just put
        # right broken.
        $pyDir = $null
        $pyExe = Resolve-PinnedPython -Version $script:PythonVersion
        if ($pyExe) { $pyDir = Split-Path -Parent $pyExe }
        if ($pyDir -and -not $WhatIfOnly) {
            # User scope only, as in the PATH phase: $env:PATH holds the two
            # scopes merged, and writing that back would copy the machine
            # entries into this user.
            $userPathNow = [Environment]::GetEnvironmentVariable('PATH', 'User') ?? ''
            $pyPath = Merge-PythonUserPath -UserPath $userPathNow -PythonDir $pyDir
            if ($pyPath.Changed) {
                [Environment]::SetEnvironmentVariable('PATH', $pyPath.Path, 'User')
                Update-SessionPath
                Write-Ok "Moved to the front of the user PATH: $pyDir"
            } else {
                Write-Ok "Already first on the user PATH: $pyDir"
            }
        } elseif ($pyDir) {
            Write-Warn2 "[WhatIf] would move $pyDir to the front of the user PATH"
        }
        try { $lib = Install-PythonLibraries -RequirementsPath $RequirementsPath -Version $script:PythonVersion -WhatIfOnly:$WhatIfOnly }
        catch { $lib = @{ Status = 'failed'; Names = @(); Detail = $_.Exception.Message } }

        switch ($lib.Status) {
            'installed' {
                Write-Ok "Into: $($lib.Python)"
                Write-Ok "Libraries: $(@($lib.Names) -join ', ')"
                if (@($lib.Conflicts).Count -gt 0) {
                    Write-Err2 'Library versions conflict with each other:'
                    foreach ($c in @($lib.Conflicts)) { Write-Host "       $c" -ForegroundColor Red }
                    Add-Warning 'pip check reported conflicts - add a constraint to requirements.txt'
                } else {
                    Write-Ok 'No version conflicts (pip check).'
                }
            }
            'skipped' {
                Write-Warn2 $lib.Detail
                # A dry run skips by design; only a real skip is worth warning about.
                if (-not $WhatIfOnly) { Add-Warning "python libraries not installed: $($lib.Detail)" }
            }
            default   { Write-Err2 $lib.Detail; Add-Warning 'python libraries failed - the document skill cannot run' }
        }

        # Libraries land in the pinned interpreter, but the skill calls a bare
        # `python`. If those are different versions the libraries are invisible.
        if (-not $WhatIfOnly) {
            $pp = Test-PathPython -Wanted $script:PythonVersion
            if ($pp.Ok) { Write-Ok $pp.Detail }
            else {
                Write-Err2 $pp.Detail
                if ($pyDir) {
                    Write-Host  '     The pinned one leads the user PATH, so this answer is coming from the system PATH, which an administrator has to edit.'
                } else {
                    Write-Host  '     No pinned python was found to put first. Rerun, or install Python by hand.'
                }
                Add-Warning "PATH python mismatch - $($pp.Detail)"
            }
        }
    }

    # --- 4. Claude Code ---
    Write-Step '4/9  Claude Code'
    if (Test-Path $claudeExe) { Write-Ok "Already installed: $claudeExe" }
    elseif ($SkipClaudeInstall) { Write-Warn2 '-SkipClaudeInstall specified.'; Add-Warning 'Claude Code skipped' }
    elseif ($WhatIfOnly) { Write-Warn2 '[WhatIf] would download and run https://claude.ai/install.ps1' }
    else {
        Write-Warn2 'Downloading and executing a remote script. Corporate EDR may flag this pattern.'
        Write-Host  '     Source: https://claude.ai/install.ps1'
        try {
            $installer = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1'
            Invoke-Expression $installer
            Update-SessionPath
            if (($env:PATH -split ';') -notcontains $claudeBin) { $env:PATH = "$env:PATH;$claudeBin" }
            if (Test-Path $claudeExe) { Write-Ok "Installed: $claudeExe" }
            else { Write-Warn2 "Installer finished but $claudeExe is missing."; Add-Warning 'Claude Code install unverified' }
        } catch {
            Write-Err2 "Claude Code install failed: $($_.Exception.Message)"
            Add-Warning 'Claude Code install failed - install by hand'
        }
    }

    # --- 5. PATH ---
    Write-Step '5/9  User PATH'
    if (($env:PATH -split ';') -notcontains $claudeBin) { $env:PATH = "$env:PATH;$claudeBin" }
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User') ?? ''
    if (($userPath -split ';') -contains $claudeBin) {
        Write-Ok "Already present: $claudeBin"
    } elseif ($WhatIfOnly) {
        Write-Warn2 "[WhatIf] would append $claudeBin to the user PATH"
    } else {
        # Read and write the User scope only. Using $env:PATH here would copy
        # the merged Machine+User value into User scope and pollute it.
        $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $claudeBin } else { "$userPath;$claudeBin" }
        [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
        Write-Ok "Appended: $claudeBin"
    }

    # --- 6. Windows Terminal ---
    # Cosmetic, and deliberately unable to stop the run: a font that did not
    # get set is no reason to fail an install that otherwise worked.
    Write-Step '6/9  Windows Terminal'
    $termFont  = 'not set'
    $termShort = 'no shortcut'
    if ($SkipTerminal) {
        Write-Warn2 '-SkipTerminal specified.'
        $termFont  = 'skipped'
        $termShort = 'skipped'
    } else {
        $wtSettings = Get-TerminalSettingsPath
        if (-not $wtSettings) {
            Write-Warn2 'Windows Terminal is not on this machine, so no font was set.'
            Add-Warning 'Windows Terminal not found - the font was not set'
        } else {
            try {
                $wtOriginal = if (Test-Path -LiteralPath $wtSettings) {
                    [IO.File]::ReadAllText($wtSettings)
                } else { '' }
                $wtMerged = Merge-TerminalDefaults -Json $wtOriginal
                $termFont = 'GulimChe 10, aliased'
                if (-not $wtMerged.Changed) {
                    Write-Ok 'Already set: GulimChe 10, antialiasing aliased'
                } elseif ($WhatIfOnly) {
                    Write-Warn2 "[WhatIf] would set the font in $wtSettings"
                } else {
                    $wtDir = Split-Path -Parent $wtSettings
                    if ($wtDir -and -not (Test-Path -LiteralPath $wtDir)) {
                        New-Item -ItemType Directory -Path $wtDir -Force | Out-Null
                    }
                    if ($wtOriginal) {
                        [IO.File]::WriteAllText("$wtSettings.bak", $wtOriginal,
                                                [System.Text.UTF8Encoding]::new($false))
                        Write-Ok "Previous Terminal settings kept at $wtSettings.bak"
                    }
                    [IO.File]::WriteAllText($wtSettings, $wtMerged.Json,
                                            [System.Text.UTF8Encoding]::new($false))
                    Write-Ok 'Set for every profile: GulimChe 10, antialiasing aliased'
                }
            } catch {
                # A settings.json that will not parse is somebody's own work.
                # Reporting it and moving on beats overwriting it.
                Write-Warn2 "Terminal settings left alone: $($_.Exception.Message)"
                Add-Warning 'Windows Terminal settings could not be read, so the font was not set'
            }
        }

        $wtExe = Resolve-WindowsTerminal
        if (-not $wtExe) {
            Write-Warn2 'wt.exe was not found, so no shortcut was made.'
            Add-Warning 'wt.exe not found - the PowerShell 7 shortcut was not made'
        } else {
            # The picture is the shipped PNG, built into an .ico next door.
            # pwsh.exe is the fallback: it carries exactly one icon, so index
            # 0 is the whole story there, and a shortcut ends up with a
            # picture on it even where the PNG or System.Drawing is missing.
            $iconFrom = (Test-ClaudePowerShell).Path
            # Empty unless the build below succeeds, so the tidy-up at the end
            # of the phase has something to read even when it did not.
            $icoPath  = ''
            if (Test-Path -LiteralPath $IconPng) {
                try {
                    $ico = New-IconFromPng -PngPath $IconPng -IcoDir $IconDir -WhatIfOnly:$WhatIfOnly
                    $icoPath = $ico.Path
                    $iconFrom = $icoPath
                    if ($WhatIfOnly) {
                        Write-Warn2 "[WhatIf] would build $icoPath from $(Split-Path $IconPng -Leaf)"
                    } elseif ($ico.Changed) {
                        Write-Ok "Icon built from $(Split-Path $IconPng -Leaf): $($ico.Sizes -join ', ') pixels"
                    } else {
                        Write-Ok "Icon already built: $icoPath"
                    }
                } catch {
                    # Not worth a red line. The shortcut still gets a picture,
                    # just the PowerShell one instead of the drawn one.
                    Write-Warn2 "Icon not built, using the PowerShell one: $($_.Exception.Message)"
                    Add-Warning 'the shortcut icon could not be built from the PNG'
                }
            } else {
                Write-Warn2 "Not in the payload, so the PowerShell icon is used: $(Split-Path $IconPng -Leaf)"
            }
            $written  = 0
            foreach ($dir in @([Environment]::GetFolderPath('Programs'),
                               [Environment]::GetFolderPath('Desktop'))) {
                if (-not $dir) { continue }
                $lnk = Join-Path $dir 'PowerShell 7.lnk'
                try {
                    $r = Install-TerminalShortcut -Path $lnk -Terminal $wtExe `
                                                  -IconSource $iconFrom -WhatIfOnly:$WhatIfOnly
                    if ($WhatIfOnly)    { Write-Warn2 "[WhatIf] would write $lnk" }
                    elseif ($r.Changed) { Write-Ok "Shortcut written: $lnk" }
                    else                { Write-Ok "Shortcut already there: $lnk" }
                    $written++
                } catch {
                    Write-Warn2 "Shortcut not written: $($_.Exception.Message)"
                    Add-Warning "could not write $lnk"
                }
            }
            # The icons every earlier run left behind. Cleared only once the
            # shortcuts point at the new one, so a failed write leaves a
            # machine with a stale picture rather than none at all.
            if ($written -gt 0 -and $icoPath -and -not $WhatIfOnly) {
                Get-ChildItem -LiteralPath $IconDir -Filter 'claudecode*.ico' -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -ne $icoPath } |
                    ForEach-Object {
                        try { Remove-Item -LiteralPath $_.FullName -Force } catch { }
                    }
            }
            if ($written -gt 0) {
                $termShort = "$written shortcut(s), start menu and desktop"
                # Windows 11 does not let a script pin to the taskbar. The
                # closing message asks for that one right-click, in Korean.
                Write-Ok 'Windows 11 blocks scripted taskbar pinning - one right-click finishes it'
            }
        }
    }
    # --- 7. Claude wiring ---
    Write-Step '7/9  Claude Code wiring'

    $ps7 = Test-ClaudePowerShell
    if ($ps7.Ok) {
        Write-Ok "Claude Code will run PowerShell 7: $($ps7.Path)"
    } else {
        Write-Err2 'Claude Code will fall back to Windows PowerShell 5.1.'
        Write-Host  '     It looks for pwsh.exe in these places and nowhere else:'
        foreach ($p in $ps7.Probes) { Write-Host "       $p" }
        Write-Host  '     Install PowerShell 7 into one of them, then rerun.'
        Add-Warning 'Claude Code would fall back to PowerShell 5.1 - pwsh 7 is not where it looks'
    }

    if ($SkipSkills) {
        Write-Warn2 '-SkipSkills specified.'
    } else {
        try { $sk = Install-ClaudeSkills -SourceDir $SkillsDir -WhatIfOnly:$WhatIfOnly }
        catch { $sk = @{ Status = 'failed'; Detail = $_.Exception.Message } }
        if ($sk.Status -eq 'ok') {
            if (@($sk.Installed).Count -gt 0) {
                $verb = if ($WhatIfOnly) { '[WhatIf] would install skills' } else { 'Skills installed' }
                Write-Ok "${verb}: $(@($sk.Installed) -join ', ')"
            }
            if (@($sk.Unchanged).Count -gt 0) { Write-Ok "Skills already current: $(@($sk.Unchanged) -join ', ')" }
            foreach ($e in @($sk.Empty)) {
                Write-Warn2 "Skill folder has no SKILL.md, skipped: $e"
                Add-Warning "skill '$e' shipped empty"
            }
        } else {
            Write-Warn2 "Skills skipped: $($sk.Detail)"
            Add-Warning 'skills not installed'
        }
    }

    $hookTarget = ''
    # The hook exists to say "mount the CA bundle into this container". With no
    # bundle on disk that advice points at a folder that was never created, so a
    # declined run must not register it. Answering N turns the whole corporate
    # certificate apparatus off, not just its first phase.
    if (-not $doSsl) {
        Write-Warn2 'Docker certificate hook not registered: there is no bundle for it to point at.'
    } elseif (-not $SkipHooks) {
        if (Test-Path $HookSource) {
            $hookTarget = Join-Path $BundleDir 'docker-cert-reminder.ps1'
            if ($WhatIfOnly) {
                Write-Warn2 "[WhatIf] would copy the docker hook to $hookTarget"
            } else {
                if (-not (Test-Path $BundleDir)) { New-Item -ItemType Directory -Force -Path $BundleDir | Out-Null }
                Copy-Item -LiteralPath $HookSource -Destination $hookTarget -Force
                Write-Ok "Hook script: $hookTarget"
            }
        } else {
            Write-Warn2 "No hook script at $HookSource"
            Add-Warning 'docker hook not shipped'
        }
    }

    try {
        $merged = Merge-ClaudeSettings -SettingsPath $SettingsPath -HookScript $hookTarget `
                                       -RespectExecutionPolicy:$RespectExecutionPolicy `
                                       -SkipPlugins:$SkipPlugins -WhatIfOnly:$WhatIfOnly
        if ($WhatIfOnly)         { Write-Warn2 'settings.json not written' }
        elseif ($merged.Changed) { Write-Ok "settings.json updated: $SettingsPath" }
        else                     { Write-Ok 'settings.json already correct' }
        if ($merged.Backup)      { Write-Ok "Previous settings kept at $($merged.Backup)" }
    } catch {
        Write-Err2 "settings.json untouched: $($_.Exception.Message)"
        Add-Warning 'settings.json could not be merged - fix it by hand and rerun'
    }


    # Without this the person on the other side is a stranger to Claude, and the
    # replies come back written for a developer. Merged into whatever is already
    # in CLAUDE.md rather than replacing it.
    try {
        $mem = Merge-PersonalMemory -MemoryPath $MemoryPath -TemplatePath $MemoryTemplate -WhatIfOnly:$WhatIfOnly
        if ($WhatIfOnly)      { Write-Warn2 'CLAUDE.md not written' }
        elseif ($mem.Changed) { Write-Ok "Personal memory $($mem.Mode): $MemoryPath" }
        else                  { Write-Ok 'Personal memory already current' }
        if ($mem.Backup)      { Write-Ok "Previous CLAUDE.md kept at $($mem.Backup)" }
    } catch {
        Write-Err2 "CLAUDE.md untouched: $($_.Exception.Message)"
        Add-Warning 'personal memory not installed - Claude will answer as if talking to a developer'
    }

    # --- 8. Plugins ---
    Write-Step '8/9  Claude Code plugins'
    $plugins = @()
    if ($SkipPlugins) {
        Write-Warn2 '-SkipPlugins specified.'
    } else {
        try { $plugins = Install-ClaudePlugins -ClaudeExe $claudeExe -WhatIfOnly:$WhatIfOnly }
        catch { $plugins = @(@{ Id = 'all'; Status = 'failed'; Detail = $_.Exception.Message }) }
        foreach ($r in @($plugins)) {
            switch ($r.Status) {
                'installed' { Write-Ok "$($r.Id): $($r.Detail)" }
                'skipped'   { Write-Warn2 "$($r.Id): $($r.Detail)" }
                default     {
                    Write-Warn2 "$($r.Id) did not confirm: $($r.Detail)"
                    Add-Warning "plugin unconfirmed - run 'claude plugin install $($r.Id)' by hand"
                }
            }
        }
    }

    # The document skill used to be copied into the personal skills folder and
    # now arrives as a plugin. The leftover copy goes only once the replacing
    # plugin is confirmed on disk: removed first and installed never, the
    # machine would have no document skill at all. A dry run reports what a
    # real run would do, so it too stays quiet when plugins are skipped.
    $skillsRoot = Join-Path $env:USERPROFILE '.claude/skills'
    $oldSkill   = $script:RetiredSkill
    $replaced   = @($plugins | Where-Object { $_.Id -eq $oldSkill.ReplacedBy -and $_.Status -eq 'installed' }).Count -gt 0
    if (($WhatIfOnly -and -not $SkipPlugins) -or $replaced) {
        try {
            $rm = Remove-RetiredClaudeSkill -Name $oldSkill.Name -DestRoot $skillsRoot -BackupDir $IconDir -WhatIfOnly:$WhatIfOnly
        } catch {
            $rm = @{ Status = 'failed'; Detail = $_.Exception.Message }
        }
        switch ($rm.Status) {
            'removed' { Write-Ok $rm.Detail }
            'skipped' { Write-Warn2 $rm.Detail }
            'absent'  { }
            'kept'    {
                Write-Warn2 $rm.Detail
                Add-Warning "old skill copy '$($oldSkill.Name)' kept - it holds files this installer did not write"
            }
            default   {
                Write-Err2 "Old skill copy not handled: $($rm.Detail)"
                Add-Warning "old skill copy '$($oldSkill.Name)' not handled - $($rm.Detail)"
            }
        }
    } elseif (Test-Path (Join-Path $skillsRoot $oldSkill.Name)) {
        Write-Warn2 "Old skill copy '$($oldSkill.Name)' left in place: $($oldSkill.ReplacedBy) is not confirmed installed."
        Add-Warning "old skill copy '$($oldSkill.Name)' kept - the replacing plugin is not confirmed"
    }

    # --- 9. Verify ---
    # This phase used to live inside the certificate branch, so every machine
    # that needed no certificates - which is every machine off the corporate
    # network - reached the summary without one connection attempt. The question
    # worth answering is "can python reach HTTPS from here now", and it has an
    # answer either way. With a bundle the bundle is what gets tested; without
    # one the machine's own trust is, which is exactly what pip will use there.
    Write-Step '9/9  Verify'
    $verifyBundle = if ($doSsl) { $bundlePath } else { '' }
    if ($WhatIfOnly) {
        $through = if ($doSsl) { 'through the bundle' } else { 'on this machine default trust' }
        Write-Warn2 "[WhatIf] would open $VerifyUrl $through"
        Write-Warn2 "[WhatIf] would open $ClaudeUrl with node $through"
    } else {
        $v = Test-BundleAgainstUrl -BundlePath $verifyBundle -Url $VerifyUrl
        if ($v.Tool -eq 'none') {
            # Nothing to test with. Saying so is honest; exiting 3 would blame
            # the network for a machine that simply has no python and no node.
            Write-Warn2 'Not verified: neither python nor node is on this machine.'
            Add-Warning 'nothing was verified - no python and no node to connect with'
        } elseif (-not $v.Ok) {
            Write-Err2 "Verification failed ($($v.Tool)): $($v.Detail)"
            if ($v.Forced) {
                Write-Host  '     The variables are set but the connection did not succeed. Check that this'
                Write-Host  '     machine is on the corporate network and that the corporate root certificate'
                Write-Host  '     has been deployed into the Windows certificate store.'
            } else {
                Write-Host  '     No corporate certificates were needed here, so this was a plain HTTPS'
                Write-Host  '     connection on the machine own trust. Check that this machine is online.'
                Write-Host  '     If it has since moved behind an inspecting appliance, run this again.'
            }
            exit 3
        } else {
            $how = if ($v.Forced) { 'through the bundle' } else { 'on this machine default trust' }
            Write-Ok "Verified ($($v.Tool)): connected to $VerifyUrl $how"
        }

        # The line above is usually python speaking, and python on Windows
        # reads the Windows certificate store. Claude Code does not: it runs
        # on node. Without this second question the run could report success
        # on a machine where no conversation can be opened.
        $nv = Test-NodeTrust -BundlePath $verifyBundle -Url $ClaudeUrl
        if (-not $nv.Available) {
            Write-Warn2 "Not verified with node: node is not on this machine, so $ClaudeUrl was not tried."
            Add-Warning 'node was not verified - Claude Code runs on node'
        } elseif (-not $nv.Ok) {
            Write-Err2 "Verification failed (node): $($nv.Detail)"
            Write-Host  '     Claude Code runs on node, and node trusts neither the Windows certificate'
            Write-Host  '     store nor certifi - only its own roots and NODE_EXTRA_CA_CERTS. Rerun this'
            Write-Host  '     script with -Ssl Yes to install the certificates whatever the probe said.'
            exit 3
        } else {
            $howNode = if ($nv.Forced) { 'through the bundle' } else { 'on node own roots' }
            Write-Ok "Verified (node): connected to $ClaudeUrl $howNode"
        }
    }

    Write-Host @"

--------------------------------------------------------------
Summary
--------------------------------------------------------------
  Ran on          : PowerShell $($PSVersionTable.PSVersion)
  Payload         : $ScriptDir
  CA bundle       : $(if ($doSsl) { $bundlePath } else { "none ($sslReason)" })
  Cert variables  : $(if ($doSsl) { $script:CertEnvNames -join ', ' } else { 'none set' })
  Python          : $script:PythonVersion, with $((Get-RequirementNames -Path $RequirementsPath).Count) libraries
  Terminal        : $termFont, $termShort
  settings.json   : $SettingsPath
  Permissions     : defaultMode auto, and nothing else changed. A classifier
                    checks tool calls instead of you, and it still blocks some
                    shell commands outright - that is the product's own list
  Plugins         : $(@($script:Plugins | ForEach-Object { ($_.Id -split '@')[0] }) -join ', ')

Next step
--------------------------------------------------------------
"@ -ForegroundColor White

    # The closing instruction is the last thing on screen and the only line
    # aimed at somebody who does not read the rest, so it goes out in Korean.
    $closing = Get-MessageLines -Path $ClosingKo
    if ($closing.Count -eq 0) {
        $closing = @(
            'Close every terminal, Claude Code and VSCode, then open them again.'
            'Environment variables reach only processes started after this point.'
        )
        Add-Warning 'closing message file missing - fell back to English'
    }
    foreach ($line in $closing) { Write-Host "  $line" -ForegroundColor White }
    Write-Host '--------------------------------------------------------------' -ForegroundColor White

    if ($script:Warnings.Count -gt 0) {
        # "install by hand" is not an instruction a non-developer can act on,
        # so the warning list ends with somewhere to send it instead.
        $support = @(Get-MessageLines -Path $SupportKo) + @("  $script:SupportContact")
        Write-Banner -Color Yellow -Lines (
            @("Warnings: $($script:Warnings.Count)", '') +
            ($script:Warnings | ForEach-Object { "- $_" }) +
            @('') + $support
        )
    }

    exit 0
}

if (-not $AsModule) { Invoke-Setup }
