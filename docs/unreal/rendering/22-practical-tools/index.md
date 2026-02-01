# Ch.22 실용 도구 모음

렌더링 개발에 필요한 실용 도구, 명령어, 디버깅 기법을 정리합니다.

---

## 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                      실용 도구 모음                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Tool Categories                       │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                          │   │
│  │  Console        Debug          Editor        Custom      │   │
│  │  Commands   →   Visualization → Tools    →   Development │   │
│  │                                                          │   │
│  │  • stat        • ViewMode     • Profiler   • Blueprint  │   │
│  │  • r.          • ShowFlag     • Reflector  • Plugin     │   │
│  │  • Show        • Draw Debug   • Audit      • Commandlet │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  활용 시나리오:                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Performance  │  │ Visual       │  │ Asset        │         │
│  │ Analysis     │  │ Debugging    │  │ Management   │         │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤         │
│  │ • Profiling  │  │ • Wireframe  │  │ • Reference  │         │
│  │ • Bottleneck │  │ • Collision  │  │ • Size Map   │         │
│  │ • Memory     │  │ • Bounds     │  │ • Validation │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 주제

### [1. 콘솔 명령어 모음](01-console-commands.md)
- 렌더링 명령어
- 통계 명령어
- 디버그 명령어
- 설정 명령어

### [2. 디버그 시각화](02-debug-visualization.md)
- ViewMode
- ShowFlag
- Draw Debug
- 시각화 셰이더

### [3. 에디터 도구](03-editor-tools.md)
- 프로파일러
- Widget Reflector
- Asset Audit
- Reference Viewer

### [4. 커스텀 도구 개발](04-custom-tools.md)
- Editor Utility Widget
- Blueprint 도구
- Commandlet
- 플러그인 개발

### [5. 트러블슈팅 가이드](05-troubleshooting.md)
- 일반적인 문제
- 셰이더 오류
- 메모리 문제
- 성능 문제

---

## 빠른 참조

```
┌─────────────────────────────────────────────────────────────────┐
│                    Quick Reference                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  성능 확인:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  stat fps              FPS 표시                          │   │
│  │  stat unit             GT/RT/GPU 시간                    │   │
│  │  stat gpu              GPU 패스별 시간                   │   │
│  │  ProfileGPU            GPU 프로파일 캡처                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  시각화:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ViewMode Wireframe    와이어프레임                      │   │
│  │  ViewMode Lit          기본 렌더링                       │   │
│  │  ViewMode ShaderComplexity  셰이더 복잡도               │   │
│  │  Show Collision        콜리전 표시                       │   │
│  │  Show Bounds           바운드 박스 표시                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  디버그:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  r.ShaderDevelopmentMode=1  셰이더 개발 모드            │   │
│  │  recompileshaders all       셰이더 재컴파일             │   │
│  │  ToggleDebugCamera          디버그 카메라               │   │
│  │  FreezeRendering            렌더링 프리즈               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 자주 사용하는 단축키

| 단축키 | 기능 |
|--------|------|
| `F5` | 셰이더 재컴파일 |
| `Ctrl+Shift+,` | GPU 프로파일러 |
| `Ctrl+Shift+H` | FPS 표시 토글 |
| `` ` `` (백틱) | 콘솔 열기 |
| `~` (틸드) | 콘솔 열기 (전체) |
| `F1` | 디버그 카메라 |
| `G` | 게임 뷰 토글 |

---

## 주요 CVar 카테고리

| 접두사 | 카테고리 |
|--------|----------|
| `r.` | 렌더링 |
| `sg.` | 스케일러빌리티 |
| `gc.` | 가비지 컬렉션 |
| `net.` | 네트워크 |
| `p.` | 물리 |
| `a.` | 오디오 |
| `fx.` | 이펙트 (Niagara) |

---

## 참고 자료

- [Console Variables](https://docs.unrealengine.com/console-variables/)
- [Debugging Tools](https://docs.unrealengine.com/debugging-tools/)
- [Editor Tools](https://docs.unrealengine.com/editor-tools/)
