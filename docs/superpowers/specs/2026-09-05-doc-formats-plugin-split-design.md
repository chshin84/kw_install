# document-formats 스킬의 플러그인 분리 설계 (2026-09-05)

`document-formats` 스킬을 kw_install에서 떼어 별개 플러그인 레포로 옮기고, kw_install은 그 플러그인을 설치하는 쪽으로 바꾼다.

## 목적

스킬을 고칠 때 설치기를 건드리지 않게 하고, 이미 깔린 PC가 스킬 갱신을 플러그인 자동 갱신으로 받게 한다. 지금은 설치기가 스킬 파일을 개인 스킬 폴더로 복사하므로, 스킬을 고치면 설치기를 다시 돌려야 한다.

## 결정한 것

| 항목 | 결정 | 근거 |
|---|---|---|
| 옮기는 것 | `skills/document-formats/` 하나 | `register-corp-certs`는 도커 훅이 가리키는 인증서 지침이라 설치기에 남긴다 |
| 레포 | `KiwoomAX/KW-doc-formats`, 퍼블릭 | 사용자 결정. 퍼블릭이어야 새 PC가 인증 없이 clone한다 |
| 플러그인·마켓플레이스 이름 | `kw-doc-formats` (소문자) | `claude plugin validate`가 대문자를 경고와 함께 통과시키지만 Claude.ai 마켓플레이스 동기화는 kebab-case를 요구한다고 알린다. 레포 이름만 대문자를 살린다 |
| 스킬 호출 이름 | `kw-doc-formats:document-formats` | 플러그인 스킬은 `플러그인:스킬`로 불린다 |
| 마켓플레이스 위치 | 플러그인 레포 안 | disciplined-coder와 같은 꼴이다. 레포 루트가 곧 플러그인이고 `source: "./"`로 가리킨다 |
| 버전 | 비운다 | 커밋 SHA 기반 자동 갱신을 유지한다. validate의 version 경고는 수용한다 |
| 파이썬 라이브러리와 Poppler | 설치기에 남긴다 | 플러그인은 프로그램을 깔 수 없다 |
| 엑셀 규칙 추가 | 스킬 본문에 절 하나를 더한다 | 사용자 요청. 셀 글자 크기를 따로 바꾸지 말고 11로 둔다 |

## 새 레포의 구조

```
.claude-plugin/plugin.json        name, description. version 없음
.claude-plugin/marketplace.json   name kw-doc-formats, owner, plugins[0] = { name, source "./", description }
skills/document-formats/SKILL.md  kw_install의 것을 그대로 옮기고 엑셀 절을 더한다
README.md                         무엇이 들어 있는지, 어느 라이브러리를 전제하는지, 어떻게 까는지
tests/test_plugin.ps1             아래 계약을 검사한다
.gitignore
```

`plugins[0].description`은 `plugin.json`의 `description`과 글자 그대로 같게 둔다. 두 파일이 같은 문안을 들고 있으므로 테스트가 일치를 확인한다.

README는 이 스킬이 전제하는 것을 적는다. 파이썬 3.12 안의 `markitdown`·`pypdf`·`chardet`·`pandas`·`openpyxl`·`python-docx`·`python-pptx`, 그리고 `pdftoppm`(Poppler)이다. 목록의 정본은 kw_install의 `requirements.txt`이며 README는 그곳을 가리킨다.

### 새 레포의 테스트 계약

- `claude plugin validate ./`가 통과한다. 경고는 허용하고 오류만 실패로 본다.
- `plugin.json`의 `description`과 `marketplace.json`의 `plugins[0].description`이 같다.
- `skills/*/SKILL.md`의 frontmatter `name`이 폴더 이름과 같다.
- `SKILL.md`의 description이 `pptx`와 `PDF`를 언급한다. kw_install에 있던 검사를 스킬과 함께 옮긴다. 스킬은 description이 맞을 때만 열리므로, 발표자료를 만들 때와 PDF를 읽을 때 닿아야 한다.
- `SKILL.md`가 엑셀 글자 크기 11 규칙을 담는다.

## kw_install의 변경

### 플러그인 목록

`$script:Plugins`에 한 줄을 더한다. Id `kw-doc-formats@kw-doc-formats`, Marketplace `kw-doc-formats`, Repo `KiwoomAX/KW-doc-formats`. 이 한 줄이 `settings.json`의 `extraKnownMarketplaces`·`enabledPlugins` 선언과 CLI 설치를 둘 다 만든다. 플러그인은 넷에서 다섯이 되고 마켓플레이스는 둘에서 셋이 된다.

