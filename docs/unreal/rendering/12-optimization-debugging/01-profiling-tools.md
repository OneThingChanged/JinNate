# 프로파일링 도구

렌더링 성능 분석을 위한 다양한 프로파일링 도구와 사용법을 다룹니다.

---

## 개요

성능 최적화의 첫 단계는 정확한 측정입니다. UE는 내장 프로파일러와 외부 도구 연동을 모두 지원합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    프로파일링 도구 생태계                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    UE 내장 도구                            │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  Unreal Insights │ GPU Profiler │ Stat Commands          │  │
│  │  Frame Debugger  │ Console Vars │ Visual Debugger        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    외부 도구                               │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  RenderDoc  │  PIX  │  NSight  │  Intel GPA  │  XCode    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    플랫폼별 도구                            │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │  Razor (PS5)  │  PIX (Xbox)  │  Snapdragon (Mobile)      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Unreal Insights

UE5의 핵심 프로파일링 도구로, CPU/GPU/메모리를 통합 분석합니다.

### 트레이스 시작

```cpp
// 명령줄에서 트레이스 활성화
-trace=default,gpu

// 런타임에서 트레이스 시작/중지
Trace.Start default,gpu
Trace.Stop
```

### 타이밍 분석

```
┌─────────────────────────────────────────────────────────────────┐
│                 Unreal Insights 타이밍 뷰                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame 1234                    16.67ms                          │
│  ├── Game Thread ─────────────────────────────── 8.2ms          │
│  │   ├── Tick                                    3.1ms          │
│  │   ├── Physics                                 2.4ms          │
│  │   └── Animation                               2.7ms          │
│  │                                                              │
│  ├── Render Thread ───────────────────────────── 6.8ms          │
│  │   ├── InitViews                               1.2ms          │
│  │   ├── BasePass                                2.8ms          │
│  │   └── Lighting                                2.8ms          │
│  │                                                              │
│  └── GPU ─────────────────────────────────────── 12.4ms         │
│      ├── PrePass                                 1.8ms          │
│      ├── BasePass                                4.2ms          │
│      ├── Lighting                                3.6ms          │
│      └── PostProcess                             2.8ms          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### GPU 타이밍 마커 추가

```cpp
// 셰이더 패스에 GPU 마커 추가
SCOPED_GPU_STAT(RHICmdList, CustomPass);

// 또는 수동으로
RHICmdList.PushEvent(TEXT("MyCustomPass"), FColor::Green);
// ... 렌더링 코드
RHICmdList.PopEvent();
```

### 메모리 분석

```cpp
// 메모리 트레이스 활성화
-trace=memory

// 특정 할당 추적
LLM_SCOPE(ELLMTag::Textures);
LLM_SCOPE_BYTAG(CustomTag);
```

---

## Stat 명령어

콘솔 명령을 통한 실시간 통계 확인.

### 핵심 Stat 명령

```cpp
// 프레임 타이밍
stat fps              // FPS만 표시
stat unit             // Game/Draw/GPU/RHIT 시간
stat unitgraph        // 그래프 형태로 표시

// GPU 상세
stat gpu              // GPU 패스별 시간
stat d3d12rhi         // D3D12 RHI 통계
stat rhi              // RHI 호출 통계

// 렌더링 상세
stat scenerendering   // 씬 렌더링 통계
stat initviews        // 뷰 초기화 통계
stat lightrendering   // 라이트 렌더링
stat shadowrendering  // 섀도우 렌더링
```

### Stat 출력 분석

```
┌─────────────────────────────────────────────────────────────────┐
│                        stat unit 출력                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame:   16.67 ms    (60.0 fps)                                │
│  Game:     4.21 ms    ◀── 게임 로직                             │
│  Draw:     3.45 ms    ◀── 렌더 스레드 (Draw Call 제출)          │
│  GPU:     11.23 ms    ◀── GPU 실행 시간                         │
│  RHIT:     1.02 ms    ◀── RHI 스레드                            │
│  DynRes:   100%                                                 │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ 병목 판단:                                               │    │
│  │ - GPU > Game, Draw → GPU Bound                          │    │
│  │ - Game > GPU, Draw → CPU Bound (게임 로직)              │    │
│  │ - Draw > GPU, Game → CPU Bound (렌더 스레드)            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Draw Call 분석

```cpp
stat scenerendering

// 출력 예시:
// MeshDrawCalls: 2847
// - StaticMeshes: 1523
// - SkeletalMeshes: 234
// - Particles: 890
// - Others: 200
```

---

## RenderDoc

오픈소스 그래픽 디버거로 프레임 캡처 및 분석에 최적.

### 연동 설정

