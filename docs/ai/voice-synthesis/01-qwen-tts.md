# Qwen3-TTS

Alibaba Qwen팀의 오픈소스 음성합성(TTS) 모델

---

## 프로젝트 정보

| 항목 | 내용 |
|------|------|
| GitHub | https://github.com/QwenLM/Qwen3-TTS |
| 라이선스 | Apache-2.0 |
| 모델 크기 | ~3.5GB |
| VRAM | 6GB+ 권장 |

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    Qwen3-TTS Pipeline                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │  텍스트   │ → │  언어 모델    │ → │  음성 디코더  │ → 음성   │
│  │  입력     │    │  (1.7B)      │    │  (12Hz)      │          │
│  └──────────┘    └──────────────┘    └──────────────┘          │
│        │                │                    │                  │
│        ▼                ▼                    ▼                  │
│    언어 선택        화자 선택           감정/스타일              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 지원 화자

| 화자 | 성별 | 추천 언어 |
|------|------|-----------|
| `Sohee` | 여성 | 한국어 |
| `Vivian` | 여성 | 영어 |
| `Ryan` | 남성 | 영어 |
| `Serena` | 여성 | 영어 |
| `Aiden` | 남성 | 영어 |
| `Dylan` | 남성 | 영어 |
| `Eric` | 남성 | 영어 |
| `Ono_anna` | 여성 | 일본어 |
| `Uncle_fu` | 남성 | 중국어 |

---

## 지원 언어

Korean, English, Chinese, Japanese, German, French, Russian, Portuguese, Spanish, Italian

---

## 설치 방법

### 1. 저장소 클론

```bash
git clone https://github.com/QwenLM/Qwen3-TTS.git
cd Qwen3-TTS
```

### 2. 가상환경 생성

```bash
python -m venv venv
source venv/Scripts/activate  # Windows Git Bash
```

### 3. 패키지 설치

```bash
pip install -e .
```

### 4. CUDA 버전 PyTorch 설치

기본 설치시 CPU 버전이 설치되므로, CUDA 버전으로 재설치:

```bash
pip uninstall torch torchaudio -y
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu124
```

---

## 사용 방법

### 웹 UI (권장)

```bash
python web_ui.py
```

브라우저에서 http://127.0.0.1:7860 접속

**기능:**

- 텍스트 입력
- 언어 선택
- 화자 선택
- 감정/스타일 지정 (선택)

### Python 코드

```python
import torch
import soundfile as sf
from qwen_tts import Qwen3TTSModel

# 모델 로드
tts = Qwen3TTSModel.from_pretrained(
    "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    device_map="cuda:0",
    dtype=torch.bfloat16,
)

# 음성 생성
wavs, sr = tts.generate_custom_voice(
    text="안녕하세요! 반갑습니다.",
    language="Korean",
    speaker="Sohee",
    instruct="밝고 명랑하게",  # 선택사항
)

# 파일 저장
sf.write("output.wav", wavs[0], sr)
```

---

## 모델 종류

| 모델 | 용도 | HuggingFace |
|------|------|-------------|
| CustomVoice | 내장 화자 + 감정 지시 | `Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice` |
| Base | 음성 복제 | `Qwen/Qwen3-TTS-12Hz-1.7B-Base` |

---

## 음성 복제

3초 이상의 참조 오디오로 목소리 복제:

```python
tts = Qwen3TTSModel.from_pretrained(
    "Qwen/Qwen3-TTS-12Hz-1.7B-Base",
    device_map="cuda:0",
    dtype=torch.bfloat16,
)

wavs, sr = tts.generate_voice_clone(
    text="복제된 목소리로 말합니다.",
    language="Korean",
    ref_audio="참조_음성.wav",       # 3초 이상
    ref_text="참조 음성의 대사 내용",
)

sf.write("cloned_voice.wav", wavs[0], sr)
```

---

## 빠른 시작

### 서버 시작

```
start-server.bat 더블클릭
```

### 접속 URL

```
http://127.0.0.1:7860
```

### 서버 종료

```
stop-server.bat 더블클릭
```

---

## 주의사항

1. **첫 실행시 모델 다운로드** (~3.5GB) - HuggingFace에서 자동 다운로드
2. **SoX 경고** - 무시해도 됨 (기본 기능에 영향 없음)
3. **flash-attn 경고** - 선택사항, 없어도 작동함
4. **GPU 메모리 부족시** - 다른 GPU 사용 프로그램 종료 후 재시도

---

## 참고

- [GitHub](https://github.com/QwenLM/Qwen3-TTS)
- [HuggingFace](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice)
