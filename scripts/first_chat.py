"""첫 대화 확인용 스크립트.

사용법:
    uv run python scripts/first_chat.py models/모델파일.gguf

하는 일:
    1. 모델 파일을 읽어 GPU(없으면 CPU)에 올립니다.
    2. 한국어로 질문 두 개를 던지고 답을 화면에 보여 줍니다.
    3. 답이 나오는 속도(초당 토큰 수)를 함께 보여 줍니다.

성공 기준:
    - 답이 한국어로 자연스럽게 나온다.
    - 실행 중 출력에 "offloaded N/N layers to GPU" 처럼 모든 층이 GPU에 올라갔다는 줄이 보인다.
"""

import sys
import time
from pathlib import Path

from llama_cpp import Llama

QUESTIONS = [
    "한국의 수도는 어디야? 한 문장으로 답해줘.",
    "우리 회사는 서버와 스토리지를 납품하고 유지보수하는 회사야. "
    "고객사 서버에서 RAID 디그레이드 경고가 떴을 때 점검 순서를 다섯 줄로 알려줘.",
]


def main() -> None:
    if len(sys.argv) < 2:
        print("사용법: uv run python scripts/first_chat.py models/모델파일.gguf")
        sys.exit(1)

    model_path = Path(sys.argv[1])
    if not model_path.exists():
        print(f"모델 파일이 없습니다: {model_path}")
        sys.exit(1)

    print(f"모델을 올리는 중입니다: {model_path}")
    started = time.time()
    llm = Llama(
        model_path=str(model_path),
        n_gpu_layers=-1,   # -1: 모든 층을 GPU에. GPU가 없으면 자동으로 CPU 사용
        n_ctx=4096,        # 한 대화에서 기억하는 길이(토큰)
        verbose=True,      # 층이 GPU에 올라가는 과정을 보여 줌
    )
    print(f"\n모델 로드 완료: {time.time() - started:.1f}초\n")

    for question in QUESTIONS:
        print("=" * 60)
        print("질문:", question)
        print("-" * 60)
        started = time.time()
        tokens = 0
        stream = llm.create_chat_completion(
            messages=[
                {"role": "system", "content": "당신은 사내 기술지원 비서입니다. 항상 한국어로 간결하게 답하세요."},
                {"role": "user", "content": question},
            ],
            max_tokens=400,
            temperature=0.3,
            stream=True,
        )
        for chunk in stream:
            delta = chunk["choices"][0]["delta"]
            if "content" in delta and delta["content"]:
                print(delta["content"], end="", flush=True)
                tokens += 1
        elapsed = time.time() - started
        print(f"\n\n[{tokens} 토큰, {elapsed:.1f}초, 초당 {tokens / max(elapsed, 0.001):.1f} 토큰]\n")


if __name__ == "__main__":
    main()