```cpp
// DefaultEngine.ini
[/Script/Engine.RendererSettings]
r.RenderDoc.BinaryPath=C:/RenderDoc/renderdoc.dll
r.RenderDoc.EnableCrashHandler=True

// 또는 실행 인자
-RenderDoc
```

### 캡처 및 분석

```
┌─────────────────────────────────────────────────────────────────┐
│                    RenderDoc 워크플로우                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 캡처 (F12 또는 Print Screen)                                │
│     ┌─────────────────────────────────────────────────────┐     │
│     │  Frame 1234 captured                                │     │
│     │  Duration: 16.67ms                                  │     │
│     │  API Calls: 4,523                                   │     │
│     │  Draw Calls: 847                                    │     │
│     └─────────────────────────────────────────────────────┘     │
│                                                                 │
│  2. 이벤트 브라우저                                             │
│     ├── Frame Start                                             │
│     ├── PrePass                                                 │
│     │   ├── Draw [Static Mesh] (256 verts)                     │
│     │   └── Draw [Static Mesh] (1024 verts)                    │
│     ├── BasePass                                                │
│     │   └── ...                                                 │
│     └── PostProcess                                             │
│                                                                 │
│  3. 리소스 검사                                                 │
│     - 텍스처 바인딩 확인                                        │
│     - 버퍼 내용 검사                                            │
│     - 셰이더 소스 확인                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 셰이더 디버깅

```cpp
// RenderDoc에서 셰이더 디버깅
// 1. 픽셀 선택
// 2. Debug Pixel 클릭
// 3. 셰이더 스텝 실행
// 4. 변수 값 확인

// 디버그 정보 포함 컴파일
r.Shaders.KeepDebugInfo=1
```

### 텍스처 뷰어

```
┌─────────────────────────────────────────────────────────────────┐
│                  RenderDoc 텍스처 뷰어                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  텍스처: SceneColor                                             │
│  포맷: R16G16B16A16_FLOAT                                       │
│  크기: 1920 x 1080                                              │
│  Mip 레벨: 11                                                   │
│                                                                 │
│  채널 표시: [R] [G] [B] [A]                                     │
│  범위: Min 0.0 ─────────────── Max 10.0                         │
│  히스토그램: ▁▂▃▅▇▅▃▂▁                                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                                                         │    │
│  │                   [텍스처 프리뷰]                        │    │
│  │                                                         │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  픽셀 (960, 540): R=1.234 G=0.567 B=0.890 A=1.0                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## PIX (Windows/Xbox)

Microsoft의 공식 그래픽 디버거로, D3D12 분석에 최적화.

### GPU 캡처

```cpp
// PIX 마커 추가 (자동으로 UE 이벤트와 연동)
PIXBeginEvent(CommandList, PIX_COLOR(255, 0, 0), L"MyCustomPass");
// ... 렌더링
PIXEndEvent(CommandList);
```

### 타이밍 분석

```
┌─────────────────────────────────────────────────────────────────┐
│                      PIX GPU 타이밍                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Timeline View:                                                 │
│                                                                 │
│  Queue 0 (Graphics):                                            │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ PrePass  │  BasePass      │  Lighting  │  PostProcess   │   │
│  │  1.2ms   │    4.5ms       │   3.2ms    │     2.1ms      │   │
│  ├──────────────────────────────────────────────────────────┤   │
│                                                                 │
│  Queue 1 (Compute):                                             │
│  ├──────────────────────────────────────────────────────────┤   │
│  │     │ Culling │     │ SSAO Compute │                    │   │
│  │     │  0.3ms  │     │    0.8ms     │                    │   │
│  ├──────────────────────────────────────────────────────────┤   │
│                                                                 │
│  Occupancy: ████████░░ 80%                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 메모리 분석

```cpp
// PIX 메모리 스냅샷
// 1. GPU 메모리 사용량 확인
// 2. 힙별 분석
// 3. 리소스 크기 정렬

// 출력 예시:
// Total GPU Memory: 4.2 GB
// ├── Textures: 2.1 GB (50%)
// ├── Buffers: 1.4 GB (33%)
// ├── RT/DS: 0.5 GB (12%)
// └── Other: 0.2 GB (5%)
```

---

## NSight (NVIDIA)

NVIDIA GPU 전용 심층 분석 도구.

### GPU 트레이스

```
┌─────────────────────────────────────────────────────────────────┐
│                     NSight GPU 트레이스                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  SM Throughput:        78%                                      │
│  Memory Throughput:    92%  ◀── 메모리 병목 의심                │
│  L2 Hit Rate:          67%                                      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Warp State Analysis                                     │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ Active:          ████████████░░░░░░ 65%                 │    │
│  │ Waiting Memory:  ████████░░░░░░░░░░ 28%  ◀── 문제!      │    │
│  │ Waiting Barrier: ██░░░░░░░░░░░░░░░░ 5%                  │    │
│  │ Stalled:         █░░░░░░░░░░░░░░░░░ 2%                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  권장사항:                                                      │
│  - 텍스처 캐시 최적화 필요                                      │
│  - 메모리 접근 패턴 개선 검토                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 셰이더 프로파일러

