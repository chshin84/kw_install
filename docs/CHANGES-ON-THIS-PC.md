# 이 PC에 들어오는 것과 바뀌는 설정

`setup.ps1`이 이 PC에 실제로 무엇을 넣고 무엇을 고치는지를 한자리에 모았다. 설치 담당자가
읽어야 하는 것은 `README.md`이고, 이 문서는 무엇이 들어오는지 확인하려는 사람과 설치기를
고칠 사람을 위한 것이다.

비고에는 **설명이 필요한 것만** 적었다. 이름만으로 무엇을 하는지 드러나는 항목은 비고를 비워
둔다. 빈 칸은 적다 만 것이 아니라 적을 것이 없다는 뜻이다.

## 깔리는 프로그램

| 프로그램 | winget ID | 비고 |
|---|---|---|
| 파이썬 3.12 (판 고정) | `Python.Python.3.12` | 아래 문서 라이브러리가 **이 판 안에** 깔린다. 다른 판이 PATH 앞에 서면 라이브러리가 안 보이는데도 설치는 성공으로 보고돼 조용히 실패한다. 그래서 판을 고정한다 |
| git | `Git.Git` | 플러그인 마켓플레이스를 내려받는 수단이다. 없으면 플러그인 단계가 통째로 건너뛰어진다. Git Bash도 함께 깔린다 |
| Node.js LTS | `OpenJS.NodeJS.LTS` | 클로드 코드가 도는 런타임이다. 노드는 윈도 인증서 저장소도 `certifi`도 안 보고 `NODE_EXTRA_CA_CERTS`만 보므로, 마지막 검증이 파이썬과 별개로 노드에게 한 번 더 묻는다. 이 물음만 실패해도 종료 코드 3으로 끝난다 |
| Poppler | `oschwartz10612.Poppler` | 클로드는 PDF 쪽을 **그림으로 그려야** 볼 수 있고 그 도구가 `pdftoppm`이다. 없으면 `pdftoppm is not installed`로 거절하고, 남는 길은 글자만 뽑는 것뿐이라 표와 배치가 사라진다. 표가 중요한 문서에서 정확히 그 부분을 잃는다 |

## 깔리는 파이썬 라이브러리

`requirements.txt`가 정본이고 설치기는 그 파일을 읽는다.

| 라이브러리 | 되는 일 | 비고 |
|---|---|---|
| `openpyxl` | 엑셀(.xlsx)을 읽고 쓴다 | |
| `python-docx` | 워드(.docx)를 읽고 쓴다 | |
| `python-pptx` | PPT를 만들고 고친다 | |
| `pypdf` | PDF에서 글자를 뽑는다 | 쪽별로 뽑아 **어느 쪽을 봐야 하는지 고르는** 데 쓴다 |
| `markitdown[docx,pptx,pdf,xlsx,xls]` | 여러 형식의 내용을 읽어 낸다 | 확장 하나가 형식 하나에 대응한다. 안 붙이면 그 형식을 못 읽는다. `[all]`은 음성 인식과 외부 서비스까지 끌고 와서 쓰지 않는다 |
| `chardet` | CSV가 어떤 인코딩인지 알아낸다 | 사내 CSV는 대개 cp949인데 UTF-8로 읽으면 글자가 전부 깨진다. 사용자 눈에는 "클로드가 잘못했다"로 보인다. 판별만 하고 파일은 고치지 않아 부작용이 없다 |
| `pandas<3.0` | 표 데이터를 계산하고 정리한다 | 판을 3.0 미만으로 묶는다. 한국거래소 데이터를 가져오는 `pykrx`가 그 아래를 요구해서, 제약을 풀면 `pykrx`가 깨진다 |

## 깔리는 플러그인

