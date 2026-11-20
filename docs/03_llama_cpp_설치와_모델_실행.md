# 03. llama.cpp 설치와 모델 실행

- 작업 날짜: 2026-11-19
- 대상 서버: `ai-server` (192.168.0.193), RTX 3090 24GB × 2, CUDA 13.5
- 전제: [02. GPU 드라이버 설치](02_GPU_드라이버_설치.md)까지 끝나 `nvidia-smi`와 `nvcc`가 동작해야 합니다.
- 작업 계정: 일반 사용자 `dyadmin` (관리자 명령만 `sudo`)

이 단계가 끝나면 서버에서 공개 AI 모델이 돌아가고, 사내 PC에서 API로 질문을 보낼 수 있게 됩니다.

> 용어: **llama.cpp**는 공개 AI 모델을 일반 서버에서 돌리는 프로그램입니다. **GGUF**는 그 프로그램이 읽는 모델 파일 형식입니다.
> **양자화(Q4_K_M 등)**는 모델을 압축해 GPU 메모리에 들어가게 만드는 기술입니다. 숫자가 작을수록 더 작고 빠르지만 답변 품질이 조금 떨어집니다.
> **빌드(조립)**는 소스 코드를 서버에서 실행 파일로 만드는 과정입니다. GPU 종류에 맞춰 직접 조립해야 가장 빠릅니다.

---

## 0. 작업 폴더 준비 (root로 한 번만)

```bash
sudo mkdir -p /data/llama.cpp /data/models
sudo chown -R dyadmin:dyadmin /data/llama.cpp /data/models
```
→ 빌드와 모델 폴더를 만들고 일반 사용자 소유로 바꿉니다. 이후 작업에 `sudo`가 필요 없어집니다.

---

## 1. llama.cpp 받아서 GPU용으로 빌드

```bash
git clone https://github.com/ggml-org/llama.cpp.git /data/llama.cpp
```
→ 공식 저장소의 소스 코드를 `/data/llama.cpp`로 복사해 옵니다.

```bash
cd /data/llama.cpp
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86
```
→ 조립 설계도를 만듭니다. `GGML_CUDA=ON`은 "GPU를 쓰게 만들라", `ARCHITECTURES=86`은 "RTX 3090 세대(Ampere, 계산 능력 8.6)에 맞춰라"는 뜻입니다.
화면에 `The CUDA compiler identification is NVIDIA 13.5`가 나오고 끝에 `Configuring done`, `Generating done`이 보이면 성공입니다.

```bash
cmake --build build --config Release -j 32
```
→ 실제 조립. `-j 32`는 32개를 동시에 조립하라는 뜻(64코어 서버라 여유). `[100%] Built target ...`으로 끝나면 성공. 약 10분.

**확인**
```bash
ls /data/llama.cpp/build/bin/ | grep -E "^llama-(server|cli|bench)$"
/data/llama.cpp/build/bin/llama-server --version
```
→ 세 파일이 보이고 버전이 찍히면 됩니다.

| 항목 | 결과 (2026-11-19) |
|---|---|
| llama.cpp 버전 | build 12536 (commit 7a4117eef), GCC 11.5로 빌드 |
| 빌드 시간 | 약 10분 (`-j 32`) |

> **실수 기록:** 첫 시도에서 `No CMAKE_CUDA_COMPILER could be found` 오류가 났습니다.
> 02단계에서 `nvcc` 경로를 `/etc/profile.d/cuda.sh`에 등록했는데, 그 **전에** 열어 둔 접속 세션이라 경로를 몰랐던 것입니다.
> 해결: 접속을 끊고 다시 로그인한 뒤 `rm -rf build`로 찌꺼기를 지우고 다시 실행. (또는 `source /etc/profile.d/cuda.sh`)

---

## 2. 모델 내려받기

