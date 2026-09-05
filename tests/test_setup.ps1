#Requires -Version 7.0
# Contract tests for kw_install\setup.ps1.
# Dot-sources with -AsModule, so no phase runs: no winget, no installs, and the
# real user profile is never touched. ASCII-only, same as the script.
#
#   pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test_setup.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'setup.ps1') -AsModule

$script:Pass = 0
$script:Fail = 0

function Assert($label, $cond) {
    if ($cond) { $script:Pass++; Write-Host "PASS  $label" -ForegroundColor Green }
    else       { $script:Fail++; Write-Host "FAIL  $label" -ForegroundColor Red }
}

# Phases are located by name rather than by number. Written against the
# number, every one of these turned into a silent no-op the day a phase was
# inserted and the rest were renumbered - Substring(-1) is what that looked
# like from here, which is at least loud. The name does not move.
function Find-Phase {
    param([string]$Name)
    $m = [regex]::Match($script:setupText, "Write-Step '\d+/\d+\s+" + [regex]::Escape($Name) + "'")
    if ($m.Success) { return $m.Index }
    return -1
}

$Seed       = Join-Path $Root 'certs/combined_cacert.pem'   # the public root seed, shipped so a PC with no python can still judge
$Req        = Join-Path $Root 'requirements.txt'

# Several sections read the script body, so it is read once here and shared.
$setupText  = [IO.File]::ReadAllText((Join-Path $Root 'setup.ps1'))

$nlTest = [string][char]10
$Tmp = Join-Path ([IO.Path]::GetTempPath()) "kwinstall-test-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
$Bundle = Join-Path $Tmp 'ca-bundle.pem'

# A throwaway root, made here rather than taken from certs\. That folder ships
# empty now, so a test that read a certificate out of it would only pass on the
# machine that happened to have filled it. Generated in memory, so nothing is
# added to the Windows store.
$rsa  = [Security.Cryptography.RSA]::Create(2048)
$creq = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=KWINSTALL TEST ROOT', $rsa,
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1)
$TestRoot  = $creq.CreateSelfSigned([DateTimeOffset]::Now.AddDays(-1), [DateTimeOffset]::Now.AddYears(1))
$TestCrt   = Join-Path $Tmp 'test-root.crt'
[IO.File]::WriteAllBytes($TestCrt, $TestRoot.Export('Cert'))
$TestThumb = $TestRoot.Thumbprint

Write-Host '--- baking the bundle ---'
$r1 = Build-CaBundle -BundlePath $Bundle -SeedPem $Seed -CorpRootCrt $TestCrt
Assert 'the bundle file appears' (Test-Path $Bundle)
Assert 'the bundle holds many certificates' ($r1.Count -gt 1)
$thumbs = Get-PemThumbprints -Text ([IO.File]::ReadAllText($Bundle))
Assert 'a supplied root lands in the bundle' ($thumbs -contains $TestThumb)
Assert 'the first run reports a change' ($r1.Changed -eq $true)

Write-Host '--- idempotence ---'
$r2 = Build-CaBundle -BundlePath $Bundle -SeedPem $Seed -CorpRootCrt $TestCrt
Assert 'the second run yields the same count' ($r2.Count -eq $r1.Count)
Assert 'the second run reports no change' ($r2.Changed -eq $false)

Write-Host '--- certs\ ships empty, so the ingredients are optional ---'
# The corp root used to be required and the bake threw without it. It comes from
# the Windows store on a machine where IT deployed it, so a missing file is now
# ordinary. What must still hold is that a bundle gets built.
$noCorp = Join-Path $Tmp 'no-corp.pem'
$rn = Build-CaBundle -BundlePath $noCorp -SeedPem $Seed -CorpRootCrt (Join-Path $Tmp 'absent.crt')
Assert 'a bake with no corp root still produces a bundle' (Test-Path $noCorp)
Assert 'and that bundle carries the public roots' ($rn.Count -gt 1)
Assert 'a missing corp root file reads as empty, not as an error' ((Get-CorpRootPem -CrtPath (Join-Path $Tmp 'absent.crt')) -eq '')

# Public roots are the one thing it cannot invent. With no seed and no certifi
# there is nothing to build from, and that has to stay an error.
$mat = Test-CertMaterial -SeedPem $Seed -CorpRootCrt $TestCrt
Assert 'the material check reports what it found' ($mat.Detail -match 'seed=' -and $mat.Detail -match 'certifi=')
Assert 'a present file is seen' ($mat.CorpRoot -eq $true)
Assert 'a missing corp file is seen as missing' ((Test-CertMaterial -SeedPem $Seed -CorpRootCrt (Join-Path $Tmp 'absent.crt')).CorpRoot -eq $false)

Write-Host '--- the first run on a machine that has no python yet ---'
# The failure this pins was seen on a new PC: the certificate decision is taken
# before any python library is installed, and a fresh python carries no certifi.
# With certs\ holding no seed either there was nothing to judge the network
# against, so the run skipped certificates altogether, set no NODE_EXTRA_CA_CERTS
# and phase 8 died on node with 'self-signed certificate in certificate chain'.
# The seed is what lets that first look happen with no python on the machine.
$seedText = if (Test-Path $Seed) { [IO.File]::ReadAllText($Seed) } else { '' }
Assert 'the public root seed ships with the payload' (Test-Path $Seed)
Assert 'the seed is a real root list, not a stub' ((Get-PemCertificates -Text $seedText).Count -gt 100)

# HasPublicRoots is taken from the seed alone here, which is exactly what a
# machine with no certifi has. Reading it from Test-CertMaterial would pass on
# any developer machine and prove nothing about the one that broke.
$dFresh = Resolve-SslDecision -Ssl 'Auto' -HasPublicRoots ([bool](Test-Path $Seed)) -Verdict 'unknown'
Assert 'a first run without certifi does not skip for lack of material' ($dFresh.Reason -ne 'no material')
Assert 'and it installs rather than leaving node without a bundle' ($dFresh.Install -eq $true)

# The seed has to be usable as the thing the handshake is judged against, not
# merely present. An unreachable host is used so this needs no network.
$seedProbe = Test-SslIntercepted -TargetHost 'no-such-host.invalid' -PublicRootPemText $seedText -TimeoutMs 4000
Assert 'the seed alone is enough to judge a handshake against' ($seedProbe.Detail -ne 'no public roots to judge against')

Write-Host '--- a bundle that cannot be built ---'
# With certifi on the machine, a missing seed and a missing corp root no longer
# fail: certifi supplies the public roots. That is the point of emptying certs\,
# so the old "both missing throws" test would now be asserting the wrong thing.
$mNone = Test-CertMaterial -SeedPem (Join-Path $Tmp 'nope.pem') -CorpRootCrt (Join-Path $Tmp 'nope.crt')
if ($mNone.PublicRoots) {
    $stillWorks = Join-Path $Tmp 'from-certifi.pem'
    $rc = Build-CaBundle -BundlePath $stillWorks -SeedPem (Join-Path $Tmp 'nope.pem') -CorpRootCrt (Join-Path $Tmp 'nope.crt')
    Assert 'with certifi present, an empty certs folder still bakes' ((Test-Path $stillWorks) -and $rc.Count -gt 1)
    Assert 'and it says where the public roots came from' ($rc.PublicSource -match 'certifi')
} else {
    $threw = $false
    try { Build-CaBundle -BundlePath (Join-Path $Tmp 'x.pem') -SeedPem (Join-Path $Tmp 'nope.pem') -CorpRootCrt (Join-Path $Tmp 'nope.crt') | Out-Null }
    catch { $threw = $true }
    Assert 'with nothing at all to build from, the bake throws' $threw
}

# The old bundle must survive a bake that goes wrong, whatever the reason. The
# protection is writing to a temporary file and moving it into place, so that
# is what gets pinned - it holds even where a failure is hard to provoke.
Assert 'the bake writes to a temporary file and moves it into place' ($setupText -match '\$tmp = "\$BundlePath\.tmp"' -and $setupText -match 'Move-Item -LiteralPath \$tmp')

