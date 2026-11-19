# local-llm: 사내 전용 AI 비서

회사 내부 서버에서 공개 AI 모델을 돌려, 자료가 밖으로 나가지 않는 사내 AI 비서를 만드는 프로젝트입니다.

## 구성

| 폴더 | 내용 |
|---|---|
| [docs/](docs/README.md) | 서버 설치 가이드와 현황 기록. **여기부터 읽으세요.** |
| [tools/collect-docs/](tools/collect-docs/README.md) | 직원 PC의 문서를 NAS로 모으는 윈도우용 수집 도구 |
| `src/local_llm/` | 로컬 LLM 실행 엔진, OpenAI 호환 API 서버, 터미널 채팅 (작성 예정) |

## 진행 순서

1. 직원 PC 문서를 NAS로 모으기 → `tools/collect-docs/`
2. 서버 준비와 GPU 드라이버 설치 → `docs/01`, `docs/02`
3. 모델 실행과 첫 대화 → `docs/03`
4. 문서 검색(RAG) 연결, 서비스 단계 전환 → 추후

작업 규칙은 [CLAUDE.md](CLAUDE.md)에 있습니다.
