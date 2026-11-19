# 02. GPU 드라이버와 CUDA 설치

- 작업 날짜: 2026-11-19
- 대상 서버: `ai-server` (192.168.0.193), Rocky Linux 9.9, RTX 3090 24GB × 2
- 전제: [01. 서버 기본 준비](01_서버_기본_준비.md)가 끝나 있어야 합니다. (최신 커널, kernel-devel, dkms, EPEL)

이 단계가 끝나면 운영체제가 GPU 두 장을 제대로 부릴 수 있게 되고, GPU로 계산하는 프로그램을 만들 도구(CUDA)가 갖춰집니다.

> 용어: **드라이버**는 운영체제와 그래픽카드 사이의 통역사입니다. **CUDA**는 그 통역사를 통해 GPU에 계산을 시키는 도구 모음입니다.
> **dkms**는 커널(운영체제 심장)이 업데이트될 때 드라이버를 새 커널에 맞춰 자동으로 다시 조립해 주는 장치입니다.

---

## 1. NVIDIA 저장소 등록

**왜 하나요?** Rocky Linux 기본 창고에는 NVIDIA 드라이버가 없습니다. NVIDIA가 직접 운영하는 창고(저장소)를 등록해야 합니다.

```bash
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
dnf clean all
```
→ 저장소 관리 도구를 깔고, NVIDIA의 RHEL 9용 창고 주소를 등록한 뒤, 창고 목록을 새로 읽습니다.
(Rocky 9는 RHEL 9와 호환되므로 `rhel9` 주소를 그대로 씁니다.)

**확인**
```bash
dnf repolist | grep cuda
```
→ `cuda-rhel9-x86_64` 한 줄이 보이면 됩니다.

```bash
dnf module list nvidia-driver
```
→ 설치할 수 있는 드라이버 묶음(스트림) 목록이 나옵니다. `open-dkms`에 `[d]`(기본) 표시가 있습니다.

---

## 2. 드라이버 설치

**어떤 걸 고르나요?** NVIDIA는 드라이버를 두 가지로 제공합니다.
- **open**: 커널 쪽 코드가 공개된 방식. RTX 20 시리즈 이후(3090 포함)에 NVIDIA가 권장.
- **proprietary(비공개)**: 옛 GPU용. 여기서는 쓰지 않습니다.

`open-dkms` 묶음은 "공개 방식 + 커널 바뀔 때 자동 재조립"입니다.

```bash
dnf module enable -y nvidia-driver:open-dkms
```
→ 드라이버 묶음을 `open-dkms`로 고정합니다.

```bash
dnf -y install nvidia-open
```
→ 드라이버를 설치합니다. 내려받기 수백 MB, 커널에 맞춰 조립하는 시간까지 5~10분 걸립니다.
설치 과정에서 기본 드라이버 nouveau를 막는 설정과 부팅 이미지 갱신이 자동으로 처리됩니다.

> 오래 걸리는 작업을 접속이 끊겨도 계속 돌리려면:
> `nohup dnf -y install nvidia-open > /root/nvidia-install.log 2>&1 &` 로 시작하고 `tail -f /root/nvidia-install.log`로 지켜봅니다.

**확인**
```bash
dkms status
```
→ `nvidia-open/620.xx, 5.14.0-xxx, x86_64: installed` 처럼 **installed**가 보여야 합니다.

```bash
grep -rh "blacklist nouveau" /etc/modprobe.d/ /usr/lib/modprobe.d/
```
→ nouveau를 막는 줄이 한 줄 이상 나와야 합니다.

| 항목 | 결과 (2026-11-19) |
|---|---|
| 드라이버 버전 | nvidia-open 620.70.06 (패키지 24개, 약 7분) |
| dkms 상태 | `nvidia/620.70.06, 5.14.0-741.22.1.el9_9.x86_64, x86_64: installed` |
| nouveau 차단 | `/usr/lib/modprobe.d/nvidia.conf`에 `blacklist nouveau` 자동 생성, 부팅 옵션에도 반영됨 |

---

## 3. 재부팅

**왜 하나요?** 지금 올라가 있는 nouveau를 내리고 NVIDIA 드라이버를 올리는 가장 확실한 방법입니다.

```bash
reboot
```
→ 2~3분 뒤 다시 접속합니다.

---

## 4. GPU 확인

```bash
nvidia-smi
```
→ 아래처럼 표가 나오고, GPU 줄이 **두 개** 보여야 합니다.

