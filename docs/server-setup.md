# 서버 설치 가이드 (Rocky Linux + NVIDIA GPU)

사내 AI 비서 1단계 "두뇌 켜기"를 위한 순서입니다.
노트북에서 돌아가는 Claude Code 세션이 이 문서를 보고 서버(192.168.0.193)에 SSH로 접속해 단계별로 진행합니다.
각 단계에는 **왜 필요한지**, **성공하면 어떻게 보이는지**를 적어 두었습니다. 확인 기준을 통과하면 다음 단계로 넘어갑니다.

> **이 문서의 역할**: 전체 흐름을 한눈에 보는 요약본입니다. 실제 설치 절차는 노트북 세션이 서버에서
> 한 단계씩 진행하며 쓰는 번호 문서(`01_` ~ `04_`)를 따릅니다. 번호 문서가 아직 없는 단계(모델 받기,
> API 서버, 32B 비교, Open WebUI)는 이 문서를 참고합니다. 서버 조사 결과는 `00_서버_현황.md`에 있습니다.
>
> 조사로 확인된 사실: RTX 3090 24GB 2장, Rocky Linux 9.8, nouveau 드라이버가 올라가 있음(차단 필요),
> 7.3TB HDD는 `/data`로 연결해 모델·문서 보관용으로 씀. 아래 예시의 `models/` 대신 `/data/models`를 써도 됩니다.
>
> 이 문서의 모델 이름과 파일명은 작성 시점 기준 예시입니다. 더 새 모델이 나왔을 수 있으니,
> 내려받기 전에 Hugging Face 페이지에서 파일명을 한 번 확인합니다.

---

## 0단계. 접속과 기본 정보 확인

**왜**: 드라이버가 있는지, 디스크가 넉넉한지, 인터넷이 되는지에 따라 이후 단계가 달라집니다.

```bash
ssh 사용자명@192.168.0.193
```

```bash
cat /etc/os-release | grep -E "^(NAME|VERSION_ID)="; nproc; free -h | head -2
```
```bash
nvidia-smi
```
```bash
df -h / /home
```
```bash
python3 --version; curl -sI https://huggingface.co | head -1
```

**확인 기준**
- `VERSION_ID`가 8 또는 9로 시작 (Rocky 8/9). 아래 명령은 9 기준이며, 8이면 `rhel9`를 `rhel8`로 바꿉니다.
- `nvidia-smi`가 GPU 2~3장을 표로 보여 주면 **1단계를 건너뜁니다.** `command not found`이면 1단계로.
- 디스크 여유가 **100GB 이상**이면 넉넉합니다. (7B 약 5GB, 32B 약 20GB, 70B 약 40GB)
- `HTTP/2 200` 또는 `HTTP/1.1 200`이 나오면 인터넷으로 모델을 받을 수 있습니다. 안 되면 모델 파일을 다른 PC에서 받아 USB나 NAS로 옮깁니다.

---

## 1단계. NVIDIA 드라이버와 CUDA 설치 (nvidia-smi가 없을 때만)

**왜**: GPU는 드라이버 없이는 그냥 꽂혀 있는 부품입니다. CUDA는 프로그램이 GPU에 일을 시키는 통로입니다.

```bash
sudo dnf install -y epel-release dnf-plugins-core kernel-devel-$(uname -r) kernel-headers-$(uname -r) gcc make
```
```bash
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
```
```bash
sudo dnf clean all && sudo dnf -y module install nvidia-driver:latest-dkms
```
위 `module install`이 "모듈을 찾을 수 없음"으로 실패하면 (최신 저장소는 모듈 방식을 쓰지 않음) 대신:
```bash
sudo dnf -y install nvidia-driver-cuda kmod-nvidia-latest-dkms
```
```bash
sudo dnf -y install cuda-toolkit
```
```bash
sudo reboot
```

재부팅 후 다시 접속해서:
```bash
nvidia-smi
```
```bash
ls /usr/local/cuda/bin/nvcc && /usr/local/cuda/bin/nvcc --version | tail -1
```

**확인 기준**: `nvidia-smi` 표에 GPU가 모두 보이고 각각 `24576MiB` 근처의 메모리가 표시됩니다. `nvcc`가 버전을 출력합니다.

**막히면**
- Secure Boot가 켜져 있으면 드라이버 모듈이 로드되지 않습니다. BIOS에서 Secure Boot를 끕니다.
- `nouveau` 드라이버가 잡고 있으면 `lsmod | grep nouveau`로 확인하고, 설치 과정에서 자동으로 막히지 않았다면 `/etc/modprobe.d/blacklist-nouveau.conf`에 `blacklist nouveau`를 적고 `sudo dracut --force` 후 재부팅합니다.

---

## 2단계. 작업 도구 설치 (uv, git)

**왜**: `uv`는 파이썬과 필요한 부품을 한 번에 깔끔하게 설치해 주는 도구입니다. Rocky의 기본 파이썬(3.9)은 오래되어 그대로 쓰지 않고, uv가 3.12를 따로 설치합니다.

