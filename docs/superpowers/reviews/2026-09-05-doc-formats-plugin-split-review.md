# spec 검진 기록 — document-formats 플러그인 분리 (2026-09-05)

검토 대상은 `docs/superpowers/specs/2026-09-05-doc-formats-plugin-split-design.md`다. 훅이 넘긴 경로가 `specs`이므로 spec으로 판정했다.

렌즈를 한 번씩만 돌렸다. 한 서브에이전트가 grounding과 consistency를 차례로 적용했고, adversarial은 자세가 반대라 따로 띄웠다. 렌즈 원본은 이 파일과 같은 이름의 폴더에 있다.

선행연구 렌즈(lens-prior-art)는 제안하지 않았다. 이 spec은 이미 하던 일(disciplined-coder와 같은 꼴의 플러그인 레포)을 같은 방식으로 하나 더 만드는 것이라 발동 기준에 걸리지 않는다.

## 합친 목록

근거를 열어 확인한 뒤 남긴 것이다. 괄호는 잡은 렌즈다. 둘 이상이 함께 잡은 것은 그렇게 적었다.

| 번호 | 지적 | 렌즈 | 확인 결과 |
|---|---|---|---|
| 1 | 옛 사본 삭제(7단계)가 플러그인 설치(8단계)보다 먼저 놓여, 설치가 실패하면 문서 스킬이 하나도 없는 PC가 된다 | adversarial | setup.ps1 단계 순서와 맞다 |
| 2 | 삭제 조건이 `-SkipSkills` 하나라 `-SkipPlugins`로 돌리면 사본만 지워진다 | adversarial | 1번과 같은 뿌리다 |
| 3 | `-SkipSkills`로 돌린 PC는 사본이 남은 채 플러그인이 깔려 이중 적재가 된다 | adversarial | 1번과 같은 뿌리다 |
| 4 | `at least one skill calls a python module` 단언도 실패하는데 걷어낼 대상에 없다 | adversarial·grounding 둘 다 | test_setup.ps1 646행에 있다 |
| 5 | 설치 성공 판정이 `known_marketplaces.json` 원문을 대소문자 무시로 대조해, repo 줄 `KiwoomAX/KW-doc-formats`가 마켓플레이스 이름 `kw-doc-formats`에 걸린다. install이 실패해도 add만 되면 통과한다 | adversarial | PowerShell `-match`는 기본이 대소문자 무시다. 1350행 판정이 그렇다 |
| 6 | 목적에 적은 "플러그인 자동 갱신"은 서드파티 마켓플레이스에서 기본이 꺼져 있어 설계만으로는 성립하지 않는다 | adversarial | 공식 문서 확인. "Third-party and local development marketplaces have auto-update disabled by default." 설치기가 넣은 두 마켓플레이스에도 `autoUpdate`가 없다 |
| 7 | 사본을 남기지 않고 지운다. 설치기가 고치는 다른 파일은 모두 `.bak`을 남긴다 | adversarial | settings.json·CLAUDE.md는 `.bak`을 남긴다 |
| 8 | 퍼블릭 공개의 근거 칸에 무엇이 공개되는지가 없다 | adversarial | 표의 근거 칸이 clone 편의만 적고 있다 |
| 9 | `$script:RetiredSkills` 목록은 둘째 항목을 가질 길이 없다 | adversarial | 같은 문서가 register-corp-certs를 안 옮긴다고 못박는다 |
| 10 | `$script:Plugins` 위 주석의 '넷 중 셋, 마켓플레이스 둘'이 고칠 곳에 없다 | adversarial·grounding 둘 다 | setup.ps1 232~238행 |
| 11 | 파이썬 라이브러리 단계 주석(1883행 'installed in phase 6')이 고칠 곳에 없다 | grounding | 맞다 |
| 12 | CHANGES-ON-THIS-PC.md의 플러그인 표에 새 행을 더한다는 지시가 없다 | grounding | 표가 네 행이다 |
| 13 | 호출 이름을 `kw-doc-formats:document-formats`로 정하고서 개인 기억 템플릿은 맨 이름으로 둔다 | consistency | 결정 표와 문서 절이 어긋난다 |
| 14 | 두 레포에 각각 적히는 이름이 같은지 보는 검사가 없다 | consistency | 맞다. 레포를 넘는 검사는 둘 수 없다 |
| 15 | README가 담을 것이 구조 절과 남는 위험 절에 다르게 적혀 있다 | consistency | 맞다 |
| 16 | 순서 절에 테스트를 돌리는 걸음이 없다 | consistency | 맞다 |
| 17 | 옛 사본 제거가 결정 표에 없다 | consistency | 맞다 |
| 18 | README가 정본을 가리키면서 라이브러리 목록을 복제한다 | consistency | 맞다. grounding도 그 목록의 셋은 스킬이 부르지 않는다고 짚었다 |
| 19 | 엑셀 규칙 추가는 목적 밖이다 | consistency | 사용자가 이 작업에 함께 넣으라고 한 것이다. 문서에 그 사실을 적는다 |

## 상충과 공백

렌즈 사이의 상충은 없었다. 1·2·3번은 한 뿌리(삭제와 설치의 순서)에서 나온 셋이라 하나로 합쳐 고친다.

렌즈가 남긴 확인거리 가운데 두 개는 발견으로 올리지 않았지만 처리한다. 개인 기억 템플릿이 접두사 없는 이름으로 플러그인 스킬에 닿는지는 13번을 고치면서 이름을 전체 이름으로 바꿔 없앤다. `Install-ClaudePlugins`의 `skipped` 가지에 경고가 없는 것은 설치기 쪽 줄이라 이 spec 밖이다.

아무도 안 본 렌즈는 없다. 셋 다 문서 전체를 읽었다.