```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 620.70.06              KMD Version: 620.70.06     CUDA UMD Version: 13.5     |
+-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 3090        On  |   00000000:01:00.0 Off |                  N/A |
| 30%   36C    P0            107W /  350W |       1MiB /  24576MiB |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
|   1  NVIDIA GeForce RTX 3090        On  |   00000000:81:00.0 Off |                  N/A |
| 30%   34C    P0            109W /  350W |       1MiB /  24576MiB |      0%      Default |
+-----------------------------------------+------------------------+----------------------+
```
(2026-11-19 재부팅 직후 실제 출력. 아래 Processes 표는 생략)

읽는 법
- 맨 윗줄 `Driver Version`: 드라이버 버전. `CUDA Version`: 이 드라이버가 지원하는 CUDA 최대 버전.
- 각 GPU 줄의 `24576MiB`: 메모리 24GB. `0%`: 현재 사용률(지금은 아무것도 안 돌리니 0).
- `Bus-Id` 01:00.0과 81:00.0: 00 문서의 PCI 조사 결과와 일치합니다.
- 재부팅 후 `lsmod` 결과: `nvidia_drm nvidia_modeset nvidia_uvm nvidia` 네 개가 올라오고 nouveau는 없음.

```bash
lsmod | grep -E "^nvidia|^nouveau"
```
→ `nvidia`로 시작하는 줄들이 있고 `nouveau`는 없어야 합니다.

---

## 5. CUDA 툴킷 설치

**왜 하나요?** 드라이버만 있으면 GPU를 "쓸" 수는 있지만, llama.cpp처럼 GPU용 프로그램을 서버에서 직접 조립(빌드)하려면 CUDA 컴파일러(`nvcc`)가 필요합니다.

```bash
dnf -y install cuda-toolkit
```
→ 최신 CUDA 툴킷을 설치합니다. 3GB 안팎, 10분쯤 걸립니다. 드라이버는 이미 깔았으므로 다시 깔지 않습니다.

```bash
cat > /etc/profile.d/cuda.sh <<'SH'
# CUDA 도구를 어디서든 이름만으로 실행할 수 있게 경로 등록
export PATH=/usr/local/cuda/bin:$PATH
SH
source /etc/profile.d/cuda.sh
```
→ 모든 사용자가 `nvcc`를 바로 쓸 수 있게 경로를 등록합니다. 다음 로그인부터 자동 적용됩니다.

**확인**
```bash
nvcc --version | tail -2
```
→ `Cuda compilation tools, release 13.x` 가 보이면 됩니다.

| 항목 | 결과 (2026-11-19) |
|---|---|
| CUDA 툴킷 | 13.5.0 (nvcc V13.5.37), 패키지 72개, 내려받기 포함 약 20분 |
| 설치 위치 | `/usr/local/cuda` → `/usr/local/cuda-13.5` |
| 시스템 디스크 사용 | 5.4GB → 16GB (드라이버+CUDA로 약 10GB 증가) |

---

## 2단계 완료 후 서버 상태 요약

| 항목 | 값 |
|---|---|
| GPU 드라이버 | nvidia-open 620.70.06 (open-dkms 스트림, 커널 바뀌면 자동 재조립) |
| CUDA | 13.5 (`nvcc` 경로 등록됨, 드라이버가 지원하는 CUDA 최대 버전도 13.5) |
| GPU 인식 | RTX 3090 × 2, 각 24576MiB, Bus 01:00.0 / 81:00.0 |
| 작업 로그 | 서버의 `/root/nvidia-install.log`, `/root/cuda-install.log` |

다음 단계: [03. llama.cpp 설치와 모델 실행](03_llama_cpp_설치와_모델_실행.md)

---

## 문제가 생기면

| 증상 | 원인과 해결 |
|---|---|
| `nvidia-smi`가 "couldn't communicate with the NVIDIA driver" | 드라이버가 아직 안 올라옴. 재부팅했는지 확인. `dkms status`에 installed가 없으면 `dkms autoinstall` 후 재부팅 |
| `lsmod`에 nouveau가 여전히 보임 | 차단 설정이 부팅 이미지에 안 들어감. `dracut -f` 실행 후 재부팅 |
| 커널 업데이트 뒤 GPU가 안 보임 | dkms가 새 커널용 조립을 못 한 경우. `dkms autoinstall` 후 재부팅. kernel-devel이 새 커널과 같은 버전인지 확인 |
| GPU가 한 장만 보임 | `lspci | grep -i nvidia`로 두 장이 PCI에 잡히는지 확인. 한 장만 잡히면 전원 케이블·슬롯 문제 |
