# document-formats 플러그인 분리 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `document-formats` 스킬을 새 플러그인 레포 `KiwoomAX/KW-doc-formats`로 옮기고, kw_install 설치기가 그 플러그인을 설치하며 옛 사본을 안전하게 걷어내게 한다.

**Architecture:** 새 레포는 disciplined-coder와 같은 꼴로 레포 루트가 곧 플러그인이고 마켓플레이스 파일도 같은 레포에 둔다. kw_install은 `$script:Plugins` 한 줄로 선언과 설치를 만들며, 설치 성공을 `installed_plugins.json`으로 판정하고, 확인된 뒤에만 `~/.claude/skills/document-formats`를 사본을 남기고 지운다.

**Tech Stack:** PowerShell 7 (pwsh 7.6.5), `claude` CLI, `gh` CLI, git.

**Spec:** `docs/superpowers/specs/2026-09-05-doc-formats-plugin-split-design.md`

## Global Constraints

- `setup.ps1`과 `tests/test_setup.ps1`은 **ASCII만** 쓰고 **CRLF** 줄 끝을 유지한다. 테스트가 둘 다 검사한다. 한글은 `templates/`와 `docs/`와 `README.md`에만 쓴다. 두 파일에 넣는 새 코드와 주석은 영어로 쓴다.
- 플러그인·마켓플레이스 이름은 소문자 `kw-doc-formats`, GitHub 레포는 `KiwoomAX/KW-doc-formats`, 플러그인 id는 `kw-doc-formats@kw-doc-formats`, 스킬 호출 이름은 `kw-doc-formats:document-formats`다.
- `plugin.json`에 `version`을 두지 않는다. `claude plugin validate`의 version 경고는 수용한다.
- 새 레포의 `.claude-plugin/plugin.json`의 `description`과 `marketplace.json`의 `plugins[0].description`은 글자 그대로 같다.
- 사용자 파일을 고칠 때는 사용자가 넣어 둔 값을 덮지 않고, `.bak`을 남기고, 다시 파싱해 유효할 때만 쓴다.
- 기준선: 지금 `tests/test_setup.ps1`은 PASS 258, FAIL 5다. 다섯 실패는 모두 `certs/combined_cacert.pem`이 레포에 없어서 나는 것이며(`.gitignore`) 이 작업과 무관하다. 작업 뒤에도 그 다섯만 실패해야 한다.
- Task는 번호 순서대로 돈다. Task 3(레포 공개)이 끝나기 전에 Task 8(드라이런)을 돌리지 않는다. Task 8 Step 0이 이를 확인한다. 이 PC에서 설치기를 실제로 돌리지 않는다. 사용자 결정이다.
- 커밋 메시지 끝에 아래 두 줄을 붙인다.
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01X9XzW5b9hMbZ3RTcbJupcv
  ```
- CRLF 정규화: `setup.ps1`이나 `tests/test_setup.ps1`을 고친 뒤 테스트 전에 아래를 돌린다. Edit 도구가 LF를 섞어 넣을 수 있다. UTF-8로 쓰므로 비ASCII가 섞였으면 그대로 남아 ASCII 테스트가 잡는다. 스니펫이 비ASCII를 바꿔치기하지 않는다.
  ```powershell
  foreach ($p in @('D:\projects\kw_install\setup.ps1','D:\projects\kw_install\tests\test_setup.ps1')) {
    $t = [IO.File]::ReadAllText($p) -replace "(?<!`r)`n", "`r`n"
    [IO.File]::WriteAllText($p, $t, [Text.UTF8Encoding]::new($false))
  }
  ```

---

## 파일 구조

새 레포 `D:\projects\KW-doc-formats`:

| 경로 | 책임 |
|---|---|
| `.claude-plugin/plugin.json` | 플러그인 이름과 설명 |
| `.claude-plugin/marketplace.json` | 마켓플레이스 이름과 플러그인 항목 하나 |
| `skills/document-formats/SKILL.md` | 옮긴 스킬 본문. 엑셀 절이 추가된다 |
| `README.md` | 무엇이 들어 있고 어떻게 깔고 무엇을 전제하는지 |
| `tests/test_plugin.ps1` | 계약 검사 |
| `.gitignore` | 세션 로컬 설정 제외 |

kw_install:

| 경로 | 바뀌는 것 |
|---|---|
| `setup.ps1` | `$script:Plugins` 한 줄과 주석, `Merge-ClaudeSettings`의 autoUpdate, 새 함수 `Test-PluginInstalled`·`Set-MarketplaceAutoUpdate`·`Remove-RetiredClaudeSkill`, `Install-ClaudePlugins` 판정, 8단계 배선, 머리말 주석 |
| `tests/test_setup.ps1` | 플러그인 목록, autoUpdate, 새 함수 셋의 검사. 스킬-모듈 대조와 description 검사 제거 |
| `skills/document-formats/` | 삭제 |
| `templates/personal-memory-ko.md` | 스킬 이름을 전체 이름으로 |
| `README.md`, `docs/CHANGES-ON-THIS-PC.md` | 표와 수 |

---

### Task 1: 새 레포 뼈대와 계약 테스트

**Files:**
- Create: `D:\projects\KW-doc-formats\tests\test_plugin.ps1`
- Create: `D:\projects\KW-doc-formats\.claude-plugin\plugin.json`
- Create: `D:\projects\KW-doc-formats\.claude-plugin\marketplace.json`
- Create: `D:\projects\KW-doc-formats\skills\document-formats\SKILL.md` (복사)
- Create: `D:\projects\KW-doc-formats\README.md`
- Create: `D:\projects\KW-doc-formats\.gitignore`

**Interfaces:**
- Consumes: 없음.
- Produces: 플러그인 이름 `kw-doc-formats`, 스킬 `document-formats`. Task 3이 GitHub에 올리고 Task 4가 kw_install에서 이 이름을 적는다.

- [ ] **Step 1: 폴더를 만들고 git을 연다**

```powershell
New-Item -ItemType Directory -Force -Path 'D:\projects\KW-doc-formats\tests','D:\projects\KW-doc-formats\.claude-plugin','D:\projects\KW-doc-formats\skills\document-formats' | Out-Null
git -C 'D:\projects\KW-doc-formats' init -b main
```

- [ ] **Step 2: 실패하는 계약 테스트를 쓴다**

`D:\projects\KW-doc-formats\tests\test_plugin.ps1` (UTF-8 with BOM. 한글 문자열을 담는다). 파일이 없을 때도 FAIL 목록과 `PASS=`/`FAIL=` 줄까지 찍히도록, 읽기는 `Test-Path`로 감싼다.

```powershell
#Requires -Version 7.0
# Contract tests for the kw-doc-formats plugin.
#   pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test_plugin.ps1

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