Write-Host '--- environment variables (Process scope, so the registry is untouched) ---'
foreach ($n in $script:CertEnvNames) { Remove-Item -Path "Env:$n" -ErrorAction SilentlyContinue }
$envResult = Set-CertEnvironment -BundlePath $Bundle -Scope 'Process'
Assert 'one result per configured variable' ($envResult.Count -eq $script:CertEnvNames.Count)
$missing = @($script:CertEnvNames | Where-Object {
    $cur = Get-Item "Env:$_" -ErrorAction SilentlyContinue
    (-not $cur) -or ($cur.Value -ne $Bundle)
})
Assert 'every variable points at the bundle' ($missing.Count -eq 0)
$envAgain = Set-CertEnvironment -BundlePath $Bundle -Scope 'Process'
Assert 'setting them again reports no change' (@($envAgain | Where-Object { $_.Changed }).Count -eq 0)

Write-Host '--- the curl revocation line (written to a temp file, not the profile) ---'
# curl is reached by a config file rather than a variable, so it gets its own
# checks: it must append without eating what is there, and it must not stack up
# copies of itself on a second run.
$CurlRc = Join-Path $Tmp '.curlrc'
$c1 = Set-CurlRevocationConfig -ConfigPath $CurlRc
Assert 'the first run writes the file' ($c1.Changed -eq $true -and (Test-Path $CurlRc))
Assert 'the option lands in the file' (@([IO.File]::ReadAllLines($CurlRc)) -contains '--ssl-revoke-best-effort')
$c2 = Set-CurlRevocationConfig -ConfigPath $CurlRc
Assert 'the second run reports no change' ($c2.Changed -eq $false)
Assert 'the option appears exactly once' (@([IO.File]::ReadAllLines($CurlRc) | Where-Object { $_.Trim() -eq '--ssl-revoke-best-effort' }).Count -eq 1)

# Somebody else's config is the case that must not be damaged, so it is a file
# with several lines: a single-line fixture would pass even if the function
# overwrote everything it found.
$CurlMine = Join-Path $Tmp 'mine.curlrc'
[IO.File]::WriteAllLines($CurlMine, [string[]]@('--connect-timeout 9', '# my own note', '--retry 3'))
Set-CurlRevocationConfig -ConfigPath $CurlMine | Out-Null
$mine = @([IO.File]::ReadAllLines($CurlMine))
Assert 'an existing setting survives' ($mine -contains '--connect-timeout 9')
Assert 'an existing comment survives' ($mine -contains '# my own note')
Assert 'the last existing line survives' ($mine -contains '--retry 3')
Assert 'ours is added on top of theirs' ($mine -contains '--ssl-revoke-best-effort')

Assert 'the cert phase actually calls it' ($setupText -match '\$curl = Set-CurlRevocationConfig')
Write-Host '--- a machine with no bundle still gets connected to ---'
# The verify phase used to sit entirely inside the certificate branch, so a run
# that decided against certificates - every machine off the corporate network -
# reached the summary without a single connection attempt. The README promised
# the opposite: "it does not call itself a success without connecting". What a
# person wants confirmed is "can python reach HTTPS now", and that question is
# answerable with or without a bundle.
$vNoBundle = Test-BundleAgainstUrl -Url 'https://pypi.org'
Assert 'verification runs without a bundle' ($vNoBundle.Ok -eq $true)
Assert 'and it says which tool did the connecting' ($vNoBundle.Tool -notin @('', $null, 'none'))

# Without a bundle the machine's own default trust is what gets exercised. That
# is exactly what pip and node will use on such a machine, so it is the right
# thing to test - but it must not be confused with having verified a bundle.
$vEmpty = Test-BundleAgainstUrl -BundlePath '' -Url 'https://pypi.org'
Assert 'an empty bundle path is treated as no bundle, not as an error' ($vEmpty.Ok -eq $true)
Assert 'the result records that no bundle was forced' ($vEmpty.Forced -eq $false)
$vForced = Test-BundleAgainstUrl -BundlePath $Bundle -Url 'https://pypi.org'
Assert 'and a real bundle is recorded as forced' ($vForced.Forced -eq $true)

# The phase must no longer hide behind the certificate decision.
$iVerify = Find-Phase 'Verify'
$verifyPhase = $setupText.Substring($iVerify)
Assert 'the verify phase is where it is expected' ($iVerify -gt 0)
Assert 'the verify phase no longer skips itself when there is no bundle' ($verifyPhase -notmatch '(?s)^.{0,400}if \(-not \$doSsl\)')

Write-Host '--- verification (with a planted regression, so it cannot spin idle) ---'
$v1 = Test-BundleAgainstUrl -BundlePath $Bundle -Url 'https://data.krx.co.kr'
Assert 'the right bundle passes verification' ($v1.Ok -eq $true)

# pypi.org is not intercepted by the corporate appliance, so it only validates
# when the public roots are present. data.krx.co.kr is intercepted and would
# pass on the corp root alone, which would hide this regression.
$broken = Join-Path $Tmp 'broken.pem'
[IO.File]::WriteAllText($broken, (Get-CorpRootPem -CrtPath $TestCrt), [System.Text.UTF8Encoding]::new($false))
$v2 = Test-BundleAgainstUrl -BundlePath $broken -Url 'https://pypi.org'
Assert 'a bundle without the public roots fails' ($v2.Ok -eq $false)
$v2b = Test-BundleAgainstUrl -BundlePath $Bundle -Url 'https://pypi.org'
Assert 'the whole bundle also reaches a site that is not intercepted' ($v2b.Ok -eq $true)

$empty = Join-Path $Tmp 'empty.pem'
[IO.File]::WriteAllText($empty, '', [System.Text.UTF8Encoding]::new($false))
$v3 = Test-BundleAgainstUrl -BundlePath $empty -Url 'https://data.krx.co.kr'
Assert 'an empty bundle fails' ($v3.Ok -eq $false)

Write-Host '--- settings.json on a clean machine ---'
$fresh = Join-Path $Tmp 'fresh.json'
$m1 = Merge-ClaudeSettings -SettingsPath $fresh
Assert 'the settings file appears' (Test-Path $fresh)
$a1 = Get-Content $fresh -Raw | ConvertFrom-Json
Assert 'defaultMode is auto' ($a1.permissions.defaultMode -eq 'auto')
Assert 'the PowerShell tool is enabled' ($a1.env.CLAUDE_CODE_USE_POWERSHELL_TOOL -eq '1')
Assert 'defaultShell is powershell' ($a1.defaultShell -eq 'powershell')
Assert 'inline shell in skills and slash commands stays on' ($a1.disableSkillShellExecution -eq $false)
Assert 'execution policy is not respected, so scripts are not blocked' ($null -eq $a1.env.PSObject.Properties['CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY'])
Assert 'the first merge reports a change' ($m1.Changed -eq $true)

Write-Host '--- the posture this installer was asked for ---'
# One line, and only that line. Earlier versions wrote a wide allow list and an
# SSL ask gate here; both are gone. This is pinned by absence because the value
# of the decision IS the absence - a rule creeping back in is the regression.
Assert 'defaultMode is the only permission key written' (@($a1.permissions.PSObject.Properties.Name) -join ',' -eq 'defaultMode')

# The plugin set is a decision, not a derivation, so it is spelled out here.
# Reading it from the script would make this vacuous: it would pass whatever
# the script happened to say.
$WantPlugins = @(
    'superpowers@claude-plugins-official'
    'document-skills@anthropic-agent-skills'
    'playwright@claude-plugins-official'
    'frontend-design@claude-plugins-official'
    'kw-doc-formats@kw-doc-formats'
)
$configured = @($script:Plugins | ForEach-Object { $_.Id })
Assert 'every plugin that was asked for is configured' (@($WantPlugins | Where-Object { $configured -notcontains $_ }).Count -eq 0)

# The same plugin from two marketplaces means two copies of its skills loaded
# and the same name listed twice. Pinned by plugin name, not by count, so
# adding a plugin later cannot quietly reintroduce a pair.
$names = @($configured | ForEach-Object { ($_ -split '@')[0] })
Assert 'no plugin is taken from two marketplaces' (@($names | Select-Object -Unique).Count -eq $names.Count)