**어떤 모델을 골랐나요?** Qwen3-32B, 4비트 양자화(Q4_K_M), 19.8GB.
- 한국어 포함 다국어 성능이 공개 모델 중 상위권, llama.cpp 지원이 안정적
- Apache 2.0 라이선스라 회사에서 쓰는 데 제약 없음
- GPU 한 장(24GB)에 들어가므로 다른 한 장은 문서 검색용 모델에 쓸 수 있음

```bash
wget -c -O /data/models/Qwen3-32B-Q4_K_M.gguf "https://huggingface.co/Qwen/Qwen3-32B-GGUF/resolve/main/Qwen3-32B-Q4_K_M.gguf"
```
→ Hugging Face(공개 모델 저장소)에서 모델 파일을 받습니다. `-c`는 끊겨도 같은 명령으로 이어받는 옵션.
**받는 동안 터미널 창을 닫으면 중단됩니다.** 끝나면 `saved [19762149024/19762149024]`가 나옵니다.

**확인**
```bash
ls -lh /data/models/
```
→ `19G` 크기 파일이 보여야 합니다.

| 항목 | 결과 (2026-11-19) |
|---|---|
| 내려받기 속도 | 약 10 MB/s, 총 35분 안팎 |
| 파일 크기 | 19,762,149,024 바이트 |

---

## 3. 첫 대화 테스트

**어떻게 하나요?** API 서버(`llama-server`)를 서버 안에서만 접근되게 잠깐 띄우고, 한국어 질문을 보내 답변과 속도를 봅니다.

```bash
/data/llama.cpp/build/bin/llama-server -m /data/models/Qwen3-32B-Q4_K_M.gguf -ngl 99 -c 8192 --jinja --host 127.0.0.1 --port 8080
```
→ 모델을 GPU에 올리고 8080번 문에서 기다립니다. `-ngl 99`: 모델 전체를 GPU에 / `-c 8192`: 한 번에 기억하는 대화 길이 / `--jinja`: 이 모델의 대화 형식 사용 / `127.0.0.1`: 서버 안에서만 접근.
`model loaded`, `listening on ...`이 보이면 준비 완료. 다른 터미널에서 질문을 보냅니다.

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json"   -d '{"messages":[{"role":"user","content":"RAID 5와 RAID 10의 차이를 세 문장으로 설명해 줘."}],"max_tokens":300,"chat_template_kwargs":{"enable_thinking":false}}'
```
→ OpenAI와 같은 형식으로 질문을 보냅니다. `enable_thinking: false`는 Qwen3의 "생각 과정 출력"을 끄는 옵션(짧은 답을 원할 때).

**결과 (2026-11-19)**

| 항목 | 값 |
|---|---|
| 모델 적재 시간 | 5초 (방금 받은 파일이라 메모리에 남아 있던 덕. 재부팅 후 첫 적재는 HDD에서 읽어 2~3분) |
| GPU 메모리 | 두 장에 나뉘어 각 10.9GB / 10.8GB 사용 (llama.cpp 기본 동작: 층을 반씩 나눔) |
| 질문 처리 속도 | 592 토큰/초 |
| 답변 생성 속도 | 39.5 토큰/초 (한국어 기준 초당 약 20~25글자, 읽는 속도보다 빠름) |
| 답변 품질 | RAID 5/10 설명이 정확하고 문장이 자연스러움 |

> **실수 기록:** 테스트 서버를 내리려고 `pkill -f llama-server`를 썼다가 SSH 접속이 끊겼습니다.
> `-f`는 "명령줄에 그 단어가 들어간 모든 프로세스"를 죽이는데, 그 명령을 보낸 접속 세션 자신도 해당됐기 때문입니다.
> 프로그램 이름이 정확히 일치할 때만 죽이는 `pkill -x llama-server`를 써야 합니다.

---

## 4. API 서버 자동 시작 등록과 사내망 개방

**왜 하나요?** 서버가 재부팅되어도 사람이 손대지 않고 AI 서버가 다시 뜨게 하고, 사내 PC에서 접근할 수 있게 합니다.
사내망 안이라도 아무나 못 쓰게 간단한 접근 열쇠(API 키)를 둡니다.

### 4-1. API 키 만들기 (root)
```bash
tr -dc A-Za-z0-9 </dev/urandom | head -c 32 > /data/llama-api.key; echo >> /data/llama-api.key
chown dyadmin:dyadmin /data/llama-api.key; chmod 600 /data/llama-api.key
```
→ 무작위 32글자 열쇠를 만들어 서비스 계정만 읽을 수 있게 둡니다. 사내 PC 프로그램에 이 값을 넣어 씁니다. 열쇠 값은 문서에 적지 않습니다.

### 4-2. 서비스 등록 파일 (root)
```bash
cat > /etc/systemd/system/llama-server.service <<'UNIT'
[Unit]
Description=사내 AI 비서 - llama.cpp API 서버 (Qwen3-32B)
After=network-online.target
Wants=network-online.target