$script:Pass = 0
$script:Fail = 0
function Assert($label, $cond) {
    if ($cond) { $script:Pass++; Write-Host "PASS  $label" -ForegroundColor Green }
    else       { $script:Fail++; Write-Host "FAIL  $label" -ForegroundColor Red }
}
# Reads JSON if the file exists, else $null, so a missing file is a FAIL line
# and not a crash before the totals print.
function Read-JsonOrNull($path) {
    if (Test-Path $path) { return (Get-Content $path -Raw | ConvertFrom-Json) }
    return $null
}
function Read-TextOrEmpty($path) {
    if (Test-Path $path) { return [IO.File]::ReadAllText($path) }
    return ''
}

$PluginName = 'kw-doc-formats'

Write-Host '--- manifests ---'
$pluginJson = Join-Path $Root '.claude-plugin/plugin.json'
$mktJson    = Join-Path $Root '.claude-plugin/marketplace.json'
Assert 'plugin.json exists' (Test-Path $pluginJson)
Assert 'marketplace.json exists' (Test-Path $mktJson)
$plugin = Read-JsonOrNull $pluginJson
$mkt    = Read-JsonOrNull $mktJson

# kw_install writes this string into $script:Plugins; it is pinned here so the
# two repos cannot drift without one of them failing.
Assert "plugin.json name is $PluginName" ($plugin.name -eq $PluginName)
Assert "marketplace name is $PluginName" ($mkt.name -eq $PluginName)
Assert 'the marketplace lists exactly one plugin' (@($mkt.plugins).Count -eq 1)
Assert "that plugin is $PluginName" ($mkt.plugins[0].name -eq $PluginName)
Assert 'the plugin source is the repo root' ($mkt.plugins[0].source -eq './')
Assert 'both descriptions are the same text' ($null -ne $plugin.description -and $plugin.description -eq $mkt.plugins[0].description)
Assert 'plugin.json carries no version (commit-based auto update)' ($null -ne $plugin -and $null -eq $plugin.PSObject.Properties['version'])

Write-Host '--- skills ---'
$skillDirs = @(Get-ChildItem -Path (Join-Path $Root 'skills') -Directory -ErrorAction SilentlyContinue)
Assert 'at least one skill ships' ($skillDirs.Count -gt 0)
foreach ($d in $skillDirs) {
    $md = Join-Path $d.FullName 'SKILL.md'
    Assert "$($d.Name) has SKILL.md" (Test-Path $md)
    $text = Read-TextOrEmpty $md
    $name = ([regex]::Match($text, '(?m)^name:\s*(\S+)\s*$')).Groups[1].Value
    Assert "$($d.Name) frontmatter name matches the folder" ($name -eq $d.Name)
}

# A skill is only read when its description matches what the user is doing.
# Deck and PDF guidance lives in document-formats, so both must be reachable.
$docFmt  = Read-TextOrEmpty (Join-Path $Root 'skills/document-formats/SKILL.md')
$docDesc = ([regex]::Match($docFmt, '(?ms)^description:\s*(.+?)$')).Groups[1].Value
foreach ($topic in @('pptx', 'PDF')) {
    Assert "the description mentions $topic" ($docDesc -match [regex]::Escape($topic))
}

Write-Host '--- claude plugin validate ---'
# Exit code is the verdict. The tool prints warnings for a missing version and
# author and still exits 0; an error exits non-zero.
Push-Location $Root
try {
    $null = & claude plugin validate ./ 2>&1 | Out-String
    $code = $LASTEXITCODE
} finally { Pop-Location }
Assert 'claude plugin validate exits 0 (warnings allowed)' ($code -eq 0)

Write-Host ''
Write-Host ("PASS={0} FAIL={1}" -f $script:Pass, $script:Fail)
if ($script:Fail -ne 0) { exit 1 }
```

- [ ] **Step 3: 테스트를 돌려 실패를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\KW-doc-formats\tests\test_plugin.ps1`
Expected: 마지막에 `PASS=0 FAIL=N` 줄이 찍히고 N은 0보다 크다. `plugin.json exists`, `marketplace.json exists`, `at least one skill ships`, `claude plugin validate exits 0`이 FAIL 목록에 있다. 합계 줄 없이 스크립트가 멈추면 테스트 자체가 깨진 것이다.

- [ ] **Step 4: 매니페스트 둘을 쓴다**

`D:\projects\KW-doc-formats\.claude-plugin\plugin.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "kw-doc-formats",
  "displayName": "KW Doc Formats",
  "description": "사내 문서 형식 처리 스킬(document-formats). 한글(.hwp)·구형 오피스·PDF를 읽는 법, 긴 PDF에서 볼 쪽만 고르는 법, PPT를 만들 때 지킬 글꼴·윤곽선 규칙, 엑셀을 만들 때 지킬 글자 크기 규칙을 담는다. kw_install이 깔아 주는 파이썬 라이브러리와 Poppler를 전제한다.",
  "author": { "name": "KiwoomAX" },
  "license": "UNLICENSED",
  "keywords": ["documents", "hwp", "pdf", "pptx", "xlsx", "korean"]
}
```