# A machine that ran the earlier version still carries the old ids. Adding the
# new ones without removing those is what leaves the duplication in place.
$dupes = Join-Path $Tmp 'dupes.json'
@'
{
  "enabledPlugins": {
    "superpowers@superpowers-marketplace": true,
    "frontend-design@claude-code-plugins": true,
    "somebody-elses@their-marketplace": true
  },
  "extraKnownMarketplaces": {
    "superpowers-marketplace": { "source": { "source": "github", "repo": "obra/superpowers-marketplace" } },
    "their-marketplace": { "source": { "source": "github", "repo": "someone/theirs" } }
  }
}
'@ | Set-Content -LiteralPath $dupes
Merge-ClaudeSettings -SettingsPath $dupes | Out-Null
$ad2 = Get-Content $dupes -Raw | ConvertFrom-Json
$enabled = @($ad2.enabledPlugins.PSObject.Properties.Name)
Assert 'the retired plugin ids are taken back out' (@($script:RetiredPlugins | Where-Object { $enabled -contains $_ }).Count -eq 0)
Assert 'the replacements are in' (@($WantPlugins | Where-Object { $enabled -notcontains $_ }).Count -eq 0)
Assert 'a plugin the user chose is left alone' ($enabled -contains 'somebody-elses@their-marketplace')
$mkts = @($ad2.extraKnownMarketplaces.PSObject.Properties.Name)
Assert 'a marketplace nothing points at is dropped' ($mkts -notcontains 'superpowers-marketplace')
Assert 'a marketplace the user still uses survives' ($mkts -contains 'their-marketplace')

Write-Host '--- plugin declarations ---'
# Derived from the list: a plugin added without its marketplace fails here.
foreach ($pl in $script:Plugins) {
    $mkt = $a1.extraKnownMarketplaces.($pl.Marketplace)
    Assert "$($pl.Id) has its marketplace declared" (($mkt.source.repo -eq $pl.Repo) -and ($mkt.source.source -eq 'github'))
    Assert "$($pl.Id) is declared enabled" ($a1.enabledPlugins.($pl.Id) -eq $true)
}

# Third-party marketplaces have auto-update off by default, so the one that
# carries our own skill is declared with it on. Nothing else gets the key:
# the official marketplace already updates itself.
Assert 'the kw-doc-formats marketplace is declared with auto-update on' ($a1.extraKnownMarketplaces.'kw-doc-formats'.autoUpdate -eq $true)
Assert 'the official marketplace declaration carries no auto-update key' ($null -eq $a1.extraKnownMarketplaces.'claude-plugins-official'.PSObject.Properties['autoUpdate'])

# A value the user set on that entry - off, say - is theirs and survives a
# rerun. The declaration only fills the key in when it is absent.
$userOff = Join-Path $Tmp 'user-off.json'
@'
{ "extraKnownMarketplaces": { "kw-doc-formats": { "source": { "source": "github", "repo": "KiwoomAX/KW-doc-formats" }, "autoUpdate": false } } }
'@ | Set-Content -LiteralPath $userOff
Merge-ClaudeSettings -SettingsPath $userOff | Out-Null
$aOff = Get-Content $userOff -Raw | ConvertFrom-Json
Assert 'an auto-update value the user set is left alone' ($aOff.extraKnownMarketplaces.'kw-doc-formats'.autoUpdate -eq $false)

$skip = Join-Path $Tmp 'skip.json'
Merge-ClaudeSettings -SettingsPath $skip -SkipPlugins | Out-Null
$as = Get-Content $skip -Raw | ConvertFrom-Json
Assert '-SkipPlugins writes no plugin keys' ($null -eq $as.PSObject.Properties['enabledPlugins'])

Write-Host '--- repairing a machine that still prompts ---'
# ask beats allow in Claude Code. If our three patterns are not swept out of
# ask, adding them to allow changes nothing and the prompts keep coming.
$legacy = Join-Path $Tmp 'legacy.json'
@'
{
  "model": "opus",
  "theme": "dark",
  "permissions": {
    "ask": [ "PowerShell(*)", "Bash(powershell.exe *)", "Bash(pwsh *)", "Edit(//etc/*)" ],
    "allow": [ "Read" ],
    "deny": [ "PowerShell(*)", "Bash(rm *)" ]
  },
  "hooks": {
    "PostToolUse": [ { "matcher": "Write", "hooks": [ { "type": "command", "command": "someone-elses-tool.exe" } ] } ]
  }
}
'@ | Set-Content -LiteralPath $legacy

$hook = Join-Path $Tmp 'docker-cert-reminder.ps1'
Set-Content -LiteralPath $hook -Value '# stand-in for the hook script'
Merge-ClaudeSettings -SettingsPath $legacy -HookScript $hook | Out-Null
$al = Get-Content $legacy -Raw | ConvertFrom-Json

Assert 'unrelated top level settings survive' (($al.model -eq 'opus') -and ($al.theme -eq 'dark'))
Assert 'a backup of the original is kept' (Test-Path "$legacy.bak")
Assert 'somebody else hook survives' (@($al.hooks.PostToolUse).Count -eq 1)
Assert 'our two docker hooks are registered' (@($al.hooks.PreToolUse).Count -eq 2)

# The rules on this machine belong to the person or to their organisation. The
# installer sets the starting mode and reads nothing else in permissions - so a
# list it once rewrote wholesale now has to come through untouched.
Assert 'their ask list is left exactly as found' (@(Compare-Object @($al.permissions.ask) @('PowerShell(*)', 'Bash(powershell.exe *)', 'Bash(pwsh *)', 'Edit(//etc/*)')).Count -eq 0)
Assert 'their allow list is left exactly as found' (@(Compare-Object @($al.permissions.allow) @('Read')).Count -eq 0)
Assert 'their deny list survives, rather than being deleted' (@(Compare-Object @($al.permissions.deny) @('PowerShell(*)', 'Bash(rm *)')).Count -eq 0)
Assert 'and the starting mode is still set' ($al.permissions.defaultMode -eq 'auto')

Write-Host '--- settings idempotence ---'
$m2 = Merge-ClaudeSettings -SettingsPath $legacy -HookScript $hook
Assert 'the second merge reports no change' ($m2.Changed -eq $false)
$al2 = Get-Content $legacy -Raw | ConvertFrom-Json
Assert 'hooks do not accumulate' (@($al2.hooks.PreToolUse).Count -eq 2)

Write-Host '--- idempotence across processes ---'
# .NET randomizes the string hash seed per process, so a hashtable with the
# same keys enumerates in a different order in the next run. The in-process
# check above cannot see that; only a second process can. This is the exact
# defect that made every real run rewrite settings.json and stack up backups.
$cross = Join-Path $Tmp 'cross.json'
Merge-ClaudeSettings -SettingsPath $cross -HookScript $hook | Out-Null
$firstBytes = [IO.File]::ReadAllText($cross)

$child = Join-Path $Tmp 'child.ps1'
@"
. '$(Join-Path $Root 'setup.ps1')' -AsModule
`$m = Merge-ClaudeSettings -SettingsPath '$cross' -HookScript '$hook'
if (`$m.Changed) { 'CHANGED' } else { 'UNCHANGED' }
"@ | Set-Content -LiteralPath $child

$verdict = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $child 2>&1 | Out-String).Trim()
Assert 'a fresh process reports no change' ($verdict -match 'UNCHANGED')
Assert 'a fresh process leaves the bytes alone' ([IO.File]::ReadAllText($cross) -eq $firstBytes)

Write-Host '--- a settings file that cannot be read ---'
$brokenJson = Join-Path $Tmp 'broken.json'
'{ "model": "opus",,, }' | Set-Content -LiteralPath $brokenJson
$beforeJson = Get-Content $brokenJson -Raw
$threw = $false
try { Merge-ClaudeSettings -SettingsPath $brokenJson | Out-Null } catch { $threw = $true }
Assert 'malformed settings throw' $threw
Assert 'malformed settings are not overwritten' ((Get-Content $brokenJson -Raw) -eq $beforeJson)

Write-Host '--- deciding about certificates by measuring, not by asking ---'
# Nobody is asked any more. The verdict comes from a real TLS handshake judged
# against the public roots - which is what pip and npm see, unlike the Windows
# store they never read.
$probe = Test-SslIntercepted -PublicRootPemText (Get-PublicRootPem -SeedPem $Seed).Text
Assert 'the probe returns a verdict it knows' ($probe.Verdict -in @('clean', 'intercepted', 'unknown'))
Assert 'a verdict names the root it judged' (($probe.Verdict -eq 'unknown') -or ($probe.Detail -match 'root='))