[Service]
User=dyadmin
Group=dyadmin
WorkingDirectory=/data/llama.cpp
ExecStart=/data/llama.cpp/build/bin/llama-server -m /data/models/Qwen3-32B-Q4_K_M.gguf -ngl 99 -c 8192 --jinja --host 0.0.0.0 --port 8080 --api-key-file /data/llama-api.key
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
```
→ "서버가 켜지면 dyadmin 계정으로 이 명령을 실행하고, 죽으면 5초 뒤 다시 띄워라"는 등록 파일. `0.0.0.0`은 사내망 어디서든 접근 허용.

> **2026-11-20 변경:** 대시보드 자료 조회(도구 호출)를 붙이자 8192로는 부족해 `-c 32768`로 늘렸습니다([05 문서 6절](05_대시보드_채팅_연동.md) 참고).
> ```bash
> sudo sed -i 's/-c 8192/-c 32768/' /etc/systemd/system/llama-server.service
> sudo systemctl daemon-reload && sudo systemctl restart llama-server
> ```
> 재시작 후 로그에 `n_slots = 4, n_ctx_slot = 32768`이 찍혔습니다. 동시에 4명까지 각자 32768 토큰 길이의 대화를 할 수 있다는 뜻입니다.
> GPU 메모리는 장당 약 1.7GB 늘어 7~7.7GB가 되었습니다(이 시점 GPU는 4장).

```bash
systemctl daemon-reload
systemctl enable --now llama-server
```
→ 등록 파일을 읽게 하고(`daemon-reload`), 자동 시작을 켜면서 지금 바로 실행(`enable --now`).

### 4-3. SELinux 분류 규칙 (root) — 처음엔 실행이 거부됨
처음 `enable --now`를 하면 `Failed at step EXEC ... Permission denied` (status=203)로 실패합니다.
`/data`는 새로 만든 디스크라 그 안의 파일에 SELinux 꼬리표가 없고(`unlabeled_t`), 서비스 관리자는 "실행 프로그램(bin_t)" 꼬리표가 없는 파일을 띄우지 않습니다.
SELinux를 끄지 않고 규칙만 추가합니다.

```bash
dnf -y install policycoreutils-python-utils
semanage fcontext -a -t bin_t "/data/llama.cpp/build/bin(/.*)?"
restorecon -R /data/llama.cpp/build/bin
systemctl restart llama-server
```
→ 규칙 도구 설치 → "이 폴더의 파일은 실행 프로그램"이라는 규칙 등록 → 실제 파일에 꼬리표 적용 → 재시작.
llama.cpp를 다시 빌드해도 규칙이 남아 있어 `restorecon`만 다시 하면 됩니다.

### 4-4. 방화벽 (root)
```bash
firewall-cmd --permanent --add-port=8080/tcp
firewall-cmd --reload
```
→ 사내망에서 8080번 문으로 들어오게 허용. 서버 자체가 사내망에만 있으므로 외부에는 열리지 않습니다.

**확인 (서버에서)**
```bash
systemctl is-active llama-server && systemctl is-enabled llama-server
journalctl -u llama-server -n 5 -o cat
```
→ `active`, `enabled`, 로그에 `model loaded`, `listening on http://0.0.0.0:8080`.