`D:\projects\KW-doc-formats\.claude-plugin\marketplace.json`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-marketplace.json",
  "name": "kw-doc-formats",
  "description": "KiwoomAX의 문서 형식 처리 플러그인 마켓플레이스.",
  "owner": { "name": "KiwoomAX" },
  "plugins": [
    {
      "name": "kw-doc-formats",
      "source": "./",
      "description": "사내 문서 형식 처리 스킬(document-formats). 한글(.hwp)·구형 오피스·PDF를 읽는 법, 긴 PDF에서 볼 쪽만 고르는 법, PPT를 만들 때 지킬 글꼴·윤곽선 규칙, 엑셀을 만들 때 지킬 글자 크기 규칙을 담는다. kw_install이 깔아 주는 파이썬 라이브러리와 Poppler를 전제한다."
    }
  ]
}
```

- [ ] **Step 5: 스킬을 그대로 복사한다**

```powershell
Copy-Item 'D:\projects\kw_install\skills\document-formats\SKILL.md' 'D:\projects\KW-doc-formats\skills\document-formats\SKILL.md'
```

- [ ] **Step 6: README와 .gitignore를 쓴다**

`D:\projects\KW-doc-formats\README.md` (바깥 펜스는 백틱 넷이다. 안의 백틱 셋은 파일 내용이다):

````markdown
# KW-doc-formats

클로드 코드 플러그인이다. 사내 문서 형식을 다루는 스킬 `document-formats` 하나가 들어 있다. 한글(.hwp)과 구형 오피스와 PDF를 읽는 법, 긴 PDF에서 볼 쪽만 고르는 법, PPT를 만들 때 지킬 글꼴·윤곽선 규칙, 엑셀을 만들 때 지킬 글자 크기 규칙을 담는다.

## 설치

새 PC 설치기 `kw_install`이 이 플러그인을 함께 깐다. 손으로 깔려면 이렇게 한다.

```
claude plugin marketplace add KiwoomAX/KW-doc-formats
claude plugin install kw-doc-formats@kw-doc-formats
```

스킬은 `kw-doc-formats:document-formats`로 불린다.

## 전제

이 스킬은 kw_install이 깔아 주는 파이썬 3.12 라이브러리와 Poppler가 있는 PC를 전제한다. 라이브러리 목록의 정본은 kw_install 레포의 `requirements.txt`다. 이 레포는 그 목록을 다시 적지 않는다.

스킬 본문에서 새 파이썬 모듈을 부르게 되면 kw_install의 `requirements.txt`도 손으로 맞춰야 한다. 두 레포 사이에는 자동 대조가 없다.

## 검사

```
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test_plugin.ps1
```

매니페스트 이름과 설명의 일치, 스킬 frontmatter, `claude plugin validate`를 본다.
````

`D:\projects\KW-doc-formats\.gitignore`:

```
# session-specific Claude Code local settings (not plugin content)
.claude/settings.local.json
.claude/worktrees/
```

- [ ] **Step 7: 테스트를 돌려 통과를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\KW-doc-formats\tests\test_plugin.ps1`
Expected: `FAIL=0`. validate 출력에 version과 author 경고는 있어도 된다.

- [ ] **Step 8: 커밋**

```powershell
git -C 'D:\projects\KW-doc-formats' add -A
git -C 'D:\projects\KW-doc-formats' commit -m "document-formats 스킬을 플러그인으로 (kw_install에서 분리)"
```

---

### Task 2: 엑셀 글자 크기 규칙

**Files:**
- Modify: `D:\projects\KW-doc-formats\skills\document-formats\SKILL.md` (frontmatter description, 「기존 오피스 문서의 내용을 뽑을 때」 절 앞)
- Test: `D:\projects\KW-doc-formats\tests\test_plugin.ps1`

**Interfaces:**
- Consumes: Task 1의 `test_plugin.ps1`의 `$docFmt`·`$docDesc` 변수.
- Produces: 없음.

- [ ] **Step 1: 실패하는 테스트를 더한다**

`test_plugin.ps1`의 `foreach ($topic in @('pptx', 'PDF')) {...}` 블록 바로 뒤에:

```powershell
# The Excel rule lives in this skill, so making a workbook must reach it too.
Assert 'the description mentions xlsx' ($docDesc -match 'xlsx')
Assert 'the body carries the Excel section' ($docFmt -match '(?m)^## 엑셀을 만들 때 항상 지킬 것')
Assert 'the Excel rule fixes the font size at 11' ($docFmt -match 'size=11')
```

- [ ] **Step 2: 실패를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\KW-doc-formats\tests\test_plugin.ps1`
Expected: `FAIL=3`. 새 셋만 실패한다.

- [ ] **Step 3: description에 엑셀을 더한다**

frontmatter `description:` 줄에서 `발표자료(.pptx)를 만들 때 항상 지켜야 하는 글꼴·윤곽선 규칙과` 바로 앞에 아래를 끼워 넣는다.

```
엑셀(.xlsx)을 만들 때의 글자 크기 규칙,
```

- [ ] **Step 4: 엑셀 절을 더한다**

`## 기존 오피스 문서의 내용을 뽑을 때` 바로 앞에 아래를 넣는다 (바깥 펜스는 백틱 넷. 안의 백틱 셋은 파일 내용이다).

````markdown
## 엑셀을 만들 때 항상 지킬 것

셀 글자 크기는 **11**로 둔다. 엑셀의 기본값이 11이고, `openpyxl`이 새로 만드는 통합 문서의
`Normal` 스타일도 11이다. 셀마다 크기를 따로 지정하지 않는다. 지정해야 하는 자리가 있어도
11로 적는다. 머리글을 돋보이게 하려면 크기가 아니라 굵기와 채우기 색으로 한다. 글꼴 이름은
이 규칙이 다루지 않는다.

```python
from openpyxl.styles import Font
ws["A1"].font = Font(bold=True)             # 크기를 적지 않는다. 11을 물려받는다
ws["A1"].font = Font(size=11, bold=True)    # 적어야 한다면 11이다
```

````

