# 작업 규칙 (Claude Code가 세션마다 읽는 파일)

## 대화 방식
- 모든 설명, 계획, 진행 과정은 **한국어**로 쓴다. 작업 목록(Task) 제목도 한국어로 쓴다.
- 사용자는 전문 개발자가 아니다. 전문 용어는 처음 나올 때 쉬운 말로 풀어 쓰고, 비유를 활용한다.
- 파일을 만들거나 고치기 전에 **무엇을 어떻게 바꿀지 먼저 설명하고 진행 여부를 묻는다.**
  사용자가 **"수정 진행"**이라고 답한 뒤에만 실제로 파일을 만들거나 수정한다.
  (커밋·푸시는 설명한 작업의 마무리로 함께 수행한다.)
- 코드 안의 주석과 문서도 비개발자가 읽을 수 있게 쓴다.

## 프로젝트 배경
- 회사: 하드웨어, 서버, 스토리지 납품·설치·유지보수 업체. 직원 약 10명, 20명을 넘지 않음. 동시 사용자는 5명 정도.
- 조직: 관리부, 기술지원부, 영업부. **기술지원부부터 적용**하고 영업부·관리부는 추후 검토.
  관리부는 계정 정보와 계좌 정보가 많아 별도의 주의가 필요하다.
- 목표: 사내 전용 AI 비서. 외부로 자료가 나가지 않아야 한다.
- 자료 위치: 대부분 직원 PC에 흩어져 있고, 많은 자료가 Synology NAS에 있다. NAS로 모으는 것이 1차 과제.
- 대상 서버(회사 내부, 이름 `ai-server`): GIGABYTE G242-Z10, Rocky Linux 9.9(커널 5.14.0-741), AMD EPYC 7702 64코어(SMT 꺼짐), 메모리 125GB,
  **NVIDIA RTX 3090 24GB 2장**(GPU 슬롯 4개라 3장째 추가 가능), 시스템 NVMe 232GB + 7.3TB HDD(`/data`로 연결 완료: `models` `docs` `index`).
  사내망 주소 192.168.0.193. 클라우드 세션에서는 접속할 수 없고, 노트북에서 돌아가는 세션이 SSH로 작업한다
  (root는 노트북 키 전용, 일반 사용자 `dyadmin`은 비밀번호 + `sudo`).
- 서버에 설치된 것(2026-11-19 기준): NVIDIA 드라이버 nvidia-open 620.70.06(open-dkms), CUDA 13.5, llama.cpp(`/data/llama.cpp`, CUDA 빌드),
  모델 Qwen3-32B Q4_K_M(`/data/models`). `llama-server`가 systemd 서비스(`llama-server.service`)로 자동 시작되어
  `http://192.168.0.193:8080/v1/...`(OpenAI 호환, API 키는 서버의 `/data/llama-api.key`)로 응답한다. 생성 속도 약 40토큰/초.
  조사 기록은 `docs/00_서버_현황.md`, 실제 설치 절차와 결과는 `docs/01_`~`03_` 번호 문서, 전체 흐름 요약은 `docs/server-setup.md`.
- 이 저장소에서 작업하는 클라우드 세션은 공부와 준비용이다. 실제 실행은 회사 노트북과 서버에서 한다.
- `sooya85.synology.me` 주소는 이 프로젝트와 **무관**하다. 사용하거나 언급하지 않는다.

## 업무 사이트 (rnb-dashboard)
- 별도 저장소 `dynacache/rnb-dashboard` (비공개). 기술지원부가 쓰는 업무 사이트로, 사용자가 Claude Code로 만들었다.
- PHP + MariaDB, Synology NAS 웹 서버(`/volume1/web/dashboard`)에서 동작. 로그인·그룹 권한 체계 있음.
- 주요 테이블: tech_support(기술지원 건), tech_support_progress(진행 기록), contracts(유지보수 계약),
  customers(고객사), maintenance_monthly(월별 점검), part_requests(파트 구매 요청), business_project(영업 프로젝트),
  weekly_reports / 월간 보고서(NAS 스케줄러가 자동 생성), vendors, vehicles, 회의록, 공지.
- `api/` 폴더에 로그인 필요한 JSON 조회·입력 기능 85개. 외부용 API는 없음.
- DB 비밀번호는 `config.php`에만 있고 저장소에 올리지 않는다. AI 연동 시에도 같은 원칙(읽기 전용 계정, 설정 파일 분리)을 지킨다.
- 노트북에서는 운영 폴더가 `Y:` 드라이브(NAS `dashboard` 공유 폴더)로 연결되어 있고, 저장소 복사본은 `C:\work\rnb-dashboard`.
  `Y:`에서 고친 뒤 복사본에 복사해 커밋한다. 푸시는 사용자가 직접 한다.
- 2026-11-19 "AI 매니저" 연동 완료: 오른쪽 위 "매니저" 버튼 → 대화창(`chat.js`) → `api/chat_stream.php`가 AI 서버에 중계.
  AI 서버 주소·키는 `config.php`의 `LLM_API_URL`, `LLM_API_KEY`. 내용은 `docs/05_대시보드_채팅_연동.md`.

## 전체 계획 순서
1. ~~AI 서버에 두뇌 올리기~~ **완료(2026-11-19)**: llama.cpp + OpenAI 호환 API. Open WebUI는 대시보드 채팅창으로 대신해 생략.
2. 업무 사이트 DB 읽기 연동 + 주간·월간 보고서 글로 풀어 쓰기 (읽기 전용, 사이트 수정 거의 없음)
3. NAS 문서 검색 도우미 (`tools/collect-docs`로 모은 문서, 임베딩 + 벡터 저장소)
4. 사이트 안 "비서에게 묻기" 채팅창 **(완료)** + 입력 대신하기 (사람이 확인 버튼을 눌러야 저장, 미착수)

## 저장소 구성
- `src/local_llm/`: 로컬 LLM 실행 엔진, OpenAI 호환 API 서버, 터미널 채팅 (Python, uv로 관리)
- `tools/collect-docs/`: 직원 PC의 문서를 NAS로 모으는 윈도우용 수집 도구 (PowerShell)
- `docs/`: 서버 설치 기록(`00_`~`05_` 번호 문서), 전체 흐름 요약(`server-setup.md`), 학습 자료
- `scripts/`: 확인용 소형 스크립트 (`first_chat.py`: 모델 로드와 첫 대화 확인)

## 기술 선택
- 추론 엔진은 학습 단계에서 llama.cpp(GGUF), 서비스 단계에서 vLLM 전환을 검토한다.
- API는 OpenAI 호환 형식(`/v1/chat/completions`)을 유지한다.
- 한국어 문서 검색용 임베딩 모델은 다국어 지원 모델(bge-m3 등)을 쓴다.