| 플러그인 | 비고 |
|---|---|
| `document-skills` | 문서 업무의 핵심이다. 이 설치기의 목적에 정면으로 맞는다 |
| `superpowers` | 복잡한 일회성 업무를 끌고 갈 때 실제로 도움이 되는 것이 확인됐다 |
| `playwright` | 브라우저 자동화다. 사내 웹에서 자료를 받아 오는 경우에 쓴다 |
| `frontend-design` | 대시보드 수요 때문이다. 비개발자가 자기 결과물을 남에게 보여 주는 가장 깔끔한 수단이 웹 화면이고, 사내에서 본부별 대시보드로 공유되고 있다 |
| `kw-doc-formats` | 사내 문서 형식 처리 스킬 `kw-doc-formats:document-formats`다. 이전 판은 이 스킬을 개인 스킬 폴더에 복사했는데, 이제 플러그인으로 와서 고친 것이 자동 갱신으로 따라온다. 서드파티 마켓플레이스는 자동 갱신이 기본으로 꺼져 있어 설치기가 이 마켓플레이스에만 켠다 |

목록의 정본은 `setup.ps1`의 `$script:Plugins`다. `settings.json`의 선언과 CLI 설치가 모두 그
한 곳에서 생성되므로 둘이 어긋날 수 없다. 어느 마켓플레이스에서 오는지도 거기 적혀 있다.

## 고쳐지는 설정 파일

사용자 파일 네 개를 고친다. `settings.json`과 `CLAUDE.md`, 윈도우 터미널의 설정, 그리고
클로드 코드의 플러그인 레지스트리 `known_marketplaces.json`이다. 프로젝트 설정과 회사 관리
정책은 별개 파일이라 건드리지 않는다.

`CLAUDE.md`는 통째로 덮지 않는다. `# BEGIN AX 설치`와 `# END AX 설치` 사이만 바꾸고 그 바깥에
사용자가 쓴 것은 그대로 둔다. 고치기 전에 `CLAUDE.md.bak`으로 사본을 뜬다. 관리 영역 안을 손으로
고치면 다음 실행에서 덮이므로, 남길 내용은 마커 바깥에 적어야 한다.

윈도우 터미널 설정은 `profiles.defaults` 아래 세 값만 바꾼다. 글꼴은 굴림체(`GulimChe`) 10이고,
글자 가장자리를 다듬지 않게 한다. 파일에 이미 있던 프로필·단축키·색 구성은 그대로 옮겨 담고,
고치기 전 사본을 `settings.json.bak`으로 남긴다. `defaults`에 넣기 때문에 나중에 WSL이나
Git Bash 프로필이 생겨도 같은 글꼴로 열린다.

아래 표는 클로드 코드의 `settings.json` 쪽이다.

| 설정 키 | 바뀌는 값 | 비고 |
|---|---|---|
| `permissions.defaultMode` | `auto`로 지정 | 클로드 코드를 켤 때마다 auto 모드로 시작하게 하는 한 줄이다. **권한 쪽에서 바꾸는 것은 이것뿐이다** |
| `permissions.allow`·`ask`·`deny` | 그대로 둠 | 거기 있는 것은 사용자나 회사 정책의 것이다. 이전 판은 넓은 `allow`를 넣고 `deny`를 지웠는데 전부 걷어냈다 |
| `env.CLAUDE_CODE_USE_POWERSHELL_TOOL` | `1`로 지정 | PowerShell 도구를 켠다 |
| `env.CLAUDE_CODE_POWERSHELL_RESPECT_EXECUTION_POLICY` | 삭제 | 클로드가 자기 프로세스 범위의 우회를 쓰게 둬서 서명되지 않은 `.ps1`이 막히지 않게 한다 |
| `defaultShell` | `powershell`로 지정 | 대화창에서 `!`로 직접 치는 명령이 파워셸로 간다 |
| `disableSkillShellExecution` | `false`로 명시 | 스킬과 슬래시 명령 안의 인라인 셸이 실제로 실행되게 한다. 기본값이 바뀌어도 흔들리지 않도록 값을 적어 둔다 |
| `hooks.PreToolUse` | Bash 도구와 PowerShell 도구용 훅 등록 | 컨테이너는 이 PC의 인증서를 물려받지 않는다. `docker run`을 치는 그 순간이 마운트를 넣을 마지막 기회라 그때 알려 준다. 번들이 없으면 등록하지 않는다 |
| `extraKnownMarketplaces`·`enabledPlugins` | 플러그인 선언 추가 | CLI 설치가 막힌 PC에서도 첫 실행 때 들어오도록 남기는 선언이다. `kw-doc-formats` 항목에는 `autoUpdate`도 켠다. 사용자가 이미 값을 넣어 두었으면 그 값을 둔다 |