- [ ] **Step 5: 통과를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\KW-doc-formats\tests\test_plugin.ps1`
Expected: `FAIL=0`.

- [ ] **Step 6: 커밋**

```powershell
git -C 'D:\projects\KW-doc-formats' add -A
git -C 'D:\projects\KW-doc-formats' commit -m "엑셀을 만들 때 글자 크기 11 규칙"
```

---

### Task 3: GitHub에 공개하고 설치 명령이 통하는지 확인

**Files:** 없음 (원격 작업)

**Interfaces:**
- Consumes: Task 1·2의 로컬 레포.
- Produces: 퍼블릭 레포 `KiwoomAX/KW-doc-formats`. 이 PC에는 플러그인이 깔린 채로 끝난다. 사용자가 이 PC에서는 설치기를 드라이런만 하기로 정했으므로, 이 Task의 설치가 이 PC가 플러그인을 받는 유일한 길이다.

- [ ] **Step 1: 레포를 만들고 푸시한다**

```powershell
gh repo create KiwoomAX/KW-doc-formats --public --source 'D:\projects\KW-doc-formats' --remote origin --push --description "KiwoomAX 문서 형식 처리 플러그인 (document-formats 스킬)"
gh repo view KiwoomAX/KW-doc-formats --json visibility,url
```
Expected: `"visibility": "PUBLIC"`. 조직 `KiwoomAX`는 멤버의 퍼블릭 레포 생성을 허용한다(`gh api orgs/KiwoomAX`로 확인됨).

- [ ] **Step 2: 설치 명령이 통하는지 한 번 본다**

```powershell
claude plugin marketplace add KiwoomAX/KW-doc-formats
claude plugin install kw-doc-formats@kw-doc-formats
(Get-Content "$env:USERPROFILE\.claude\plugins\installed_plugins.json" -Raw | ConvertFrom-Json).plugins.PSObject.Properties.Name -contains 'kw-doc-formats@kw-doc-formats'
```
Expected: 마지막 줄이 `True`.

- [ ] **Step 3: 이 PC에 남는 것을 적어 둔다**

이 PC의 `~/.claude/skills/document-formats/`(이전 판 설치기가 복사한 개인 사본)는 그대로 둔다. 설치기를 실제로 돌리지 않기로 했으므로 옛 사본 제거는 이 PC에서 일어나지 않는다. 플러그인 스킬과 개인 스킬이 같은 이름으로 둘 다 실리는 상태이며, 최종 보고에 이 사실과 지우는 방법(`Remove-Item -Recurse "$env:USERPROFILE\.claude\skills\document-formats"`)을 적는다.

---

### Task 4: kw_install 플러그인 목록과 autoUpdate 선언

**Files:**
- Modify: `D:\projects\kw_install\setup.ps1` — `$script:Plugins` 목록과 위 주석(229~244행), `Merge-ClaudeSettings`의 `extraKnownMarketplaces` 채우는 부분(1266~1271행)
- Test: `D:\projects\kw_install\tests\test_setup.ps1` — `$WantPlugins`(234~239행), `--- plugin declarations ---` 블록(275~281행)

**Interfaces:**
- Consumes: Task 1이 정한 이름 `kw-doc-formats`. Task 3이 끝나 있어야 하는 것은 아니다(테스트는 문자열만 본다).
- Produces: `$script:Plugins` 행의 선택 키 `AutoUpdate`(bool). Task 5의 `Install-ClaudePlugins`가 읽는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`$WantPlugins` 배열에 한 줄을 더한다.

```powershell
    'kw-doc-formats@kw-doc-formats'
```

`--- plugin declarations ---` 블록의 `foreach ($pl in $script:Plugins)` 루프 뒤에:

```powershell
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
```

- [ ] **Step 2: 실패를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String '^FAIL'`
Expected: 기준선 다섯에 더해 `every plugin that was asked for is configured`, `the replacements are in`, `auto-update on`이 FAIL. `left alone`은 키가 없어 통과할 수도 있다.

- [ ] **Step 3: 목록과 주석을 고친다**

`# One row per plugin.`부터 `$script:RetiredPlugins` 앞 빈 줄까지를 아래로 바꾼다.

```powershell
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
```

- [ ] **Step 4: Merge-ClaudeSettings에 autoUpdate를 넣는다**

```powershell
        foreach ($pl in $script:Plugins) {
            $settings['extraKnownMarketplaces'][$pl.Marketplace] = @{
                source = @{ source = 'github'; repo = $pl.Repo }
            }
            $settings['enabledPlugins'][$pl.Id] = $true
        }
```
을 아래로 바꾼다.

```powershell
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
```

- [ ] **Step 5: CRLF 정규화 뒤 통과를 본다**

Global Constraints의 정규화 스니펫을 돌린 뒤:
Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String '^FAIL|^PASS='`
Expected: FAIL은 기준선 다섯뿐.

- [ ] **Step 6: 커밋**

```powershell
git -C 'D:\projects\kw_install' add setup.ps1 tests/test_setup.ps1
git -C 'D:\projects\kw_install' commit -m "kw-doc-formats 플러그인을 목록에 더하고 자동 갱신을 선언"
```

---

### Task 5: 설치 판정과 레지스트리 자동 갱신

**Files:**
- Modify: `D:\projects\kw_install\setup.ps1` — `Install-ClaudePlugins`(1314~1360행) 앞에 함수 둘을 더하고 본문을 바꾼다
- Test: `D:\projects\kw_install\tests\test_setup.ps1` — `-SkipPlugins writes no plugin keys` 단언 뒤에 새 블록

**Interfaces:**
- Consumes: Task 4의 `$script:Plugins` 행 키 `AutoUpdate`.
- Produces: `Test-PluginInstalled -RegistryPath <string> -Id <string>` → `[bool]`. `Set-MarketplaceAutoUpdate -RegistryPath <string> -Marketplace <string>` → `@{ Status = 'set'|'unchanged'|'failed'; Detail }`. `Install-ClaudePlugins`의 결과 형은 그대로(`@{ Id; Status = 'installed'|'skipped'|'failed'; Detail }`). Task 7이 `Status -eq 'installed'`를 본다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`-SkipPlugins writes no plugin keys` 단언 뒤에:

```powershell
Write-Host '--- a plugin counts as installed only when the CLI recorded it ---'
# The marketplace registry is not proof: `marketplace add` can succeed while
# `plugin install` fails, and a repo name can contain the marketplace name
# (KiwoomAX/KW-doc-formats holds kw-doc-formats, and -match ignores case).
$inst = Join-Path $Tmp 'installed_plugins.json'
@'
{ "version": 2, "plugins": { "kw-doc-formats@kw-doc-formats": [ { "scope": "user", "installPath": "x" } ] } }
'@ | Set-Content -LiteralPath $inst
Assert 'a recorded plugin is installed' (Test-PluginInstalled -RegistryPath $inst -Id 'kw-doc-formats@kw-doc-formats')
Assert 'an unrecorded plugin is not' (-not (Test-PluginInstalled -RegistryPath $inst -Id 'playwright@claude-plugins-official'))
Assert 'a missing file means not installed' (-not (Test-PluginInstalled -RegistryPath (Join-Path $Tmp 'nope.json') -Id 'x@y'))
'not json' | Set-Content -LiteralPath (Join-Path $Tmp 'bad.json')
Assert 'a file that is not JSON means not installed' (-not (Test-PluginInstalled -RegistryPath (Join-Path $Tmp 'bad.json') -Id 'x@y'))