### 스킬 폴더

`skills/document-formats/`를 레포에서 지운다. `Install-ClaudeSkills`는 그대로 두고 `register-corp-certs`만 복사하게 된다.

### 옛 사본 제거

이전 판 설치기가 `~/.claude/skills/document-formats/SKILL.md`를 써 둔 PC가 있다. 그대로 두면 개인 스킬과 플러그인 스킬이 같은 이름으로 둘 다 실린다. 설치기가 마켓플레이스 중복을 없앨 때 피했던 상황과 같다.

- `$script:RetiredSkills = @('document-formats')`를 둔다. `$script:RetiredPlugins`와 같은 자리, 같은 역할이다.
- 새 함수 `Remove-RetiredClaudeSkills -DestRoot -WhatIfOnly`가 목록의 각 폴더를 개인 스킬 폴더에서 찾는다.
- 폴더 안에 `SKILL.md` 하나만 있으면 폴더째 지운다. 설치기가 쓴 것이 그 파일 하나뿐이다.
- 다른 파일이 하나라도 있으면 사용자 것이 섞였다고 보고 지우지 않는다. 경고를 내고 `Add-Warning`으로 마무리 화면에 남긴다.
- 폴더가 없으면 아무것도 하지 않는다. 두 번 돌려도 같다.
- `-WhatIfOnly`에서는 지울 것을 보고만 하고 지우지 않는다.
- 클로드 연동 단계에서 `Install-ClaudeSkills` 직후에 부른다. `-SkipSkills`이면 부르지 않는다.

### 테스트

- `$WantPlugins`에 새 id를 더한다.
- "스킬이 부르는 파이썬 모듈이 requirements.txt에 있는가" 검사를 걷어낸다. 스킬이 레포 밖으로 나가므로 레포 안에서 도출할 수 없다. `requirements.txt` 자체의 검사(`pypdf`가 있는가, `markitdown`이 형식 확장을 달았는가)는 남긴다.
- "스킬 description이 pptx와 PDF를 언급하는가" 검사는 새 레포로 옮긴다. 개인 기억 템플릿이 `document-formats`를 가리키는가 하는 검사는 남긴다.
- `Remove-RetiredClaudeSkills`를 검사한다. `SKILL.md`만 있는 폴더는 지워지고, 다른 파일이 섞인 폴더는 남고, WhatIf는 아무것도 지우지 않고, 두 번째 실행은 아무것도 하지 않는다.

### 문서

`README.md`와 `docs/CHANGES-ON-THIS-PC.md`, `setup.ps1`의 머리말 주석에서 `document-formats`를 설치기가 복사한다고 적힌 곳을 플러그인으로 온다고 고친다. 플러그인 수와 폴더 표도 맞춘다. 개인 기억 템플릿의 "`document-formats` 스킬에 적혀 있습니다"는 그대로 둔다. 플러그인 스킬도 그 이름으로 찾힌다.

## 순서

1. 새 레포를 만들고 푸시한다. `gh repo create KiwoomAX/KW-doc-formats --public`으로 만든다.
2. kw_install을 고친다. 설치기의 플러그인 단계가 그 레포를 clone하므로 순서를 바꿀 수 없다.
3. 이 PC에서 설치기를 `-WhatIfOnly`로 돌려 플러그인 다섯이 보이는지 확인한 뒤, 실제로 돌려 플러그인이 깔리고 옛 사본이 걷히는지 본다.

## 남는 위험

스킬이 부르는 파이썬 모듈과 설치기의 `requirements.txt`가 서로 다른 레포에 놓여 자동 대조가 사라진다. 스킬에 새 모듈을 쓰게 되면 설치기의 `requirements.txt`를 손으로 맞춰야 한다. 새 레포의 README가 이 사실을 적는다.

## 하지 않는 것

- `register-corp-certs`는 옮기지 않는다.
- 개인 기억 블록을 플러그인의 SessionStart 훅으로 옮기지 않는다.
- 파이썬 라이브러리 설치를 플러그인 쪽으로 옮기지 않는다.
- 기존 `chshin-tools` 마켓플레이스에는 등록하지 않는다.