```bash
sudo dnf install -y git cmake gcc-c++
```
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh && source ~/.bashrc && uv --version
```

**확인 기준**: `uv 0.x.x`처럼 버전이 출력됩니다.

---

## 3단계. 프로젝트 받기와 GPU 모드로 설치

**왜**: 이 저장소에 모델 실행과 API 서버에 필요한 설정이 모여 있습니다. llama-cpp-python은 설치할 때 "GPU를 써라"는 옵션을 주고 빌드해야 GPU가 동작합니다. 빌드는 5~15분 걸립니다.

```bash
mkdir -p ~/work && cd ~/work && git clone -b claude/trusting-keller-btj51x https://github.com/dynacache/local_llm.git && cd local_llm
```
```bash
export PATH=/usr/local/cuda/bin:$PATH
CMAKE_ARGS="-DGGML_CUDA=on" uv sync --reinstall-package llama-cpp-python
```

**확인 기준**: 오류 없이 끝나고, 아래가 `True`를 출력합니다.
```bash
uv run python -c "import llama_cpp; print(llama_cpp.llama_supports_gpu_offload())"
```

**막히면**
- `nvcc not found`: `export PATH=/usr/local/cuda/bin:$PATH`를 다시 실행한 뒤 재시도합니다.
- 빌드가 메모리 부족으로 죽으면 `CMAKE_BUILD_PARALLEL_LEVEL=8`을 앞에 붙여 동시에 쓰는 코어 수를 줄입니다.

---

## 4단계. 첫 모델 받기 (7B, 약 5GB)

**왜**: 작고 빠른 모델로 전체 흐름이 되는지 먼저 확인합니다. 품질 비교는 6단계에서 합니다.

```bash
mkdir -p ~/work/local_llm/models && cd ~/work/local_llm
```
```bash
uv run hf download Qwen/Qwen2.5-7B-Instruct-GGUF qwen2.5-7b-instruct-q4_k_m.gguf --local-dir models
```
`hf` 명령이 없다고 나오면 예전 이름으로:
```bash
uv run huggingface-cli download Qwen/Qwen2.5-7B-Instruct-GGUF qwen2.5-7b-instruct-q4_k_m.gguf --local-dir models
```

**확인 기준**:
```bash
ls -lh models/
```
`qwen2.5-7b-instruct-q4_k_m.gguf`가 약 4.7GB로 보입니다.

---

## 5단계. 첫 대화 (파이썬 스크립트)

**왜**: 서버를 띄우기 전에, 모델이 GPU에 올라가고 한국어로 답하는지 가장 단순한 방법으로 확인합니다.

```bash
cd ~/work/local_llm && uv run python scripts/first_chat.py models/qwen2.5-7b-instruct-q4_k_m.gguf
```

**확인 기준**
- 화면에 `한국의 수도는 서울입니다` 같은 답이 나옵니다.
- 출력 중에 `offloaded 29/29 layers to GPU`처럼 **모든 층이 GPU에 올라갔다**는 줄이 보입니다. `0/29`이면 GPU 빌드가 안 된 것이니 3단계를 다시 합니다.
- 다른 터미널에서 `nvidia-smi`를 치면 GPU 메모리 사용량이 5GB 정도 올라가 있습니다.
- 답이 나오는 속도: 7B 기준 초당 50~100 토큰, 눈으로 따라 읽기 어려울 만큼 빠릅니다.

---

## 6단계. API 서버 띄우기 (사내 ChatGPT의 뼈대)

**왜**: 이 단계부터 노트북이나 다른 프로그램이 서버에 질문을 보낼 수 있습니다. ChatGPT와 같은 형식의 주소(`/v1/chat/completions`)를 쓰므로, 기성 채팅 화면 프로그램을 그대로 연결할 수 있습니다.

방화벽에서 8000번 문을 엽니다 (한 번만):
```bash
sudo firewall-cmd --add-port=8000/tcp --permanent && sudo firewall-cmd --reload
```

서버 실행:
```bash
cd ~/work/local_llm && uv run python -m llama_cpp.server --model models/qwen2.5-7b-instruct-q4_k_m.gguf --n_gpu_layers -1 --n_ctx 8192 --host 0.0.0.0 --port 8000
```

**확인 기준** (노트북의 PowerShell이나 다른 터미널에서):
```bash
curl http://192.168.0.193:8000/v1/models
```
모델 이름이 든 JSON이 돌아옵니다. 이어서 질문:
```bash
curl http://192.168.0.193:8000/v1/chat/completions -H "Content-Type: application/json" -d "{\"messages\":[{\"role\":\"user\",\"content\":\"우리 회사는 서버와 스토리지를 납품하는 회사야. 자기소개 한 줄 해줘.\"}]}"
```
`content`에 한국어 답이 들어 있으면 성공입니다.

**설명**
- `--n_gpu_layers -1`: 모든 층을 GPU에 올림. GPU 2~3장이 있으면 llama.cpp가 자동으로 나눠 올립니다.
- `--n_ctx 8192`: 한 대화에서 기억하는 길이(토큰). A4 약 10장. 늘리면 메모리를 더 씁니다.
- 브라우저로 `http://192.168.0.193:8000/docs`를 열면 API 설명 화면이 나옵니다.