Write-Host '--- auto-update is switched on in the marketplace registry ---'
$reg = Join-Path $Tmp 'known_marketplaces.json'
$regText = @'
{
  "claude-plugins-official": { "source": { "source": "github", "repo": "anthropics/claude-plugins-official" }, "installLocation": "C:\\x", "lastUpdated": "2026-09-05T09:08:52.295Z" },
  "kw-doc-formats": { "source": { "source": "github", "repo": "KiwoomAX/KW-doc-formats" }, "installLocation": "C:\\y", "lastUpdated": "2026-09-05T09:08:53.617Z" },
  "theirs": { "source": { "source": "github", "repo": "someone/theirs" }, "autoUpdate": false }
}
'@
[IO.File]::WriteAllText($reg, $regText, [Text.UTF8Encoding]::new($false))
$s1 = Set-MarketplaceAutoUpdate -RegistryPath $reg -Marketplace 'kw-doc-formats'
$after = Get-Content $reg -Raw | ConvertFrom-Json
Assert 'the key is set on the named marketplace' ($s1.Status -eq 'set' -and $after.'kw-doc-formats'.autoUpdate -eq $true)
Assert 'a backup is left beside the registry' (Test-Path "$reg.bak")
Assert 'every entry survives the rewrite' (@($after.PSObject.Properties.Name).Count -eq 3)
Assert 'other marketplaces are untouched' ($null -eq $after.'claude-plugins-official'.PSObject.Properties['autoUpdate'])
Assert 'the timestamp strings survive the rewrite' (([IO.File]::ReadAllText($reg)) -match '2026-09-05T09:08:52\.295Z')
$s2 = Set-MarketplaceAutoUpdate -RegistryPath $reg -Marketplace 'kw-doc-formats'
Assert 'a second call changes nothing' ($s2.Status -eq 'unchanged')
$s3 = Set-MarketplaceAutoUpdate -RegistryPath $reg -Marketplace 'theirs'
$after3 = Get-Content $reg -Raw | ConvertFrom-Json
Assert 'a value the user set is not overwritten' ($s3.Status -eq 'unchanged' -and $after3.theirs.autoUpdate -eq $false)
$s4 = Set-MarketplaceAutoUpdate -RegistryPath $reg -Marketplace 'unknown'
Assert 'an unregistered marketplace is reported, not added' ($s4.Status -eq 'failed')
```

- [ ] **Step 2: 실패를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String 'Test-PluginInstalled|Set-MarketplaceAutoUpdate|^PASS=' | Select-Object -First 3`
Expected: `Test-PluginInstalled`가 없다는 오류로 스크립트가 멈추고 `PASS=` 줄이 없다. 이 단계에서는 그것이 기대한 실패다.

- [ ] **Step 3: 함수 둘을 더한다**

`# The plugin cache and marketplace registry live outside settings.json` 주석 바로 앞에:

```powershell
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
    Copy-Item -LiteralPath $RegistryPath -Destination "$RegistryPath.bak" -Force
    [IO.File]::WriteAllText($RegistryPath, $json, [Text.UTF8Encoding]::new($false))
    return @{ Status = 'set'; Detail = "autoUpdate on for $Marketplace (backup at $RegistryPath.bak)" }
}
```

- [ ] **Step 4: Install-ClaudePlugins의 판정을 바꾼다**

`Install-ClaudePlugins` 안에서

```powershell
    $registry = Join-Path $env:USERPROFILE '.claude/plugins/known_marketplaces.json'
```
을

```powershell
    $pluginsDir = Join-Path $env:USERPROFILE '.claude/plugins'
    $installed  = Join-Path $pluginsDir 'installed_plugins.json'
    $registry   = Join-Path $pluginsDir 'known_marketplaces.json'
```
으로 바꾼다. 함수 본문 `try` 블록 안의 두 줄 주석

```powershell
            # Adding a marketplace that is already known is a success, not a
            # fault, so neither call's exit code is trusted. The registry is.
```
을

```powershell
            # Adding a marketplace that is already known is a success, not a
            # fault, so neither call's exit code is trusted. installed_plugins.json is.
```
으로 바꾼다. 그리고 `try { ... } catch { ... }` 뒤의

```powershell
        if ((Test-Path $registry) -and ([IO.File]::ReadAllText($registry) -match [regex]::Escape($pl.Marketplace))) {
            $results += @{ Id = $pl.Id; Status = 'installed'; Detail = "$($pl.Marketplace) registered in $registry" }
        } else {
            $results += @{ Id = $pl.Id; Status = 'failed'; Detail = $out.Trim() }
        }
```
을

```powershell
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
```
으로 바꾼다.

- [ ] **Step 5: CRLF 정규화 뒤 통과를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String '^FAIL|^PASS='`
Expected: FAIL은 기준선 다섯뿐.

- [ ] **Step 6: 커밋**

```powershell
git -C 'D:\projects\kw_install' add setup.ps1 tests/test_setup.ps1
git -C 'D:\projects\kw_install' commit -m "플러그인 설치 판정을 installed_plugins.json으로, 자동 갱신은 레지스트리에"
```

---

### Task 6: 옛 사본 제거 함수

**Files:**
- Modify: `D:\projects\kw_install\setup.ps1` — `$script:RetiredPlugins` 뒤에 상수, `Install-ClaudeSkills` 뒤에 함수
- Test: `D:\projects\kw_install\tests\test_setup.ps1` — `a second skill install reports them unchanged` 단언 뒤

**Interfaces:**
- Consumes: 없음.
- Produces: `$script:RetiredSkill = @{ Name = 'document-formats'; ReplacedBy = 'kw-doc-formats@kw-doc-formats' }` (해시테이블. spec의 「옛 사본 제거」 절이 이 모양을 정한다). `Remove-RetiredClaudeSkill -Name <string> -DestRoot <string> -BackupDir <string> [-WhatIfOnly]` → `@{ Status = 'absent'|'removed'|'kept'|'skipped'; Detail; Backup(removed일 때만) }`. Task 7이 8단계에서 부른다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`a second skill install reports them unchanged` 단언 뒤에:

```powershell
Write-Host '--- the old personal copy of document-formats is retired ---'
# The skill now arrives as a plugin. A personal copy left behind loads twice
# under the same name. The installer only ever wrote SKILL.md, so a folder
# holding anything else is somebody's work and stays.
Assert 'the retired skill names the plugin that replaces it' ($script:RetiredSkill.Name -eq 'document-formats' -and $script:RetiredSkill.ReplacedBy -eq 'kw-doc-formats@kw-doc-formats')
$oldRoot = Join-Path $Tmp 'old-skills'
$oldDir  = Join-Path $oldRoot 'document-formats'
$bakDir  = Join-Path $Tmp 'bak'
New-Item -ItemType Directory -Force -Path $oldDir | Out-Null
[IO.File]::WriteAllText((Join-Path $oldDir 'SKILL.md'), 'old body', [Text.UTF8Encoding]::new($false))
$r0 = Remove-RetiredClaudeSkill -Name 'document-formats' -DestRoot $oldRoot -BackupDir $bakDir -WhatIfOnly
Assert 'WhatIf reports the removal and leaves the folder' ($r0.Status -eq 'skipped' -and (Test-Path $oldDir) -and -not (Test-Path $bakDir))
$r1 = Remove-RetiredClaudeSkill -Name 'document-formats' -DestRoot $oldRoot -BackupDir $bakDir
Assert 'a folder holding only SKILL.md is removed' ($r1.Status -eq 'removed' -and -not (Test-Path $oldDir))
Assert 'and its SKILL.md is backed up first' ((Test-Path (Join-Path $bakDir 'document-formats.SKILL.md.bak')) -and ([IO.File]::ReadAllText((Join-Path $bakDir 'document-formats.SKILL.md.bak')) -eq 'old body'))
Assert 'the skills root itself is untouched' (Test-Path $oldRoot)
$r2 = Remove-RetiredClaudeSkill -Name 'document-formats' -DestRoot $oldRoot -BackupDir $bakDir
Assert 'a second run finds nothing and does nothing' ($r2.Status -eq 'absent')
New-Item -ItemType Directory -Force -Path $oldDir | Out-Null
[IO.File]::WriteAllText((Join-Path $oldDir 'SKILL.md'), 'old body', [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $oldDir 'notes.md'), 'mine', [Text.UTF8Encoding]::new($false))
$r3 = Remove-RetiredClaudeSkill -Name 'document-formats' -DestRoot $oldRoot -BackupDir $bakDir
Assert 'a folder with other files is kept' ($r3.Status -eq 'kept' -and (Test-Path (Join-Path $oldDir 'notes.md')))
$r4 = Remove-RetiredClaudeSkill -Name 'document-formats' -DestRoot (Join-Path $Tmp 'no-such-root') -BackupDir $bakDir
Assert 'no skills folder at all is absent, not an error' ($r4.Status -eq 'absent')
```

- [ ] **Step 2: 실패를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String 'retired skill|Remove-RetiredClaudeSkill|^PASS=' | Select-Object -First 3`
Expected: `the retired skill names the plugin` FAIL, 그 뒤 함수가 없어 멈추고 `PASS=` 줄이 없다.

