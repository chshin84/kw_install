# plan 검진 기록 — document-formats 플러그인 분리 (2026-09-05)

검토 대상은 `docs/superpowers/plans/2026-09-05-doc-formats-plugin-split.md`다. 훅이 넘긴 경로가 `plans`이므로 plan으로 판정했다. plan이므로 선행연구 렌즈는 제안하지 않는다.

렌즈를 한 번씩만 돌렸다. 한 서브에이전트가 grounding과 consistency를 차례로 적용했고, adversarial은 따로 띄웠다. 렌즈 원본은 이 파일과 같은 이름의 폴더에 있다.

## 합친 목록

근거를 열어 확인한 뒤 남긴 것이다. 렌즈 둘 이상이 함께 잡은 것은 그렇게 적었다.

| 번호 | 지적 | 렌즈 | 확인 결과 |
|---|---|---|---|
| 1 | CRLF 정규화 스니펫이 ASCII 인코딩으로 써서 비ASCII를 `?`로 바꾼다. 그 뒤 ASCII 테스트는 잡을 것이 없다 | adversarial | `[Text.ASCIIEncoding]`의 동작이 그렇다 |
| 2 | Task 9가 Skip 스위치 없이 설치기 전체를 이 PC에서 돌린다. 이 PC의 `CLAUDE.md`에는 AX 블록이 없어 새로 들어가고, 그 블록의 "저는 개발자가 아닙니다"는 이 사용자의 전역 지침과 어긋난다 | adversarial | `grep -c "BEGIN AX" ~/.claude/CLAUDE.md`가 0이다. 7단계(설정·기억 병합)는 건너뛰는 스위치가 없다 |
| 3 | Task 3이 이 PC에 손으로 깔아 두어 Task 9의 판정이 설치기가 아니라 Task 3의 흔적을 본다 | adversarial | `installed_plugins.json` 키는 남는다 |
| 4 | Task 9 Step 4의 `/plugin` 화면 확인은 서브에이전트가 할 수 없다 | adversarial | 맞다 |
| 5 | `-SkipPlugins -WhatIfOnly`에서 드라이런이 옛 사본 삭제를 예고하지만 실제 실행은 지우지 않는다 | adversarial·consistency 둘 다 | 조건 `$WhatIfOnly -or $replaced`가 그렇다 |
| 6 | `Merge-ClaudeSettings`가 `autoUpdate`를 매번 무조건 true로 넣는다. 레지스트리 쪽만 사용자 값을 지킨다 | adversarial | 맞다 |
| 7 | Task 3 선행 조건이 Interfaces에 없고 Task 7에는 Interfaces가 없다 | adversarial | 맞다 |
| 8 | `$script:RetiredSkill`이 spec은 문자열, plan은 해시테이블이다. 문자열이면 8단계가 try/catch 밖에서 죽는다 | adversarial·consistency 둘 다 | 맞다 |
| 9 | `Set-MarketplaceAutoUpdate -WhatIfOnly`를 부르는 자리가 없다 | adversarial·consistency 둘 다 | `Install-ClaudePlugins`는 WhatIf에서 continue한다 |
| 10 | README와 엑셀 절 블록이 세 백틱 안에 세 백틱을 넣어 도중에 닫힌다 | adversarial | 맞다 |
| 11 | validate의 'error' 낱말 단언은 exit code 단언과 겹치고 도구 표기와 무관하다 | adversarial | disciplined-coder에서 실측: 출력에 'error'가 없고 exit 0 |
| 12 | 레지스트리를 통째로 다시 쓰는데 CLI도 세션마다 그 파일을 고친다. 쓰기 뒤 항목 수 대조가 없다 | adversarial | 이 PC의 여덟 항목 중 여섯이 같은 `lastUpdated`다 |
| 13 | `Test-PluginInstalled`가 `installed_plugins.json`의 형식 하나에 다섯 플러그인 판정을 건다 | adversarial | 형식이 다르면 다섯이 `failed`로 크게 찍히고 옛 사본은 남는다. 조용한 실패가 아니라 고치지 않는다 |
| 14 | Task 1 Step 3 Expected가 스크립트 중단과 FAIL 목록을 구분하지 않는다 | adversarial | 맞다 |
| 15 | Task 5의 주석 자리가 '함수 위'가 아니라 함수 본문 안 두 줄이다 | grounding | 1342~1343행 |
| 16 | README 플러그인 행은 92행, CHANGES 플러그인 표는 35~40행이다 | grounding | 맞다 |
| 17 | Task 4 Step 2 Expected에 `the replacements are in`이 빠졌다 | grounding | 269행 |
| 18 | Task 7 (나)의 제목과 주석 두 줄 처분이 없고, (가)는 넉 줄이 아니라 다섯 줄이다 | grounding | 맞다 |
| 19 | `known_marketplaces.json`을 새로 고치면서 CHANGES '세 개'와 README '넷' 문장을 안 고친다 | consistency | 맞다 |
| 20 | spec은 실행(5) 뒤 문서(6)인데 plan은 뒤집혔다 | consistency | 맞다 |
| 21 | Task 8 Step 3의 문서 검진이 렌즈와 통과 기준 없이 미정이다 | consistency | 맞다 |
| 22 | 매니페스트 description이 엑셀에 '글꼴·글자 크기'라 적어 글꼴을 다루는 것처럼 읽힌다 | consistency | 맞다 |

## 상충과 공백

렌즈 사이의 상충은 없다. 5·8·9는 둘이 함께 잡았다. 13번은 근거는 맞지만 고치지 않는다. 형식이 달라지면 다섯 플러그인이 모두 `failed`로 마무리 화면에 남고 옛 사본은 지워지지 않으므로, 조용히 잘못되는 길이 아니다.

adversarial이 남긴 확인거리 가운데 `gh` 조직 정책은 재 봤다. `KiwoomAX`는 멤버의 퍼블릭 레포 생성을 허용한다.

## 처분

2번만 `🔴`다. 이 PC에서 설치기를 통째로 돌리면 사용자의 `CLAUDE.md`와 `settings.json`이 바뀌고, 그것은 사용자가 정할 일이다. 나머지는 전부 고친다.