**확인 (사내 PC에서)**
```powershell
curl.exe -s -o NUL -w "%{http_code}" http://192.168.0.193:8080/v1/models
```
→ 열쇠 없이 보내면 `401` (거부)이 정상.

```powershell
curl.exe -s -H "Authorization: Bearer 열쇠값" http://192.168.0.193:8080/v1/models
```
→ 열쇠를 붙이면 모델 목록이 옵니다. 대화는 `/v1/chat/completions`로 보냅니다(3절 예시와 같은 형식).

### 자주 쓰는 운영 명령
```bash
sudo systemctl status llama-server      # 상태 보기
sudo systemctl restart llama-server     # 다시 시작 (모델이나 옵션 바꾼 뒤)
sudo journalctl -u llama-server -f      # 실시간 로그
nvidia-smi                              # GPU 사용량
```

---

## 문제가 생기면

| 증상 | 원인과 해결 |
|---|---|
| `No CMAKE_CUDA_COMPILER could be found` | 이 세션이 `nvcc` 경로를 모름. 다시 로그인하거나 `source /etc/profile.d/cuda.sh` 후 `rm -rf build`하고 재실행 |
| 내려받기가 중간에 멈춤 | 같은 `wget -c` 명령을 다시 실행하면 이어받음 |
| 모델 파일이 `/data/models`에 없음 | 다른 창에서 받다가 창이 닫힌 경우. 위 명령을 다시 실행 |
| 서비스가 `status=203/EXEC`로 실패 | SELinux 꼬리표 문제. 4-3절의 `semanage`/`restorecon` 실행 |
| 재부팅 후 첫 응답이 2~3분 느림 | 20GB 모델을 HDD에서 읽는 시간. 이후 요청은 빠름 |
| 윈도우에서 한글 질문을 보내면 오류 | PowerShell이 한글을 CP949로 보내 JSON이 깨짐. 질문을 UTF-8 파일로 저장해 `--data-binary "@질문.json"`으로 보내거나, 프로그램(파이썬 등)에서 호출 |
| 사내 PC에서 `401` | 열쇠(API 키)를 안 붙였거나 틀림. `Authorization: Bearer 열쇠값` 헤더 확인 |
| 사내 PC에서 연결 자체가 안 됨 | 방화벽 4-4절 확인. `firewall-cmd --list-ports`에 `8080/tcp`가 있어야 함 |
| `pkill -f llama-server` 하니 접속이 끊김 | `-f`가 자기 세션까지 죽임. `pkill -x llama-server` 또는 `systemctl stop llama-server` 사용 |

---

## 3단계 완료 후 서버 상태 요약

| 항목 | 값 |
|---|---|
| llama.cpp | `/data/llama.cpp` (build 12536, CUDA 빌드) |
| 모델 | `/data/models/Qwen3-32B-Q4_K_M.gguf` (19.8GB, Apache 2.0) |
| API 서버 | `http://192.168.0.193:8080/v1/...`, OpenAI 호환, API 키 필요, 자동 시작 |
| GPU 사용 | 설치 당시 두 장에 각 약 11GB. 2026-11-20 확인 시 GPU 4장에 각 7~7.7GB(`-c 32768` 기준). 한 장에 몰려면 `--device CUDA0` 옵션 검토 |
| 대화 길이(`-c`) | 32768 토큰 (2026-11-20, 처음 8192에서 증설). 동시 대화 자리 4개 |
| 생성 속도 | 약 40 토큰/초 (1명 기준) |

다음 단계: [04. 점검과 문제 해결](04_점검과_문제해결.md), 그다음 문서 검색(RAG) 연결과 사내 PC용 채팅 화면.