- [ ] **Step 3: 상수를 더한다**

`$script:RetiredPlugins = @(...)` 닫는 괄호 뒤에:

```powershell

# The one skill this installer used to copy into the personal skills folder
# and now installs as a plugin instead. A personal copy left behind loads
# twice under the same name, so phase 8 removes it - but only once the
# replacing plugin is confirmed on disk, and only if the folder holds nothing
# but the SKILL.md this installer wrote. A single record, not a list: the
# other shipped skill (register-corp-certs) stays a personal skill by design.
# ReplacedBy names the plugin id phase 8 waits for.
$script:RetiredSkill = @{ Name = 'document-formats'; ReplacedBy = 'kw-doc-formats@kw-doc-formats' }
```

- [ ] **Step 4: 함수를 더한다**

`Install-ClaudeSkills` 함수의 닫는 `}` 뒤에:

```powershell

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
```

- [ ] **Step 5: CRLF 정규화 뒤 통과를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String '^FAIL|^PASS='`
Expected: FAIL은 기준선 다섯뿐.

- [ ] **Step 6: 커밋**

```powershell
git -C 'D:\projects\kw_install' add setup.ps1 tests/test_setup.ps1
git -C 'D:\projects\kw_install' commit -m "옛 document-formats 사본을 사본을 남기고 걷어내는 함수"
```

---

### Task 7: 8단계 배선, 스킬 폴더 삭제, 테스트 정리

**Files:**
- Modify: `D:\projects\kw_install\setup.ps1` — 8단계(`# --- 8. Plugins ---`, 2194~2210행), 머리말 30행, `.PARAMETER SkipPythonLibs`(71~73행), 파이썬 라이브러리 단계 주석(1883~1885행), `$IconDir` 정의 위 주석(159행 부근)
- Delete: `D:\projects\kw_install\skills\document-formats\SKILL.md`
- Modify: `D:\projects\kw_install\templates\personal-memory-ko.md` (33행)
- Test: `D:\projects\kw_install\tests\test_setup.ps1` — 536~548행, 638~649행, 새 검사

**Interfaces:**
- Consumes: Task 5의 `Install-ClaudePlugins` 결과 배열(`@{ Id; Status; Detail }`, `Status -eq 'installed'`가 설치 확인). Task 6의 `$script:RetiredSkill.Name`·`.ReplacedBy`와 `Remove-RetiredClaudeSkill -Name -DestRoot -BackupDir [-WhatIfOnly]` → `Status = 'absent'|'removed'|'kept'|'skipped'`. 기존 변수 `$IconDir`(`%LOCALAPPDATA%\kw-install`), `$SkipPlugins`, `$WhatIfOnly`, 함수 `Write-Ok`·`Write-Warn2`·`Write-Err2`·`Add-Warning`.
- Produces: 없음.

- [ ] **Step 1: 테스트를 먼저 고친다**

(가) `--- the guidance is reachable from the task that needs it ---` 블록에서 `$docFmt = ...`(540행), `$docDesc = ...`(541행), `foreach ($topic in @('pptx', 'PDF')) {...}` 세 줄(542~544행), 모두 다섯 줄을 지우고 위 주석 넉 줄(536~539행)을 아래 셋으로 바꾼다. `$mem = ...`부터 세 단언은 남기되 셋째 단언을 바꾼다.

```powershell
Write-Host '--- the guidance is reachable from the task that needs it ---'
# The pptx and PDF rules live in the kw-doc-formats plugin now; its own tests
# pin the description. What stays here is the memory block that points at it,
# because that block is the one thing loaded every session.
$mem = [IO.File]::ReadAllText($MemTemplate)
Assert 'the memory block names the pptx rule' ($mem -match 'pptx')
Assert 'the memory block names the PDF rule' ($mem -match 'PDF')
Assert 'and points at the plugin skill by its full name' ($mem -match 'kw-doc-formats:document-formats')
```

(나) `Write-Host '--- the shipped skills can actually run ---'`(638행)부터 `every python module a skill calls is in requirements.txt` 단언(648행)까지, 제목 줄과 주석 두 줄을 포함해 열한 줄을 지운다. 649행의 `pypdf, which a skill names` 단언은 `--- requirements.txt ---` 블록의 `markitdown asks for the format extras` 단언 뒤로 옮기며 아래로 바꾼다.