```cpp
// NSight 셰이더 분석 출력 예시
// Shader: BasePass_PS
//
// Instructions:
// - ALU: 234
// - TEX: 45
// - Total: 279
//
// Register Pressure:
// - VGPR: 48 (target: < 64)
// - SGPR: 32
//
// Occupancy: 75% (6/8 waves)
```

---

## 시각화 모드

### 셰이더 복잡도

```cpp
// 셰이더 복잡도 시각화
viewmode shadercomplexity

// 또는 콘솔에서
r.ShaderComplexity.Mode 1  // 인스트럭션 수
r.ShaderComplexity.Mode 2  // 텍스처 샘플
```

```
┌─────────────────────────────────────────────────────────────────┐
│                   셰이더 복잡도 색상 스케일                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  초록 ──────────────────────────────────────────────────▶ 빨강  │
│  낮음                                                     높음  │
│                                                                 │
│  ■ 초록: < 64 인스트럭션 (양호)                                 │
│  ■ 노랑: 64-128 인스트럭션 (주의)                               │
│  ■ 주황: 128-256 인스트럭션 (경고)                              │
│  ■ 빨강: > 256 인스트럭션 (위험)                                │
│  ■ 분홍: > 512 인스트럭션 (매우 위험)                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 라이트 복잡도

```cpp
viewmode lightcomplexity

// 색상별 의미:
// 초록: 1-2 라이트
// 노랑: 3-4 라이트
// 빨강: 5+ 라이트 (최적화 필요)
```

### 쿼드 오버드로우

```cpp
viewmode quadoverdraw

// 픽셀당 렌더링 횟수 시각화
// 높은 오버드로우 = Fillrate 병목
```

---

## 콘솔 변수를 이용한 테스트

### 병목 격리

```cpp
// GPU 병목 테스트: 해상도 낮추기
r.ScreenPercentage 50
// FPS가 크게 오르면 → Fillrate/셰이더 병목

// CPU 병목 테스트: 렌더링 끄기
r.MinScreenRadiusForLights 10
// FPS 변화 없으면 → CPU 병목

// Draw Call 병목 테스트
r.StaticMeshLODDistanceScale 0.25
// Draw Call 감소로 FPS 오르면 → Draw Call 병목
```

### 기능별 비용 측정

```cpp
// 섀도우 비용
r.Shadow.MaxResolution 512  // 해상도 낮추기
r.Shadow.CSM.MaxCascades 1  // 캐스케이드 줄이기

// 포스트 프로세스 비용
r.BloomQuality 0
r.AmbientOcclusionLevels 0
r.MotionBlurQuality 0

// 반사 비용
r.ReflectionCaptureResolution 64
r.SSR.Quality 0
```

---

## 자동화 프로파일링

### 스크립트 기반 테스트

```cpp
// 자동 프로파일링 설정
FAutomationTestInfo TestInfo;
TestInfo.SetTestName("RenderingPerfTest");
TestInfo.SetTestGroup(EAutomationTestGroup::Benchmark);

// CSV 출력
-csvFile=PerfResults.csv -benchmark
```

### CI/CD 통합

```yaml
# GitHub Actions 예시
- name: Run Performance Tests
  run: |
    ./Engine/Binaries/Win64/UnrealEditor-Cmd.exe \
      -game -benchmark \
      -ExecCmds="stat fps,stat unit" \
      -csvFile=perf_results.csv

- name: Check Performance Regression
  run: python check_perf_regression.py perf_results.csv
```

---

## 요약

| 도구 | 용도 | 장점 |
|------|------|------|
| Unreal Insights | 통합 분석 | CPU/GPU/메모리 통합 |
| Stat 명령 | 실시간 모니터링 | 즉시 확인 가능 |
| RenderDoc | 프레임 디버깅 | 상세한 리소스 분석 |
| PIX | D3D12 분석 | Xbox 개발 필수 |
| NSight | NVIDIA 심층 분석 | 하드웨어 수준 분석 |

---

## 참고 자료

- [Unreal Insights Documentation](https://docs.unrealengine.com/unreal-insights/)
- [RenderDoc](https://renderdoc.org/)
- [PIX for Windows](https://devblogs.microsoft.com/pix/)
- [NSight Graphics](https://developer.nvidia.com/nsight-graphics)
