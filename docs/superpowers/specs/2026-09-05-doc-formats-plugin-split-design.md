# document-formats 스킬의 플러그인 분리 설계 (2026-09-05)

`document-formats` 스킬을 kw_install에서 떼어 별개 플러그인 레포로 옮기고, kw_install은 그 플러그인을 설치하는 쪽으로 바꾼다.

## 목적

스킬을 고칠 때 설치기를 건드리지 않게 하고, 이미 깔린 PC가 스킬 갱신을 플러그인 자동 갱신으로 받게 한다. 지금은 설치기가 스킬 파일을 개인 스킬 폴더로 복사하므로, 스킬을 고치면 설치기를 다시 돌려야 한다.

자동 갱신은 저절로 켜지지 않는다. 공식 문서가 "서드파티 마켓플레이스는 자동 갱신이 기본으로 꺼져 있다"고 적고 있고, 설치기가 넣은 두 마켓플레이스에도 그 값이 없다. 그래서 설치기가 이 마켓플레이스에 한해 자동 갱신을 켠다. 방법은 아래 「자동 갱신」 절에 있다.

이 작업에는 사용자가 함께 넣으라고 한 스킬 본문 수정 하나가 묶여 있다. 엑셀을 만들 때의 글자 크기 규칙이다. 분리 목적과는 별개지만 옮기는 파일이 같아 이 회차에 같이 한다.

## 결정한 것

| 항목 | 결정 | 근거 |
|---|---|---|
| 옮기는 것 | `skills/document-formats/` 하나 | `register-corp-certs`는 도커 훅이 가리키는 인증서 지침이라 설치기에 남긴다 |
| 레포 | `KiwoomAX/KW-doc-formats`, 퍼블릭 | 사용자 결정. 퍼블릭이어야 새 PC가 인증 없이 clone한다. 공개되는 본문은 지금도 퍼블릭 레포 `chshin84/kw_install`에 올라 있는 것과 같다. 사내 파일 관행(cp949, 표준 테마)을 말하지만 인증서 구성이나 내부 주소는 없다 |
| 플러그인·마켓플레이스 이름 | `kw-doc-formats` (소문자) | `claude plugin validate`가 대문자를 경고와 함께 통과시키지만 Claude.ai 마켓플레이스 동기화는 kebab-case를 요구한다고 알린다. 레포 이름만 대문자를 살린다 |
| 스킬 호출 이름 | `kw-doc-formats:document-formats` | 플러그인 스킬은 `플러그인:스킬`로 불린다. 이 이름을 가리키는 곳은 모두 이 전체 이름을 쓴다 |
| 마켓플레이스 위치 | 플러그인 레포 안 | disciplined-coder와 같은 꼴이다. 레포 루트가 곧 플러그인이고 `source: "./"`로 가리킨다 |
| 버전 | 비운다 | 커밋 SHA 기반 자동 갱신을 유지한다. validate의 version 경고는 수용한다 |
| 자동 갱신 | 설치기가 이 마켓플레이스에 켠다 | 서드파티 마켓플레이스는 기본이 꺼져 있다. 켜지 않으면 목적이 성립하지 않는다 |
| 파이썬 라이브러리와 Poppler | 설치기에 남긴다 | 플러그인은 프로그램을 깔 수 없다 |
| 옛 사본 제거 | 플러그인 설치가 확인된 뒤에만, 사본을 남기고 지운다 | 안 지우면 같은 스킬이 두 벌 실린다. 설치 확인 전에 지우면 설치 실패 시 스킬이 없는 PC가 된다. 설치기가 고치는 다른 파일과 같이 `.bak`을 남긴다 |
| 설치 성공 판정 | `installed_plugins.json`에 플러그인 id가 있는지로 본다 | 지금 판정은 `known_marketplaces.json` 원문에 마켓플레이스 이름이 있는지를 대소문자 무시로 대조한다. 이 플러그인은 repo 줄 `KiwoomAX/KW-doc-formats`가 이름 `kw-doc-formats`에 걸려, `plugin install`이 실패해도 `marketplace add`만 되면 통과한다. 옛 사본 삭제가 이 판정에 걸려 있으므로 오탐 하나가 곧 스킬 없는 PC다 |
| 엑셀 규칙 추가 | 스킬 본문에 절 하나를 더한다 | 사용자 요청 둘. 셀 글자 크기를 따로 바꾸지 말고 11로 둔다. 글꼴 이름은 다루지 않는다. 그리고 사용자가 엑셀로 열 CSV는 BOM 있는 UTF-8(`utf-8-sig`)로 쓰고, 표가 목적이면 CSV 대신 `.xlsx`로 낸다. 한국어 엑셀은 BOM 없는 UTF-8 CSV를 cp949로 열어 한글이 깨지며, `PYTHONUTF8=1`을 세우면 파이썬의 기본 쓰기 인코딩이 UTF-8이 되어 이 일이 더 잦아진다 |