```powershell
# The document-formats skill (now the kw-doc-formats plugin) names pypdf for
# page selection and calls `python -m markitdown`. Both are pinned here by
# name because the skill lives in another repo and cannot be derived from.
Assert 'pypdf, which the document skill names, is in requirements.txt' ($reqNames -contains 'pypdf')
Assert 'markitdown, which the document skill calls, is in requirements.txt' ($reqNames -contains 'markitdown')
```

(다) `--- nothing points at a skill we do not ship ---` 블록 뒤에:

```powershell
Write-Host '--- phase 8 removes the old copy only after the plugin is confirmed ---'
$phase8 = $script:setupText.Substring((Find-Phase 'Claude Code plugins'))
$phase8 = $phase8.Substring(0, $phase8.IndexOf('# --- 9. Verify ---'))
Assert 'the retired skill is handled in the plugin phase' ($phase8 -match 'Remove-RetiredClaudeSkill')
Assert 'and only once the replacing plugin reports installed' ($phase8 -match 'ReplacedBy' -and $phase8 -match "Status -eq 'installed'")
Assert 'a dry run with plugins skipped does not promise a removal' ($phase8 -match '-not \$SkipPlugins')
Assert 'the document skill is no longer shipped as a folder' (-not (Test-Path (Join-Path $Root 'skills/document-formats')))
```

- [ ] **Step 2: 실패를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String '^FAIL'`
Expected: 기준선 다섯에 더해 `full name`, `handled in the plugin phase`, `only once`, `does not promise`, `no longer shipped` FAIL.

- [ ] **Step 3: 스킬 폴더를 지우고 템플릿을 고친다**

```powershell
git -C 'D:\projects\kw_install' rm -r -q skills/document-formats
```

`templates/personal-memory-ko.md` 33행을

```
두 가지 모두 방법은 `kw-doc-formats:document-formats` 스킬에 적혀 있습니다.
```
로 바꾼다.

- [ ] **Step 4: 8단계를 배선한다**

`# --- 8. Plugins ---`부터 `# --- 9. Verify ---` 앞 빈 줄까지를 아래로 바꾼다.

```powershell
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

```

`$IconDir` 정의 줄(159행) 바로 위 주석 끝에 한 줄을 더한다.

```powershell
# Also where phase 8 leaves the backup of a retired skill: the one folder this installer owns.
```

- [ ] **Step 5: 주석 셋을 고친다**

머리말 30행을

```
      8. Plugins       - claude plugin marketplace add + install; retire the old skill copy
```
로 바꾼다.

71~73행 `.PARAMETER SkipPythonLibs` 본문을

```
    Skip the requirements.txt install. The document-formats skill (installed
    as the kw-doc-formats plugin in phase 8) calls the tools listed there, so a
    machine set up this way cannot read .pptx, .docx or .pdf even though
    every other phase went green.
```
로 바꾼다.

1883~1885행의 주석을

```powershell
    # These are not optional decoration. The document-formats skill, which
    # phase 8 installs as the kw-doc-formats plugin, calls `python -m
    # markitdown` and names pypdf, so without this the machine goes green
    # everywhere and still cannot open a .pptx.
```
로 바꾼다.

- [ ] **Step 6: CRLF 정규화 뒤 통과를 본다**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\tests\test_setup.ps1 2>&1 | Select-String '^FAIL|^PASS='`
Expected: FAIL은 기준선 다섯뿐. PASS 수는 기준선 258에서 늘어난다.

- [ ] **Step 7: 커밋**

```powershell
git -C 'D:\projects\kw_install' add -A setup.ps1 tests/test_setup.ps1 templates/personal-memory-ko.md skills
git -C 'D:\projects\kw_install' commit -m "document-formats 폴더를 걷어내고 8단계에서 옛 사본을 정리"
```

---

### Task 8: 이 PC에서 드라이런으로 확인

**Files:** 없음

**Interfaces:**
- Consumes: Task 3의 퍼블릭 레포, Task 4~7의 `setup.ps1`.
- Produces: 없음.

사용자가 이 PC에서는 설치기를 **드라이런만** 하기로 정했다. 설치기를 통째로 돌리면 7단계가 이 PC의 `~/.claude/CLAUDE.md`에 AX 설치 블록을 넣고 `settings.json`을 auto 모드로 고치는데, 그 문안이 이 사용자의 전역 지침과 어긋나기 때문이다. 플러그인이 실제로 깔리고 옛 사본이 걷히고 자동 갱신이 켜지는지는 다른 PC에서 확인한다.

- [ ] **Step 0: 선행 조건을 확인한다**

```powershell
gh repo view KiwoomAX/KW-doc-formats --json visibility --jq .visibility
```
Expected: `PUBLIC`. 아니면 Task 3이 안 끝난 것이므로 멈춘다.

