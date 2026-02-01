# Ch.14 렌더링 엔진 역사

게임 엔진과 그래픽 기술의 발전 역사를 분석합니다.

---

## 개요

게임 엔진은 1990년대 중반부터 발전하여 현재의 고도로 정교한 시스템이 되었습니다. 이 챕터에서는 게임 엔진의 정의, 초기 시대, API 진화, GPU 하드웨어 발전, 현대 엔진들을 살펴봅니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    게임 엔진 발전 타임라인                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1992 ─── Wolfenstein 3D (id Software)                         │
│    │                                                            │
│  1993 ─── Doom (최초의 데이터 주도 아키텍처)                    │
│    │                                                            │
│  1996 ─── Quake (진정한 3D, 클라이언트-서버)                    │
│    │      3dfx Voodoo 1 (최초 3D 가속기)                        │
│    │                                                            │
│  1998 ─── Unreal Engine 1                                       │
│    │      NVIDIA RIVA TNT                                       │
│    │                                                            │
│  1999 ─── GeForce 256 (최초 GPU)                               │
│    │                                                            │
│  2001 ─── DirectX 8 (셰이더 모델 도입)                         │
│    │                                                            │
│  2004 ─── Unreal Engine 3, Source Engine                       │
│    │                                                            │
│  2012 ─── Unreal Engine 4                                       │
│    │                                                            │
│  2022 ─── Unreal Engine 5 (Nanite, Lumen)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 문서 구성

| 문서 | 내용 |
|------|------|
| [게임 엔진 정의](01-engine-definition.md) | 게임 엔진의 개념과 구성 요소 |
| [초기 시대](02-early-era.md) | 1999년 이전의 발전 |
| [API 진화](03-api-evolution.md) | DirectX와 OpenGL의 발전 |
| [하드웨어 진화](04-hardware-evolution.md) | GPU 하드웨어의 발전 |
| [현대 엔진들](05-modern-engines.md) | UE, Unity 등 현대 엔진 |

---

## 참고 자료

- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/16097134.html)
- [Game Engine Architecture (Jason Gregory)](https://www.gameenginebook.com/)