# Two bugs cost an hour each while building this, and both made every site read
# as intercepted. They are pinned so they cannot come back.
if ($probe.Verdict -ne 'unknown') {
    # Import() reads only the first certificate of a concatenated PEM - 1 of 119
    # here. ImportFromPemFile() reads them all.
    Assert 'the whole public root bundle is loaded, not just its first entry' ($probe.Roots -gt 100)
    # Without the handshake intermediates the chain cannot reach a public root,
    # so genuine sites read as intercepted.
    Assert 'the script collects the handshake intermediates' ($setupText -match 'ExtraStore\.Add')
}

Assert 'a bad host yields unknown rather than a wrong verdict' ((Test-SslIntercepted -TargetHost 'no-such-host.invalid' -PublicRootPemText (Get-PublicRootPem -SeedPem $Seed).Text -TimeoutMs 4000).Verdict -eq 'unknown')

Write-Host '--- the preflight does not cry over an empty certs folder ---'
# certs\ ships empty on purpose, so every run off the corporate network printed
# two red FAIL lines for files that are meant to be absent. The preflight says
# what it found; a folder that is empty by design is not a failure.
$iPreflight = Find-Phase 'Preflight'
$iBundle    = Find-Phase 'Corporate certificates'
Assert 'the preflight phase is where it is expected' (($iPreflight -gt 0) -and ($iBundle -gt $iPreflight))
$preflight  = $setupText.Substring($iPreflight, $iBundle - $iPreflight)
Assert 'a missing certs payload is not reported as a failure' ($preflight -notmatch 'Write-Err2 "Payload missing')
Assert 'the preflight still reports what certs\ holds' ($preflight -match 'Payload')

Write-Host '--- the decision itself, apart from the network it reads ---'
# The decision used to be written inline, and it ran before python was
# installed. On a machine with an empty certs\ and no python there was nothing
# to judge the network against, so it skipped without ever measuring: on the
# corporate network that silently left out the certificates it was there to
# install, and off it the person was told to go and export a corporate root
# that does not exist. Waiting is the honest third answer, so it is its own
# outcome here rather than a flavour of skipping.
$dWait = Resolve-SslDecision -Ssl 'Auto' -HasPublicRoots $false -CanDefer
Assert 'with nothing to judge against yet, the decision waits' ($dWait.Deferred -eq $true)
Assert 'waiting installs nothing on the spot' ($dWait.Install -eq $false)
Assert 'and waiting is not reported as missing material' ($dWait.Reason -eq 'deferred')

$dLast = Resolve-SslDecision -Ssl 'Auto' -HasPublicRoots $false
Assert 'with nowhere left to wait, it skips for lack of material' ($dLast.Reason -eq 'no material')
Assert 'and that skip is not a deferral' ($dLast.Deferred -eq $false)

$dClean = Resolve-SslDecision -Ssl 'Auto' -HasPublicRoots $true -Verdict 'clean'
Assert 'a clean network needs no certificates' (($dClean.Install -eq $false) -and ($dClean.Reason -eq 'not needed'))
Assert 'an inspected network gets them' ((Resolve-SslDecision -Ssl 'Auto' -HasPublicRoots $true -Verdict 'intercepted').Install -eq $true)

# An unreachable network must not be read as "no certificates needed": that
# would leave every later phase to fail. Install is the safe side of unknown.
Assert 'an unknown verdict installs rather than skips' ((Resolve-SslDecision -Ssl 'Auto' -HasPublicRoots $true -Verdict 'unknown').Install -eq $true)

$dNo = Resolve-SslDecision -Ssl 'No' -HasPublicRoots $true -Verdict 'intercepted'
Assert '-Ssl No overrides an inspected network' (($dNo.Install -eq $false) -and ($dNo.Reason -eq 'forced off'))
$dYes = Resolve-SslDecision -Ssl 'Yes' -HasPublicRoots $false -CanDefer
Assert '-Ssl Yes overrides an empty certs folder rather than waiting' (($dYes.Install -eq $true) -and ($dYes.Deferred -eq $false))

# Waiting is worth nothing unless something later resolves it. Python is what
# supplies the roots to judge against, so the second look has to happen after
# the programs phase and before the first phase that needs the bundle.
$iPrograms = Find-Phase 'Programs'
$iResolve  = $setupText.LastIndexOf('Resolve-SslDecision')
$iPyLibs   = Find-Phase 'Python libraries'
Assert 'the phases it has to sit between are all present' (($iPrograms -gt 0) -and ($iPyLibs -gt $iPrograms))
Assert 'a deferred decision is taken again once python has arrived' (($iResolve -gt $iPrograms) -and ($iResolve -lt $iPyLibs))

# The judgement must not be made against the Windows store.
Assert 'the probe judges against a custom root store' ($setupText -match 'CustomRootTrust')

# A 'clean' verdict turns the whole certificate apparatus off, not just phase 1.
# Each of these ran independently of the verdict at some point, and each one
# would have quietly reinstated part of it.
# The skip message has to say WHY. A run that skipped because the network is
# clean must not print the same thing as one that skipped for lack of material:
# the first is fine, the second needs the person to do something.
Assert 'the skip message distinguishes its reasons' ($setupText -match "switch \(\`$sslReason\)")
foreach ($reason in @("'not needed'", "'no material'", "'forced off'", "'installed'", "'deferred'")) {
    Assert "the reason $reason is set somewhere" ($setupText -match [regex]::Escape($reason))
}
Assert 'a clean verdict skips the rebake after python arrives' ($setupText -match '\$doSsl -and \$pythonArrived')
Assert 'a clean verdict skips the docker certificate hook' ($setupText -match 'if \(-not \$doSsl\) \{[^}]*hook not registered')

# A real run printed "Cert variables: REQUESTS_CA_BUNDLE, ..." when nothing had
# been set. The summary is what the person reads, so its lines have to be true.
Assert 'the summary does not claim cert variables that were never set' ($setupText -match 'Cert variables\s*:\s*\$\(if \(\$doSsl\)')

# The hook advises mounting the CA bundle. With no bundle that advice is wrong.
$noCerts = Join-Path $Tmp 'nocerts.json'
Merge-ClaudeSettings -SettingsPath $noCerts | Out-Null
$anc = Get-Content $noCerts -Raw | ConvertFrom-Json
Assert 'a run without certificates registers no PreToolUse hook' ($null -eq $anc.PSObject.Properties['hooks'])
Assert 'and still sets the starting mode' ($anc.permissions.defaultMode -eq 'auto')

Write-Host '--- what a non-developer actually reads ---'
# The closing line and the support contact are the only text aimed at somebody
# who does not read the rest of the screen, so they ship in Korean. They live
# outside setup.ps1 on purpose: that file is ASCII only, and Korean inside a
# BOM-less .ps1 stops Windows PowerShell from parsing it at all.
$ClosingFile = Join-Path $Root 'templates/closing-ko.txt'
$SupportFile = Join-Path $Root 'templates/support-ko.txt'
Assert 'the closing message ships' (Test-Path $ClosingFile)
Assert 'the support message ships' (Test-Path $SupportFile)