- [ ] **Step 1: 드라이런**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File D:\projects\kw_install\setup.ps1 -WhatIfOnly 2>&1 | Select-String 'kw-doc-formats|document-formats|Plugins|WhatIf'
```
Expected: `[WhatIf] would add KiwoomAX/KW-doc-formats and install kw-doc-formats@kw-doc-formats`, 이 PC에 옛 사본이 있으므로 `[WhatIf] would back up ...\document-formats\SKILL.md to ...\kw-install\document-formats.SKILL.md.bak and remove ...`, 마무리 요약의 `Plugins` 줄에 다섯 이름. 종료 코드 0.

- [ ] **Step 2: 드라이런이 아무것도 쓰지 않았는지 본다**

```powershell
Test-Path "$env:USERPROFILE\.claude\skills\document-formats"
Test-Path "$env:LOCALAPPDATA\kw-install\document-formats.SKILL.md.bak"
Select-String -Path "$env:USERPROFILE\.claude\CLAUDE.md" -Pattern 'BEGIN AX' -Quiet
```
Expected: `True`, `False`, `False`. 옛 사본은 남아 있고 사본 파일은 생기지 않았고 CLAUDE.md는 그대로다.

- [ ] **Step 3: 사용자에게 넘기는 확인**

이 항목은 서브에이전트의 통과 조건이 아니다. 최종 보고에 아래 둘을 적는다. 첫째, 다른 PC에서 설치기를 돌려 플러그인 단계에 `kw-doc-formats@kw-doc-formats: recorded in ...; autoUpdate on for kw-doc-formats`가 찍히고 옛 사본이 걷히는지 본다. 둘째, 그 PC에서 `claude`를 켜고 `/plugin` → Marketplaces → `kw-doc-formats`의 auto-update가 켜져 있는지 본다. 꺼져 있으면 spec 「자동 갱신」 절의 방법이 틀린 것이다.

---

### Task 9: 문서

**Files:**
- Modify: `D:\projects\kw_install\README.md` — 「설치 단계」 표의 플러그인 행(92행), 「이 PC에 생기는 변화」 첫 문단(105~108행), 「이 폴더에 있는 것」 표(139행), 「더 읽기」
- Modify: `D:\projects\kw_install\docs\CHANGES-ON-THIS-PC.md` — 「깔리는 플러그인」 표(35~40행), 「고쳐지는 설정 파일」 첫 문장(47행)과 `extraKnownMarketplaces` 행, 「놓이는 파일과 환경변수」 표의 스킬 행(82행)

**Interfaces:**
- Consumes: Task 4~7의 테스트 통과와 Task 8의 드라이런. 자동 갱신이 실제로 켜지는지는 다른 PC에서 확인하므로, 문서는 설치기가 켜려 한다는 사실만 적는다.
- Produces: 없음.

- [ ] **Step 1: README를 고친다**

「설치 단계」 표의 플러그인 행(92행)을

```
| 플러그인 | 마켓플레이스를 등록하고 플러그인 다섯을 설치한다. 이전 판이 복사해 둔 `document-formats` 스킬 사본은 그 플러그인이 확인된 뒤에 사본을 남기고 걷어낸다 |
```
로 바꾼다.

「이 PC에 생기는 변화」 첫 문단의 `사용자 파일은 넷을 고친다 — ... 그리고 curl 설정 파일인 \`.curlrc\` 다.`를

```
사용자 파일은 다섯을 고친다 — 클로드 코드의 `settings.json` 과 `CLAUDE.md`, 클로드 코드의 플러그인 레지스트리 `known_marketplaces.json`, 윈도우 터미널의 설정, 그리고 curl 설정 파일인 `.curlrc` 다. 앞의 넷은 통째로 덮지 않고 필요한 값만 고치며 고치기 전 사본을 `.bak` 으로 남긴다.
```
로 바꾸고, 이어지는 `앞의 셋은 통째로 덮지 않고 ... \`.bak\` 으로 남긴다.` 문장은 지운다. `.curlrc` 문장은 그대로 둔다.

「이 폴더에 있는 것」 표에서 `| \`skills\document-formats\` | 한글·구형 오피스·PDF를 다루는 사내 노하우다 |` 행을 지운다.

「더 읽기」 목록 끝에 한 줄을 더한다.

```
- `https://github.com/KiwoomAX/KW-doc-formats` — 문서 형식 처리 스킬(`kw-doc-formats:document-formats`)이 사는 플러그인 레포다. 이 설치기가 깔며, 스킬을 고칠 때는 그곳을 고친다.
```

- [ ] **Step 2: CHANGES-ON-THIS-PC.md를 고친다**

「깔리는 플러그인」 표(35~40행)에 행을 더한다.

```
| `kw-doc-formats` | 사내 문서 형식 처리 스킬 `kw-doc-formats:document-formats`다. 이전 판은 이 스킬을 개인 스킬 폴더에 복사했는데, 이제 플러그인으로 와서 고친 것이 자동 갱신으로 따라온다. 서드파티 마켓플레이스는 자동 갱신이 기본으로 꺼져 있어 설치기가 이 마켓플레이스에만 켠다 |
```

「고쳐지는 설정 파일」 첫 문장 `사용자 파일 세 개를 고친다. \`settings.json\`과 \`CLAUDE.md\`, 그리고 윈도우 터미널의 설정이다.`를

```
사용자 파일 네 개를 고친다. `settings.json`과 `CLAUDE.md`, 윈도우 터미널의 설정, 그리고 클로드 코드의 플러그인 레지스트리 `known_marketplaces.json`이다.
```
로 바꾼다. 같은 절의 `extraKnownMarketplaces`·`enabledPlugins` 행 비고 끝에 `. \`kw-doc-formats\` 항목에는 \`autoUpdate\`도 켠다. 사용자가 이미 값을 넣어 두었으면 그 값을 둔다`를 더한다. 절 끝에 문단을 하나 더한다.

```
플러그인 레지스트리 `%USERPROFILE%\.claude\plugins\known_marketplaces.json`은 `kw-doc-formats` 항목 하나만 고친다. `autoUpdate`를 켜는데, 이미 값이 있으면 건드리지 않고, 고치기 전 사본을 `known_marketplaces.json.bak`으로 남긴다. `/plugin` 화면의 자동 갱신 토글이 고치는 파일이 이것이다.
```

「놓이는 파일과 환경변수」 표의 스킬 행(82행)을

```
| 스킬 `register-corp-certs` | 개인 스킬 폴더 | 컨테이너 인증서를 다룬다. 이전 판이 함께 두던 `document-formats`는 플러그인으로 옮겨 갔고, 남은 사본은 `SKILL.md`를 `%LOCALAPPDATA%\kw-install\document-formats.SKILL.md.bak`으로 옮긴 뒤 지운다 |
```
로 바꾼다.

- [ ] **Step 3: 문서 검진**

읽기 전용 서브에이전트 하나를 띄워 `disciplined-coder:lens-grounding`과 `disciplined-coder:lens-readability`를 차례로 적용한다. 대상은 `README.md`와 `docs/CHANGES-ON-THIS-PC.md`이고, grounding의 출처는 `setup.ps1`과 spec이며, readability에 주는 목적은 "클로드 코드를 써 본 적 없는 새 PC 담당자가 이 문서만 보고 설치를 끝까지 마치고, 실패했을 때 무엇이 잘못됐는지 스스로 가려내게 한다"이다. 결과를 `docs/superpowers/reviews/2026-09-05-doc-formats-docs-check.md`에 적고 지적을 반영한다.
Expected: 기록 파일이 있고, 그 안의 지적마다 "고쳤다" 또는 "고치지 않은 이유"가 한 줄씩 있다.

- [ ] **Step 4: 커밋과 푸시**

```powershell
git -C 'D:\projects\kw_install' add README.md docs
git -C 'D:\projects\kw_install' commit -m "문서: document-formats가 플러그인으로 온다"
git -C 'D:\projects\kw_install' push origin main
```

<!-- spec-review: escalated -->