**서버를 계속 켜 두려면**: 터미널을 닫아도 돌아가게 `tmux`나 `systemd` 서비스로 등록합니다. 이건 동작 확인 후 노트북 세션에게 "systemd 서비스로 등록해 줘"라고 시키면 됩니다.

---

## 7단계. 큰 모델로 품질 비교 (32B, 약 20GB)

**왜**: 7B는 빠르지만 답이 얕습니다. 32B는 "신입"에서 "3년 차"로 올라가는 느낌이고, GPU 2장이면 여유 있게 돌아갑니다.

```bash
cd ~/work/local_llm && uv run hf download bartowski/Qwen2.5-32B-Instruct-GGUF Qwen2.5-32B-Instruct-Q4_K_M.gguf --local-dir models
```
```bash
uv run python -m llama_cpp.server --model models/Qwen2.5-32B-Instruct-Q4_K_M.gguf --n_gpu_layers -1 --n_ctx 8192 --host 0.0.0.0 --port 8000
```

**확인 기준**
- `nvidia-smi`에서 GPU 두 장에 메모리가 나뉘어 올라가 있습니다 (각 10GB 안팎).
- 같은 질문을 7B와 32B에 던져 답의 깊이를 비교합니다. 예: "고객사 서버에서 RAID 디그레이드 경고가 떴을 때 점검 순서를 알려줘."
- 속도는 7B보다 느려지지만 (초당 15~30 토큰) 읽는 속도보다는 빠릅니다.

**GPU를 나누는 옵션** (필요할 때만)
- 특정 GPU만 쓰기: 명령 앞에 `CUDA_VISIBLE_DEVICES=0,1` (3번 GPU는 다른 용도로 비워 둘 때)
- 비율 조절: `--tensor_split 1 1` (두 장에 반반), `--tensor_split 2 1` (첫 장에 2배)

---

## 8단계. 채팅 화면 붙이기 (선택, 10분)

**왜**: 직원들은 터미널이 아니라 ChatGPT 같은 화면이 필요합니다. 기성 프로그램 **Open WebUI**를 붙이면 로그인, 대화 기록, 파일 첨부까지 바로 생깁니다.

```bash
sudo dnf install -y podman
```
```bash
podman run -d --name open-webui -p 3000:8080 -e OPENAI_API_BASE_URL=http://192.168.0.193:8000/v1 -e OPENAI_API_KEY=local -v open-webui:/app/backend/data ghcr.io/open-webui/open-webui:main
```
```bash
sudo firewall-cmd --add-port=3000/tcp --permanent && sudo firewall-cmd --reload
```

**확인 기준**: 노트북 브라우저에서 `http://192.168.0.193:3000`을 열면 가입 화면이 뜹니다. 첫 가입자가 관리자가 됩니다.

---

## 자주 나는 문제

| 증상 | 원인 | 해결 |
|---|---|---|
| `CUDA error: out of memory` | 모델 + 문맥이 GPU 메모리보다 큼 | `--n_ctx`를 4096으로 줄이거나 더 작은 압축본(Q4_K_S)을 쓰거나 GPU를 더 묶음 |
| `offloaded 0/… layers to GPU` | GPU 없이 빌드됨 | 3단계의 `CMAKE_ARGS="-DGGML_CUDA=on" uv sync --reinstall-package llama-cpp-python` 재실행 |
| 노트북에서 접속이 안 됨 | 방화벽 또는 `--host` 누락 | 6단계 방화벽 명령 확인, `--host 0.0.0.0` 확인 |
| 모델 다운로드가 403/느림 | 인터넷 제한 | 다른 PC에서 받아 `models/`로 복사 |
| `nvidia-smi`가 재부팅 후 사라짐 | 커널 업데이트로 드라이버 모듈 불일치 | `sudo dnf reinstall kmod-nvidia-latest-dkms` 후 재부팅 |
| 답이 영어로만 나옴 | 시스템 메시지 없음 | 요청에 `{"role":"system","content":"항상 한국어로 답하세요."}`를 첫 메시지로 넣음 |

---

## 오늘의 목표 체크리스트

- [ ] 0단계: GPU, 디스크, 인터넷 확인
- [ ] 1단계: (필요 시) 드라이버 설치 후 `nvidia-smi` 정상
- [ ] 3단계: GPU 모드 설치, `llama_supports_gpu_offload()` → True
- [ ] 5단계: 7B로 한국어 첫 대화 성공
- [ ] 6단계: 노트북에서 `curl`로 API 응답 확인
- [ ] 7단계: 32B 올려서 품질 비교
- [ ] 8단계: (선택) Open WebUI 화면 접속

여기까지 되면 "사내 ChatGPT" 1단계가 끝난 것입니다. 다음은 업무 사이트(rnb-dashboard)의 DB를 읽어 답하는 2단계입니다.