foreach ($f in @($ClosingFile, $SupportFile)) {
    $name  = Split-Path $f -Leaf
    $bytes = [IO.File]::ReadAllBytes($f)
    Assert "$name is actually Korean, not an ASCII placeholder" (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0)
    Assert "$name carries no BOM, so it reads back as written" (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
}

$closingLines = Get-MessageLines -Path $ClosingFile
Assert 'the closing message has content' ($closingLines.Count -gt 0)
# The exact Korean wording is deliberately not pinned. This text lives in its
# own file so somebody can reword it without touching code, and a test that
# spelled the sentence out would take that back. What is pinned is the one
# actionable thing the reader has to come away with.
Assert 'the closing message tells them to run claude' (($closingLines -join ' ') -match 'claude')
Assert 'the closing message is more than one line' ($closingLines.Count -ge 2)

# A missing file must not silently print nothing: the caller falls back to
# English, and the one instruction the person needs still reaches the screen.
Assert 'a missing message file yields nothing rather than throwing' ((Get-MessageLines -Path (Join-Path $Tmp 'no-such-file.txt')).Count -eq 0)
Assert 'the script falls back to English when the closing file is gone' ($setupText -match 'closing message file missing')

# "install by hand" is not something this audience can act on.
Assert 'a contact address is configured' ($script:SupportContact -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
Assert 'the warning banner carries the contact' ($setupText -match '\$script:SupportContact')

Write-Host '--- personal memory: merged, never replaced ---'
$MemTemplate = Join-Path $Root 'templates/personal-memory-ko.md'
Assert 'the memory template ships' (Test-Path $MemTemplate)
$memText = [IO.File]::ReadAllText($MemTemplate, [Text.UTF8Encoding]::new($false))
Assert 'the template carries both markers' (($memText -match '(?m)^#\s*BEGIN AX\b') -and ($memText -match '(?m)^#\s*END AX\b'))
Assert 'the template is actually Korean' (@([IO.File]::ReadAllBytes($MemTemplate) | Where-Object { $_ -gt 127 }).Count -gt 0)

$memNew = Join-Path $Tmp 'mem-new.md'
$r = Merge-PersonalMemory -MemoryPath $memNew -TemplatePath $MemTemplate
Assert 'a machine with no CLAUDE.md gets one' (Test-Path $memNew)
Assert 'creating reports the mode' ($r.Mode -eq 'created')

# Fixtures stay ASCII: this file has the same encoding contract as setup.ps1.
$memOwn = Join-Path $Tmp 'mem-own.md'
[IO.File]::WriteAllText($memOwn, "# MY NOTES`r`n`r`n- do-not-delete-this-line`r`n", [Text.UTF8Encoding]::new($false))
$r = Merge-PersonalMemory -MemoryPath $memOwn -TemplatePath $MemTemplate
$after = [IO.File]::ReadAllText($memOwn, [Text.UTF8Encoding]::new($false))
Assert 'an existing memory file is appended to, not replaced' ($r.Mode -eq 'appended')
Assert 'what the person wrote themselves survives' ($after -match 'do-not-delete-this-line')
Assert 'a backup of their file is kept' (Test-Path "$memOwn.bak")

$r2 = Merge-PersonalMemory -MemoryPath $memOwn -TemplatePath $MemTemplate
$after2 = [IO.File]::ReadAllText($memOwn, [Text.UTF8Encoding]::new($false))
Assert 'a second run reports no change' ($r2.Changed -eq $false)
Assert 'the managed block appears exactly once' (@([regex]::Matches($after2, '(?m)^#\s*BEGIN AX\b')).Count -eq 1)

# An edit inside the managed region is overwritten; one outside it is not.
$edited = [regex]::Replace($after2, '(?m)^(#\s*BEGIN AX\b[^\r\n]*)', { param($m) $m.Groups[1].Value + "`r`nMANUAL-EDIT-INSIDE" })
$edited = $edited.TrimEnd() + "`r`n`r`nMANUAL-EDIT-OUTSIDE`r`n"
[IO.File]::WriteAllText($memOwn, $edited, [Text.UTF8Encoding]::new($false))
Merge-PersonalMemory -MemoryPath $memOwn -TemplatePath $MemTemplate | Out-Null
$after3 = [IO.File]::ReadAllText($memOwn, [Text.UTF8Encoding]::new($false))
Assert 'an edit inside the managed block is overwritten' ($after3 -notmatch 'MANUAL-EDIT-INSIDE')
Assert 'an edit outside the managed block is left alone' ($after3 -match 'MANUAL-EDIT-OUTSIDE')

# A template with no markers would be appended again on every run.
$unmarked = Join-Path $Tmp 'unmarked.md'
[IO.File]::WriteAllText($unmarked, 'no markers here', [Text.UTF8Encoding]::new($false))
$threw = $false
try { Merge-PersonalMemory -MemoryPath (Join-Path $Tmp 'x.md') -TemplatePath $unmarked | Out-Null } catch { $threw = $true }
Assert 'a template with no markers is refused' $threw

Write-Host '--- the guidance is reachable from the task that needs it ---'
# A skill is only read when its description matches what the user is doing. The
# PDF and pptx guidance was written into document-formats while its description
# still said "read or convert" - unreachable from making a deck, which is
# exactly when it is needed.
$docFmt = [IO.File]::ReadAllText((Join-Path $Root 'skills/document-formats/SKILL.md'))
$docDesc = ([regex]::Match($docFmt, '(?ms)^description:\s*(.+?)$')).Groups[1].Value
foreach ($topic in @('pptx', 'PDF')) {
    Assert "the description mentions $topic" ($docDesc -match [regex]::Escape($topic))
}
$mem = [IO.File]::ReadAllText($MemTemplate)
Assert 'the memory block names the pptx rule' ($mem -match 'pptx')
Assert 'the memory block names the PDF rule' ($mem -match 'PDF')
Assert 'and points at the skill for the detail' ($mem -match 'document-formats')

Write-Host '--- WhatIf writes nothing ---'
$whatif = Join-Path $Tmp 'whatif.json'
Merge-ClaudeSettings -SettingsPath $whatif -WhatIfOnly | Out-Null
Assert 'WhatIf writes no settings file' (-not (Test-Path $whatif))

$memWhatIf = Join-Path $Tmp 'mem-whatif.md'
Merge-PersonalMemory -MemoryPath $memWhatIf -TemplatePath $MemTemplate -WhatIfOnly | Out-Null
Assert 'WhatIf writes no memory file' (-not (Test-Path $memWhatIf))

# Regression: the first dry run of the installer wrote both skills into the
# real user profile because this function ignored the switch entirely.
$skillDest = Join-Path $Tmp 'skills-dest'
$w = Install-ClaudeSkills -SourceDir (Join-Path $Root 'skills') -DestRoot $skillDest -WhatIfOnly
Assert 'WhatIf still reports which skills it would install' (@($w.Installed).Count -gt 0)
Assert 'WhatIf writes no skill file' (-not (Test-Path $skillDest))

$r = Install-ClaudeSkills -SourceDir (Join-Path $Root 'skills') -DestRoot $skillDest
Assert 'without WhatIf the skills are written' ((@(Get-ChildItem -Path $skillDest -Recurse -Filter 'SKILL.md' -ErrorAction SilentlyContinue)).Count -eq @($r.Installed).Count)
$r2 = Install-ClaudeSkills -SourceDir (Join-Path $Root 'skills') -DestRoot $skillDest
Assert 'a second skill install reports them unchanged' (@($r2.Unchanged).Count -eq @($r.Installed).Count)

Write-Host '--- the pinned python goes to the front of the user PATH ---'
# The regression this catches: on a fresh Windows the only `python` on PATH is
# the Microsoft Store alias stub, so the libraries land in the pinned version
# and the document skills call something that opens the Store instead. Nothing
# here touches the registry - the function takes and returns a PATH string.
$upPyDir   = 'C:\Users\tester\AppData\Local\Programs\Python\Python312'
$upScripts = "$upPyDir\Scripts"
$upStub    = 'C:\Users\tester\AppData\Local\Microsoft\WindowsApps'
$upOther   = 'C:\Users\tester\AppData\Local\Programs\Python\Python313'

$upEmpty = Merge-PythonUserPath -UserPath '' -PythonDir $upPyDir
Assert 'an empty user PATH gains both directories' ($upEmpty.Path -eq "$upPyDir;$upScripts")
Assert 'and that counts as a change' ($upEmpty.Changed -eq $true)
Assert 'the new PATH comes back as one string, not a list' ($upEmpty.Path -is [string])

$upFixed = Merge-PythonUserPath -UserPath "$upStub;C:\tools" -PythonDir $upPyDir
$upParts = @($upFixed.Path -split ';')
Assert 'the interpreter is put ahead of the Store stub' (($upParts -contains $upPyDir) -and ($upParts.IndexOf($upPyDir) -lt $upParts.IndexOf($upStub)))
Assert 'the Scripts folder comes with it' (($upParts -contains $upScripts) -and ($upParts.IndexOf($upScripts) -lt $upParts.IndexOf($upStub)))
Assert 'entries that were already there are kept' (($upParts -contains 'C:\tools') -and ($upParts -contains $upStub))
Assert 'and nothing is listed twice' ($upParts.Count -eq @($upParts | Select-Object -Unique).Count)

# Idempotence: two runs of the installer have to leave the same PATH behind.
$upAgain = Merge-PythonUserPath -UserPath $upFixed.Path -PythonDir $upPyDir
Assert 'a second pass finds nothing to change' ($upAgain.Changed -eq $false)
Assert 'and hands the same PATH back untouched' ($upAgain.Path -eq $upFixed.Path)

# One condition off at a time. Given only an all-right and an all-wrong
# fixture, half the check can be deleted and everything still passes.
$upNoScripts = Merge-PythonUserPath -UserPath "$upPyDir;$upStub" -PythonDir $upPyDir
Assert 'the interpreter alone is not enough, Scripts has to be there too' ($upNoScripts.Changed -eq $true)
Assert 'and Scripts is placed directly behind the interpreter' ($upNoScripts.Path.StartsWith("$upPyDir;$upScripts;"))

$upBehind = Merge-PythonUserPath -UserPath "$upOther;$upPyDir;$upScripts;$upStub" -PythonDir $upPyDir
Assert 'another python sitting in front is moved behind the pinned one' ($upBehind.Changed -eq $true)
$upBparts = @($upBehind.Path -split ';')
Assert 'the pinned interpreter ends up first' ($upBparts[0] -eq $upPyDir)
Assert 'the other python is kept, only later' (($upBparts -contains $upOther) -and ($upBparts.IndexOf($upOther) -gt $upBparts.IndexOf($upPyDir)))
Assert 'a directory that had to be moved is not left behind as a second copy' ($upBparts.Count -eq @($upBparts | Select-Object -Unique).Count)

# Order inside the phase: pip has to run after the PATH is in order, or the
# first install spends twenty lines warning that the Scripts folder it is
# writing into cannot be reached.
$iLibsPhase = Find-Phase 'Python libraries'
$iNextPhase = Find-Phase 'Claude Code'
Assert 'the python phase is found' (($iLibsPhase -ge 0) -and ($iNextPhase -gt $iLibsPhase))
$libsPhase = $setupText.Substring($iLibsPhase, $iNextPhase - $iLibsPhase)
Assert 'the phase puts the user PATH in order itself' ($libsPhase -match 'Merge-PythonUserPath')
Assert 'and does it before pip runs' (
    $libsPhase.IndexOf('Merge-PythonUserPath') -lt $libsPhase.IndexOf('Install-PythonLibraries'))
Assert 'a dry run writes no PATH' ($libsPhase -match '\$pyDir -and -not \$WhatIfOnly')
Assert 'the session picks the new PATH up, so the check below sees it' ($libsPhase -match 'Update-SessionPath')

Write-Host '--- requirements.txt ---'
Assert 'requirements.txt ships with the folder' (Test-Path $Req)
$reqText  = [IO.File]::ReadAllText($Req)
$reqNames = Get-RequirementNames -Path $Req

# Counted, not hardcoded: adding a line must not need this number updated.
$reqLines = @(($reqText -split "`n") | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ })
Assert 'every requirement line yields exactly one name' (@($reqNames).Count -eq $reqLines.Count)
Assert 'the list is not empty' (@($reqNames).Count -gt 0)
Assert 'names carry no version constraint' (@($reqNames | Where-Object { $_ -match '[\[<>=!~;]' }).Count -eq 0)

# markitdown installed bare cannot read pptx or docx: one extra is one format.
Assert 'markitdown asks for the format extras' ($reqText -match 'markitdown\[[^\]]*docx[^\]]*\]' -and $reqText -match 'markitdown\[[^\]]*pptx[^\]]*\]')

Write-Host '--- the shipped skills can actually run ---'
# The regression this catches: shipping a skill whose tooling was never
# installed. Derived from the skill text, so a new skill is covered for free.
$skillFiles = @(Get-ChildItem -Path (Join-Path $Root 'skills') -Recurse -Filter 'SKILL.md')
Assert 'skills ship' ($skillFiles.Count -gt 0)
$skillText = ($skillFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"

$modules = @([regex]::Matches($skillText, 'python -m ([A-Za-z0-9_\-]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
Assert 'at least one skill calls a python module' ($modules.Count -gt 0)
$unmet = @($modules | Where-Object { $reqNames -notcontains $_ })
Assert "every python module a skill calls is in requirements.txt (missing: $($unmet -join ', '))" ($unmet.Count -eq 0)
Assert 'pypdf, which a skill names, is in requirements.txt' ($reqNames -contains 'pypdf')

Write-Host '--- nothing points at a skill we do not ship ---'
$shipped  = @(Get-ChildItem -Path (Join-Path $Root 'skills') -Directory | Select-Object -ExpandProperty Name)
$hookText = (@(Get-ChildItem -Path (Join-Path $Root 'hooks') -Filter '*.ps1') | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
Assert 'the docker hook still names a skill as its source of truth' ($hookText -match 'register-corp-certs')
Assert 'that skill is one we ship' ($shipped -contains 'register-corp-certs')

Write-Host '--- which PowerShell Claude Code will run ---'
# There is no settings key for this. Claude Code probes three fixed paths and
# falls back to Windows PowerShell 5.1 when none of them holds a pwsh 7.
$ps7 = Test-ClaudePowerShell
Assert 'three paths are probed' (@($ps7.Probes).Count -eq 3)
Assert 'Program Files is probed first' ($ps7.Probes[0] -match 'PowerShell\\7\\pwsh\.exe$')
Assert 'the WindowsApps location is probed' (@($ps7.Probes) -match 'WindowsApps\\pwsh\.exe$')
Assert 'this machine will not fall back to PowerShell 5.1' ($ps7.Ok)

Write-Host '--- the double-click launcher ---'
$Cmd = Join-Path $Root 'setup.cmd'
Assert 'setup.cmd ships' (Test-Path $Cmd)
$cmdText = [IO.File]::ReadAllText($Cmd)
Assert 'the launcher hands off to setup.ps1' ($cmdText -match 'setup\.ps1')
Assert 'the launcher resolves pwsh rather than assuming PATH' ($cmdText -match 'ProgramFiles%\\PowerShell\\7\\pwsh\.exe')

# Windows PowerShell 5.1 refuses a #Requires -Version 7.0 script with an error
# and still exits 0, so any fallback to it would read as success while nothing
# ran. There must be no path from this launcher to powershell.exe.
Assert 'the launcher never falls back to Windows PowerShell' ($cmdText -notmatch 'powershell\.exe')
Assert 'the launcher passes the script exit code back out' ($cmdText -match 'exit /b')
Assert 'the launcher builds an absolute path from %~dp0' ($cmdText -match '%~dp0setup\.ps1')

Write-Host '--- one clean host does not clear the network ---'
# The appliance intercepts selectively: pypi.org arrives untouched while
# api.anthropic.com does not. Judging on pypi.org alone reported a clean
# network on a machine whose Claude Code could not reach its own API, and the
# certificates the run exists to install were skipped on the very machines
# that needed them.
Assert 'one intercepted host among clean ones settles it' ((Resolve-SslVerdict -Verdicts @('clean','intercepted','clean')) -eq 'intercepted')
Assert 'all clean is clean' ((Resolve-SslVerdict -Verdicts @('clean','clean')) -eq 'clean')
Assert 'nothing reachable stays unknown' ((Resolve-SslVerdict -Verdicts @('unknown','unknown')) -eq 'unknown')
Assert 'one reachable clean host outranks unreachable ones' ((Resolve-SslVerdict -Verdicts @('unknown','clean')) -eq 'clean')
Assert 'an interception outranks an unreachable host' ((Resolve-SslVerdict -Verdicts @('unknown','intercepted')) -eq 'intercepted')

# The host Claude Code itself must reach has to be judged, or the run can pass
# on a machine where Claude Code cannot start a conversation.
Assert 'the probe list names the API host Claude Code needs' ($script:ProbeHosts -contains 'api.anthropic.com')
Assert 'the probe list keeps the package hosts too' (($script:ProbeHosts -contains 'pypi.org') -and ($script:ProbeHosts -contains 'registry.npmjs.org'))
Assert 'both decision points judge across hosts, not on one' ((([regex]::Matches($setupText, 'Test-SslInterceptedAcross -PublicRootPemText')).Count) -eq 2)

$across = Test-SslInterceptedAcross -TargetHosts @('no-such-host.invalid') -PublicRootPemText (Get-PublicRootPem -SeedPem $Seed).Text -TimeoutMs 4000
Assert 'a list of unreachable hosts yields unknown' ($across.Verdict -eq 'unknown')
Assert 'the verdict says which hosts were tried' ($across.Checked -match 'no-such-host.invalid')

Write-Host '--- node is verified too, because Claude Code runs on node ---'
# python on Windows reads the Windows certificate store; node reads neither
# that nor certifi, only its own roots plus NODE_EXTRA_CA_CERTS. A python-only
# verification therefore printed a green line on a machine where node - and so
# Claude Code - could not open api.anthropic.com.
$onlyTestRoot = Join-Path $Tmp 'only-test-root.pem'
[IO.File]::WriteAllText($onlyTestRoot, (Get-CorpRootPem -CrtPath $TestCrt))
$nodeBogus = Test-NodeTrust -BundlePath $onlyTestRoot -Url 'https://pypi.org'
if ($nodeBogus.Available) {
    Assert 'a bundle without the public roots fails the node check' ($nodeBogus.Ok -eq $false)
    Assert 'and the machine own roots pass it' ((Test-NodeTrust -BundlePath '' -Url 'https://pypi.org').Ok -eq $true)
} else {
    Write-Host '      skipped: node is not on this machine'
}
Assert 'the verify phase runs the node check' ($verifyPhase -match 'Test-NodeTrust')
Assert 'the node check aims at the host Claude Code needs' ($setupText -match 'https://api\.anthropic\.com')

Write-Host '--- Windows Terminal settings ---'
# The three settings are merged into whatever is already in the file rather
# than replacing it: this is somebody's own terminal configuration.
$wtIn = '{"copyOnSelect":false,"profiles":{"defaults":{},"list":[{"name":"PowerShell"}]}}'
$m1 = Merge-TerminalDefaults -Json $wtIn
$o1 = $m1.Json | ConvertFrom-Json
Assert 'the first merge reports a change' ($m1.Changed -eq $true)
Assert 'antialiasing is set to aliased' ($o1.profiles.defaults.antialiasingMode -eq 'aliased')
Assert 'the font face is set' ($o1.profiles.defaults.font.face -eq 'GulimChe')
# '10' -eq 10 is true in PowerShell - the left side wins the coercion - so
# the value has to be asked about its type as well as its worth.
Assert 'the font size is a number and not a string' (
    ($o1.profiles.defaults.font.size -eq 10) -and ($o1.profiles.defaults.font.size -isnot [string]))
Assert 'an unrelated setting survives' ($o1.copyOnSelect -eq $false)
Assert 'the profile list survives' ($o1.profiles.list[0].name -eq 'PowerShell')
# On defaults, so profiles Terminal generates later for WSL or git bash are
# covered too. Written onto a profile it would reach only that one.
Assert 'the settings land on defaults and not on one profile' (
    $o1.profiles.list[0].PSObject.Properties.Name -notcontains 'font')

# A second run must leave the file alone, or every run rewrites it.
$m2 = Merge-TerminalDefaults -Json $m1.Json
Assert 'the second merge reports no change' ($m2.Changed -eq $false)
Assert 'and it produces the same text' ($m2.Json -eq $m1.Json)

# Half right is not right. A file that already carries the antialiasing but a
# different font has to be reported as needing a change, or the run reads its
# own first setting back and calls the job done.
$mHalf = Merge-TerminalDefaults -Json (
    '{"profiles":{"defaults":{"antialiasingMode":"aliased","font":{"face":"Consolas","size":14}}}}')
Assert 'a file that is only half right still reports a change' ($mHalf.Changed -eq $true)
Assert 'and the font is the one asked for' (
    ($mHalf.Json | ConvertFrom-Json).profiles.defaults.font.face -eq 'GulimChe')
Assert 'and once corrected it settles' ((Merge-TerminalDefaults -Json $mHalf.Json).Changed -eq $false)

# No settings file at all is what a Terminal that was never opened looks like.
$mEmpty = Merge-TerminalDefaults -Json ''
Assert 'a machine with no settings file still gets the font' (
    ($mEmpty.Json | ConvertFrom-Json).profiles.defaults.font.face -eq 'GulimChe')

# Terminal allows // comments in this file and people do write them.
$mComment = Merge-TerminalDefaults -Json ('{' + $nlTest + '  // mine' + $nlTest +
                                          '  "copyOnSelect": true' + $nlTest + '}')
Assert 'a settings file carrying a comment still merges' (
    ($mComment.Json | ConvertFrom-Json).copyOnSelect -eq $true)

# Anything else the person chose under defaults, and under font, is theirs.
$mKeep = Merge-TerminalDefaults -Json (
    '{"profiles":{"defaults":{"font":{"weight":"bold"},"cursorShape":"bar"}}}')
$oKeep = $mKeep.Json | ConvertFrom-Json
Assert 'an existing font weight survives' ($oKeep.profiles.defaults.font.weight -eq 'bold')
Assert 'an existing default survives' ($oKeep.profiles.defaults.cursorShape -eq 'bar')

# Terminal 0.x wrote profiles as a bare list. Merging into that shape would
# replace the whole list with an object and lose every profile in it.
$threw = $false
try { $null = Merge-TerminalDefaults -Json '{"profiles":[{"name":"old"}]}' } catch { $threw = $true }
Assert 'a legacy profile list is refused rather than overwritten' $threw

Write-Host '--- the shortcut that opens the terminal ---'
$lnkDir  = Join-Path $Tmp 'lnk'
$lnkPath = Join-Path $lnkDir 'PowerShell 7.lnk'
$fakeWt   = Join-Path $Tmp 'wt.exe'
$fakeIcon = Join-Path $Tmp 'pwsh.exe'
[IO.File]::WriteAllText($fakeWt, 'x')
[IO.File]::WriteAllText($fakeIcon, 'x')
$s1 = Install-TerminalShortcut -Path $lnkPath -Terminal $fakeWt -IconSource $fakeIcon
Assert 'the shortcut appears' (Test-Path -LiteralPath $lnkPath)
Assert 'the first write reports a change' ($s1.Changed -eq $true)
$wsh = New-Object -ComObject WScript.Shell
$rd  = $wsh.CreateShortcut($lnkPath)
Assert 'it opens the terminal' ($rd.TargetPath -eq $fakeWt)
Assert 'it asks for the PowerShell profile by name' ($rd.Arguments -eq '-p "PowerShell"')
Assert 'it takes its icon from PowerShell 7' ($rd.IconLocation -eq "$fakeIcon,0")

$s2 = Install-TerminalShortcut -Path $lnkPath -Terminal $fakeWt -IconSource $fakeIcon
Assert 'a second run reports no change' ($s2.Changed -eq $false)

# A shortcut of the right name left over from an earlier version has to be
# corrected. Stopping at "the file is there" would leave it pointing away.
$stale = $wsh.CreateShortcut($lnkPath)
$stale.Arguments = '-p "Something Else"'
$stale.Save()
$s3 = Install-TerminalShortcut -Path $lnkPath -Terminal $fakeWt -IconSource $fakeIcon
Assert 'a stale shortcut is rewritten' ($s3.Changed -eq $true)
Assert 'and it points back at the PowerShell profile' (
    $wsh.CreateShortcut($lnkPath).Arguments -eq '-p "PowerShell"')

$whatIfPath = Join-Path $lnkDir 'untouched.lnk'
$null = Install-TerminalShortcut -Path $whatIfPath -Terminal $fakeWt -WhatIfOnly
Assert 'WhatIf writes no shortcut' (-not (Test-Path -LiteralPath $whatIfPath))

Write-Host '--- where the terminal phase sits ---'
$iTerm  = Find-Phase 'Windows Terminal'
$iWire  = Find-Phase 'Claude Code wiring'
Assert 'the terminal phase is in the run' ($iTerm -gt 0)
Assert 'and it sits between the PATH phase and the Claude wiring' (
    ($iTerm -gt (Find-Phase 'User PATH')) -and ($iTerm -lt $iWire))

# None of this is needed for Claude Code to work, so a font that could not be
# set must not take the install down with it.
$termPhase = $setupText.Substring($iTerm, $iWire - $iTerm)
Assert 'a terminal problem cannot stop the install' ($termPhase -notmatch '(?m)^\s*exit ')
Assert 'the phase can be turned off' ($termPhase -match '\$SkipTerminal')

# Renumbering by hand is how the phase numbers drift apart. Counted here
# rather than compared against a number written down, which would be one
# more place to keep in step.
$steps  = [regex]::Matches($setupText, "Write-Step '(\d+)/(\d+)")
$totals = @($steps | ForEach-Object { $_.Groups[2].Value }) | Select-Object -Unique
Assert 'every phase agrees on how many phases there are' (@($totals).Count -eq 1)
Assert 'the phases run from 0 to that number with no gap' (
    ((@($steps | ForEach-Object { [int]$_.Groups[1].Value }) | Sort-Object) -join ',') -eq
    ((0..[int](@($totals)[0])) -join ','))
Write-Host '--- the shortcut picture ---'
# The drawing ships as a PNG; Windows shortcuts want an .ico. Nothing else in
# the payload carries the picture, so its absence would silently downgrade
# every shortcut to the PowerShell icon without anybody noticing.
Assert 'the drawing ships with the payload' (Test-Path -LiteralPath $IconPng)

$icoDir = Join-Path $Tmp 'built'
$ico1 = New-IconFromPng -PngPath $IconPng -IcoDir $icoDir
$icoOut = $ico1.Path
Assert 'the icon file appears' (Test-Path -LiteralPath $icoOut)
Assert 'the first build reports a change' ($ico1.Changed -eq $true)
Assert 'and it lands in the folder it was given' (
    (Split-Path -Parent $icoOut) -eq $icoDir)

# Windows draws the picture it remembers for an icon path even after the file
# there changes, so a redrawn icon has to arrive under a name nothing has seen.
# The name therefore carries a stamp of the bytes. Without this the black tile
# built above stays invisible on every machine that installed the old one.
Assert 'the name carries a stamp of the bytes' (
    (Split-Path $icoOut -Leaf) -match '^claudecode-[0-9a-f]{8}\.ico$')

# Read back at the sizes the shell actually asks for. An .ico that only
# carries one size is scaled by the shell and looks it on the taskbar.
Add-Type -AssemblyName System.Drawing
$gotSizes = foreach ($s in @(16, 24, 32, 48)) {
    $i = [System.Drawing.Icon]::new($icoOut, $s, $s)
    $w = $i.Width
    $i.Dispose()
    $w
}
Assert 'every size the shell asks for is really in the file' (
    (@($gotSizes) -join ',') -eq '16,24,32,48')

# Same drawing through the same code has to give the same bytes, or every run
# rewrites the file and reports work it did not do.
$ico2 = New-IconFromPng -PngPath $IconPng -IcoDir $icoDir
Assert 'a second build reports no change' ($ico2.Changed -eq $false)
Assert 'and the file is not rewritten' ($ico2.Bytes -eq $ico1.Bytes)
Assert 'and it keeps the same name' ($ico2.Path -eq $ico1.Path)

# A stamp that never moves would pass the shape check above and still leave
# every machine showing the picture it drew the first time. So a different
# drawing has to reach a different name.
$otherPng = Join-Path $Tmp 'other.png'
$ob = [System.Drawing.Bitmap]::new(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$og = [System.Drawing.Graphics]::FromImage($ob)
$og.Clear([System.Drawing.Color]::FromArgb(255, 10, 200, 40))
$og.Dispose()
$ob.Save($otherPng, [System.Drawing.Imaging.ImageFormat]::Png)
$ob.Dispose()
$ico3 = New-IconFromPng -PngPath $otherPng -IcoDir $icoDir
Assert 'a different drawing reaches a different name' ($ico3.Path -ne $ico1.Path)

# The tile behind the mark has to be solid black, not the transparency the
# source PNG carries. Every corner is read, because filling only the big canvas
# and leaving the shrunk frames cleared to transparent would show at the edges
# of the small sizes and nowhere else.
$corners = foreach ($s in @(16, 128)) {
    $f = [System.Drawing.Icon]::new($icoOut, $s, $s).ToBitmap()
    $last = $s - 1
    foreach ($x in @(0, $last)) {
        foreach ($y in @(0, $last)) { $f.GetPixel($x, $y) }
    }
    $f.Dispose()
}
Assert 'the icon sits on an opaque black tile' (
    @($corners | Where-Object {
        ($_.A -ne 255) -or ($_.R -ne 0) -or ($_.G -ne 0) -or ($_.B -ne 0)
    }).Count -eq 0)

# The drawing sits off-centre on a much bigger empty canvas - more empty space
# above it than below. Dropped in without cropping it comes out hanging low in
# the icon, so this measures the four margins of a built frame rather than
# trusting that the crop happened. 128 is used because the same lopsided gap is
# only a pixel at 32 and would make the check a coin toss. The mark is found by
# what is not black, since the tile made every pixel opaque and an alpha crop
# would now hand back the whole frame whatever the builder did.
$frame = [System.Drawing.Icon]::new($icoOut, 128, 128).ToBitmap()
$minX = 128; $minY = 128; $maxX = -1; $maxY = -1
for ($y = 0; $y -lt 128; $y++) {
    for ($x = 0; $x -lt 128; $x++) {
        $px = $frame.GetPixel($x, $y)
        if (($px.R + $px.G + $px.B) -gt 24) {
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
$frame.Dispose()
Assert 'the mark is drawn on the tile rather than lost in it' ($maxX -ge 0)
$drawn = [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)
$leftGap   = $drawn.X
$rightGap  = 128 - ($drawn.X + $drawn.Width)
$topGap    = $drawn.Y
$bottomGap = 128 - ($drawn.Y + $drawn.Height)
Assert 'the drawing is centred in the icon' (
    ([Math]::Abs($leftGap - $rightGap) -le 2) -and ([Math]::Abs($topGap - $bottomGap) -le 2))
Assert 'and it fills the icon rather than floating in it' ($drawn.Width -ge 108)

# A canvas with nothing on it must not crash the crop with an empty rectangle.
$blank = [System.Drawing.Bitmap]::new(8, 8, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$blankBox = Get-OpaqueBounds -Bitmap $blank
$blank.Dispose()
Assert 'an empty drawing yields the whole canvas, not nothing' (
    ($blankBox.Width -eq 8) -and ($blankBox.Height -eq 8))

$whatIfDir = Join-Path $Tmp 'untouched'
$icoWhatIf = New-IconFromPng -PngPath $IconPng -IcoDir $whatIfDir -WhatIfOnly
Assert 'WhatIf builds no icon file' (-not (Test-Path -LiteralPath $icoWhatIf.Path))
Assert 'and it still says where the icon would go' (
    (Split-Path -Parent $icoWhatIf.Path) -eq $whatIfDir)

# The phase points the shortcut at whatever name the builder chose. Left as a
# name written out by hand it would go on pointing at the picture Windows has
# already cached, and every check above would still pass.
Assert 'the phase takes the icon path from the builder' (
    $termPhase -match '\$icoPath\s*=\s*\$ico\.Path')
Assert 'and clears out the icons earlier runs left behind' (
    $termPhase -match "Filter 'claudecode\*\.ico'")

# The phase has to prefer the built icon and keep pwsh.exe as the fallback.
# Written the other way round the drawing would never appear, and every test
# above would still pass because the builder itself would be fine.
Assert 'the phase builds the icon from the shipped drawing' (
    $termPhase -match 'New-IconFromPng')
Assert 'and falls back to the PowerShell icon when it cannot' (
    $termPhase -match 'Test-ClaudePowerShell')
Assert 'the built icon is kept on the local disk, not on the share' (
    $setupText -match '\$IconDir\s*=\s*Join-Path \(\$env:LOCALAPPDATA')
Write-Host '--- encoding contract ---'
# Korean in a BOM-less .ps1 is read in the system code page by Windows
# PowerShell and the file stops parsing. ASCII plus CRLF is read the same way
# under every code page, with or without a BOM.
foreach ($f in @((Join-Path $Root 'setup.ps1'), $PSCommandPath)) {
    $name  = Split-Path $f -Leaf
    $bytes = [IO.File]::ReadAllBytes($f)
    Assert "$name is ASCII only" (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    Assert "$name uses CRLF throughout" (([regex]::Matches($text, "(?<!`r)`n")).Count -eq 0)
}

Remove-Item -Recurse -Force $Tmp
Write-Host ''
Write-Host ("PASS={0} FAIL={1}" -f $script:Pass, $script:Fail)
if ($script:Fail -ne 0) { exit 1 }