플러그인 레지스트리 `%USERPROFILE%\.claude\plugins\known_marketplaces.json`은 `kw-doc-formats`
항목 하나만 고친다. `autoUpdate`를 켜는데, 이미 값이 있으면 건드리지 않고, 고치기 전 사본을
`known_marketplaces.json.bak`으로 남긴다. `/plugin` 화면의 자동 갱신 토글이 고치는 파일이
이것이다.

## 놓이는 파일과 환경변수

| 항목 | 놓이는 자리 | 비고 |
|---|---|---|
| CA 번들 | `%LOCALAPPDATA%\corp-certs\ca-bundle.pem` | 사내 검사 장비를 지나는 HTTPS가 성립하려면 필요하다. 가로채기가 없으면 만들지 않는다 |
| `REQUESTS_CA_BUNDLE`·`SSL_CERT_FILE`·`PIP_CERT`·`NODE_EXTRA_CA_CERTS` | 사용자 환경변수 | 파이썬·노드·pip가 각자 다른 변수를 본다. 하나만 세우면 나머지가 실패한다 |
| curl 설정 한 줄 | `%USERPROFILE%\.curlrc` | curl은 저 변수들을 보지 않는다. 사내 루트에 폐기 확인 주소가 없어 curl이 확인을 못 하고 연결을 끊으므로, 확인이 불가능할 때만 넘어가라는 줄을 넣는다. 남의 설정이 이미 있으면 뒤에 덧붙인다. 이 파일만은 고치기 전 사본을 남기지 않는다 |
| PATH 추가 | `%USERPROFILE%\.local\bin` | `claude`를 이름만으로 실행할 수 있게 한다 |
| PATH 맨 앞 | 고정한 파이썬 3.12 폴더와 그 아래 `Scripts` | 새 윈도우의 사용자 PATH에는 진짜 파이썬이 아닌 마이크로소프트 스토어 껍데기가 들어 있다. 그것이 먼저 대답하면 라이브러리를 넣은 3.12가 안 잡히므로 앞으로 옮긴다. 이미 앞에 있으면 건드리지 않는다 |
| 바로 가기 `PowerShell 7` | 시작 메뉴와 바탕화면 | `wt.exe -p "PowerShell"`을 연다. 아이콘은 함께 실리는 `claudecode-color.png`를 구운 것이고, 그 그림이나 굽는 기능이 없을 때만 `pwsh.exe`의 것으로 물러선다. 윈도우 11은 스크립트가 작업 표시줄에 고정하는 것을 막아 두었으므로, 그 한 번은 바로 가기를 오른쪽 클릭해서 직접 한다 |
| 스킬 `register-corp-certs` | 개인 스킬 폴더 | 컨테이너 인증서를 다룬다. 이전 판이 함께 두던 `document-formats`는 플러그인으로 옮겨 갔고, 남은 사본은 `SKILL.md`를 `%LOCALAPPDATA%\kw-install\document-formats.SKILL.md.bak`으로 옮긴 뒤 지운다 |
| 바로 가기 아이콘 파일 | `%LOCALAPPDATA%\kw-install` | `claudecode-color.png`를 구운 `.ico`가 여기 놓인다. 파일 이름에 그림 내용의 해시가 붙는데, 윈도우가 아이콘을 경로 단위로 기억해 같은 이름이면 옛 그림을 계속 그리기 때문이다 |
| 도커 훅 스크립트 | `%LOCALAPPDATA%\corp-certs` | 위 `hooks.PreToolUse`가 이 파일을 부른다 |
| 개인 기억 블록 | `%USERPROFILE%\.claude\CLAUDE.md` | 매 세션 실리는 지침이다. 이 PC에서 실제로 겪은 문제 — 발표자료 글자 윤곽선과 긴 PDF 읽기 — 를 스킬을 열지 않아도 보이게 둔다. 마커 사이만 바꾸고 이전 판은 `CLAUDE.md.bak`에 남긴다 |