## 새 레포의 구조

```
.claude-plugin/plugin.json        name, description. version 없음
.claude-plugin/marketplace.json   name kw-doc-formats, owner, plugins[0] = { name, source "./", description }
skills/document-formats/SKILL.md  kw_install의 것을 그대로 옮기고 엑셀 절을 더한다
README.md                         아래 「README」 절이 정한다
tests/test_plugin.ps1             아래 계약을 검사한다
.gitignore
```

`plugins[0].description`은 `plugin.json`의 `description`과 글자 그대로 같게 둔다. 두 파일이 같은 문안을 들고 있으므로 테스트가 일치를 확인한다.

### README

담는 것은 넷이다. 무엇이 들어 있는지, 어떻게 까는지, 무엇을 전제하는지, 그리고 그 전제가 어디서 오는지다. 전제는 "kw_install이 깔아 주는 파이썬 3.12 라이브러리와 Poppler"라고 적고 kw_install의 `requirements.txt`를 가리킨다. 라이브러리 이름을 나열하지 않는다. 그 목록의 정본은 `requirements.txt` 하나다. 스킬이 새 모듈을 쓰게 되면 kw_install의 `requirements.txt`를 손으로 맞춰야 한다는 사실도 여기 적는다.

### 테스트

`tests/test_plugin.ps1`은 pwsh 7 스크립트이고 kw_install의 `tests/test_setup.ps1`과 같은 꼴이다. 자기 안에 `Assert` 함수를 두고 PASS와 FAIL 수를 센다. 실행은 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test_plugin.ps1`이다.

- `claude plugin validate ./`가 통과한다. 경고는 허용하고 오류만 실패로 본다.
- `plugin.json`의 `name`과 `marketplace.json`의 `name`과 `plugins[0].name`이 모두 `kw-doc-formats`다. kw_install이 이 문자열을 적어 두므로 여기서 고정한다.
- `plugin.json`의 `description`과 `marketplace.json`의 `plugins[0].description`이 같다.
- `skills/*/SKILL.md`의 frontmatter `name`이 폴더 이름과 같다.
- `SKILL.md`의 description이 `pptx`와 `PDF`를 언급한다. kw_install에 있던 검사를 스킬과 함께 옮긴다.
- `SKILL.md`가 엑셀 글자 크기 11 규칙과 CSV `utf-8-sig` 규칙을 담는다.

## kw_install의 변경

### 플러그인 목록

`$script:Plugins`에 한 줄을 더한다. Id `kw-doc-formats@kw-doc-formats`, Marketplace `kw-doc-formats`, Repo `KiwoomAX/KW-doc-formats`, AutoUpdate `$true`. 이 한 줄이 `settings.json`의 `extraKnownMarketplaces`·`enabledPlugins` 선언과 CLI 설치를 둘 다 만든다. 플러그인은 넷에서 다섯이 되고 마켓플레이스는 둘에서 셋이 된다. 목록 바로 위 주석이 '넷 중 셋'과 '마켓플레이스 넷에서 둘로'라는 수를 들고 있으므로 그 주석도 고친다.

### 자동 갱신

`AutoUpdate`가 참인 행은 두 곳에 값이 들어간다. `Merge-ClaudeSettings`가 `extraKnownMarketplaces` 항목에 `autoUpdate = $true`를 넣고, `Install-ClaudePlugins`가 설치를 확인한 뒤 `~/.claude/plugins/known_marketplaces.json`의 그 마켓플레이스 항목에 같은 키를 넣는다. 뒤의 파일이 `/plugin` 화면의 자동 갱신 토글이 고치는 파일이다. 사용자가 이미 값을 넣어 둔 항목은 덮지 않고, 고치기 전 `.bak`을 남기며, 새로 쓴 파일을 다시 파싱해 유효할 때만 원래 자리에 놓는다. 이 규칙은 disciplined-coder의 `domain-plugin` 스킬 「사용자 설정 파일을 고칠 때 지킬 것」이 정한다.

### 설치 성공 판정

`Install-ClaudePlugins`의 판정을 바꾼다. `~/.claude/plugins/installed_plugins.json`을 JSON으로 읽어 `plugins` 아래에 그 플러그인 id 키가 있으면 `installed`다. 파일이 없거나 키가 없으면 `failed`이고 CLI 출력을 Detail에 담는다. 다섯 플러그인이 모두 같은 판정을 받는다. 이 플러그인만 따로 판정하지 않는다.

### 스킬 폴더

`skills/document-formats/`를 레포에서 지운다. `Install-ClaudeSkills`는 그대로 두고 `register-corp-certs`만 복사하게 된다.

### 옛 사본 제거

이전 판 설치기가 `~/.claude/skills/document-formats/SKILL.md`를 써 둔 PC가 있다. 그대로 두면 개인 스킬과 플러그인 스킬이 같은 이름으로 둘 다 실린다.

- `$script:RetiredSkill = @{ Name = 'document-formats'; ReplacedBy = 'kw-doc-formats@kw-doc-formats' }`를 상수 하나로 둔다. 목록으로 두지 않는다. 옮기는 스킬은 하나이고 남는 하나는 옮기지 않기로 정했으므로 둘째 항목이 생길 길이 없다. `ReplacedBy`는 8단계가 어느 플러그인의 설치 확인을 기다릴지 말해 준다. plan 검진에서 문자열 하나로는 그 정보를 담을 수 없다고 짚여 이렇게 바꿨다.
- 새 함수 `Remove-RetiredClaudeSkill -Name -DestRoot -BackupDir -WhatIfOnly`가 그 폴더를 개인 스킬 폴더에서 찾는다.
- 폴더 안에 `SKILL.md` 하나만 있으면, 그 파일을 `%LOCALAPPDATA%\kw-install\document-formats.SKILL.md.bak`으로 복사한 뒤 폴더째 지운다. 설치기가 쓴 것이 그 파일 하나뿐이다.
- 다른 파일이 하나라도 있으면 사용자 것이 섞였다고 보고 지우지 않는다. 경고를 내고 `Add-Warning`으로 마무리 화면에 남긴다.
- 폴더가 없으면 아무것도 하지 않는다. 두 번 돌려도 같다.
- `-WhatIfOnly`에서는 지울 것을 보고만 하고 지우지 않는다.
- 부르는 자리는 플러그인 단계(8단계)다. `kw-doc-formats@kw-doc-formats`의 결과가 `installed`일 때만 부른다. `-SkipPlugins`이거나 설치가 확인되지 않으면 부르지 않고, 옛 사본이 있으면 "플러그인이 확인되지 않아 옛 사본을 남긴다"고 경고한다. `-SkipSkills`는 이 함수와 무관하다.

### 테스트

- `$WantPlugins`에 새 id를 더한다.
- `at least one skill calls a python module`과 `every python module a skill calls is in requirements.txt` 두 단언과 그 앞의 모듈 추출을 걷어낸다. 스킬이 레포 밖으로 나가므로 레포 안에서 도출할 수 없다. `requirements.txt` 자체의 검사(`pypdf`가 있는가, `markitdown`이 형식 확장을 달았는가)는 남긴다.
- "스킬 description이 pptx와 PDF를 언급하는가" 검사는 새 레포로 옮긴다. 개인 기억 템플릿이 `pptx`·`PDF`·`document-formats`를 가리키는가 하는 검사는 남긴다.
- `Remove-RetiredClaudeSkill`을 검사한다. `SKILL.md`만 있는 폴더는 사본이 생기고 지워지며, 다른 파일이 섞인 폴더는 남고, WhatIf는 아무것도 지우지 않고, 두 번째 실행은 아무것도 하지 않는다.
- `Merge-ClaudeSettings`가 `AutoUpdate` 행의 마켓플레이스 항목에만 `autoUpdate`를 넣는지 검사한다.
- `known_marketplaces.json`을 고치는 함수를 검사한다. 키가 없는 항목에는 넣고, 사용자가 넣어 둔 값은 덮지 않고, `.bak`이 남는다.

### 문서

고칠 자리는 이름으로 부른다.

- `README.md`의 「이 폴더에 있는 것」 표에서 `skills\document-formats\` 행을 빼고, 「설치 단계」 표의 플러그인 단계 설명에서 '플러그인 넷'을 '다섯'으로 고친다.
- `docs/CHANGES-ON-THIS-PC.md`의 「깔리는 플러그인」 표에 `kw-doc-formats` 행을 더하고, 「놓이는 파일과 환경변수」 표의 스킬 행에서 `document-formats`를 뺀다.
- `setup.ps1`의 머리말 주석(`.PARAMETER SkipPythonLibs` 설명), 파이썬 라이브러리 단계 주석("installed in phase 6"), `$script:Plugins` 위 주석을 고친다.
- `templates/personal-memory-ko.md`의 "`document-formats` 스킬에 적혀 있습니다"를 "`kw-doc-formats:document-formats` 스킬에 적혀 있습니다"로 고친다. 호출 이름을 한 가지로 쓴다.

## 순서

1. 새 레포를 만든다. `gh repo create KiwoomAX/KW-doc-formats --public`으로 만들고 로컬은 `D:\projects\KW-doc-formats`에 둔다.
2. 새 레포의 테스트를 먼저 쓰고 실패를 본 뒤 파일을 채워 통과시킨다. `claude plugin validate ./`도 여기서 돈다. 푸시한다.
3. kw_install의 테스트를 먼저 고쳐 실패를 본 뒤 `setup.ps1`을 고쳐 통과시킨다. 설치기의 플러그인 단계가 새 레포를 clone하므로 2보다 앞설 수 없다.
4. 이 PC에서 설치기를 `-WhatIfOnly`로 돌려 플러그인 다섯이 보이는지 확인한다.
5. 실제 실행은 이 PC에서 하지 않는다. 사용자가 그렇게 정했다. 설치기를 통째로 돌리면 7단계가 이 PC의 `CLAUDE.md`에 AX 설치 블록을 넣고 `settings.json`을 auto 모드로 고치는데, 그 문안이 이 사용자의 전역 지침과 어긋나기 때문이다. 플러그인이 실제로 깔리고 옛 사본이 걷히고 자동 갱신이 켜지는지는 다른 PC에서 설치기를 돌려 본다. 그때 `/plugin` 화면의 마켓플레이스 탭에서 `kw-doc-formats`의 자동 갱신이 켜져 있지 않으면 「자동 갱신」 절의 방법이 틀린 것이다.
6. kw_install의 문서를 고치고 커밋한다.

## 남는 위험

- 스킬이 부르는 파이썬 모듈과 설치기의 `requirements.txt`가 서로 다른 레포에 놓여 자동 대조가 사라진다. 스킬에 새 모듈을 쓰게 되면 설치기의 `requirements.txt`를 손으로 맞춰야 한다.
- 이름 `kw-doc-formats`가 두 레포에 각각 적힌다. 새 레포의 테스트가 자기 이름을 고정하고 kw_install의 테스트가 자기 목록을 고정하지만, 둘이 같은지는 레포를 넘는 검사가 없어 사람이 본다.

## 하지 않는 것

- `register-corp-certs`는 옮기지 않는다.
- 개인 기억 블록을 플러그인의 SessionStart 훅으로 옮기지 않는다.
- 파이썬 라이브러리 설치를 플러그인 쪽으로 옮기지 않는다.
- 기존 `chshin-tools` 마켓플레이스에는 등록하지 않는다.
- `Install-ClaudePlugins`의 `skipped` 가지에 경고가 없는 것은 이 설계 밖이다. 검진에서 짚였으나 설치기의 기존 줄이라 따로 다룬다.

<!-- spec-review: passed -->
