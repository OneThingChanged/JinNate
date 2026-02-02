# RDG 디버깅

> 원문: [剖析虚幻渲染体系（11）- RDG](https://www.cnblogs.com/timlly/p/15217090.html)

RDG 디버깅 방법, 즉시 실행 모드, 콘솔 변수, 일반적인 문제 해결 방법을 설명합니다.

---

## 11.5.1 즉시 실행 모드 (Immediate Mode)

RDG의 지연 실행 특성은 디버깅을 어렵게 만들 수 있습니다. **즉시 실행 모드**는 Pass가 `AddPass()` 호출 시점에 바로 실행되도록 하여 이 문제를 해결합니다.

### 활성화 방법

```cpp
// 방법 1: 명령줄 인자 (시작 시)
UE4Editor.exe -rdgimmediate

// 방법 2: 콘솔 변수 (런타임)
r.RDG.ImmediateMode 1

// 방법 3: 코드에서 설정
static IConsoleVariable* CVarRDGImmediate =
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.RDG.ImmediateMode"));
if (CVarRDGImmediate)
{
    CVarRDGImmediate->Set(1);
}
```

### 일반 모드 vs 즉시 실행 모드

```
┌─────────────────────────────────────────────────────────────────┐
│                일반 모드 vs 즉시 실행 모드                       │
├────────────────────────────┬────────────────────────────────────┤
│         일반 모드          │        즉시 실행 모드              │
├────────────────────────────┼────────────────────────────────────┤
│ AddPass() → 큐에 저장      │ AddPass() → 즉시 실행             │
│ Execute()에서 일괄 실행    │ Execute()는 정리만 수행           │
│ 전체 프레임 최적화 적용    │ 최적화 없음 (컬링, 병합 등)       │
│ 디버깅 어려움              │ 브레이크포인트에서 즉시 확인      │
│ 성능 최적                  │ 성능 저하 (디버그 전용)           │
├────────────────────────────┼────────────────────────────────────┤
│ 프로덕션 빌드 사용         │ 개발/디버깅 시에만 사용           │
└────────────────────────────┴────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    즉시 실행 모드 동작                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  일반 모드:                                                     │
│  AddPass(A) → AddPass(B) → AddPass(C) → Execute()              │
│      ↓           ↓           ↓             ↓                   │
│   [큐 저장]   [큐 저장]   [큐 저장]   [컴파일+A+B+C 실행]       │
│                                                                 │
│  즉시 실행 모드:                                                │
│  AddPass(A) → AddPass(B) → AddPass(C) → Execute()              │
│      ↓           ↓           ↓             ↓                   │
│   [A 실행]    [B 실행]    [C 실행]    [정리만]                 │
│                                                                 │
│  디버깅 장점:                                                   │
│  • AddPass() 직후 브레이크포인트에서 결과 확인 가능            │
│  • 문제 Pass 정확히 식별                                       │
│  • RenderDoc 등 툴과 함께 사용 용이                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.5.2 디버그 콘솔 변수

### 주요 RDG 콘솔 변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `r.RDG.ImmediateMode` | 0 | 즉시 실행 모드 활성화 |
| `r.RDG.CullPasses` | 1 | Pass 컬링 활성화 |
| `r.RDG.MergeRenderPasses` | 1 | RenderPass 병합 활성화 |
| `r.RDG.Debug` | 0 | 디버그 레벨 (0:없음, 1:기본, 2:상세) |
| `r.RDG.Debug.ResourceLifetime` | 0 | 리소스 생명주기 추적 |
| `r.RDG.Debug.PassExecution` | 0 | Pass 실행 로깅 |
| `r.RDG.Debug.Barriers` | 0 | 배리어 디버깅 |
| `r.RDG.Debug.MemoryTracking` | 0 | 메모리 사용량 추적 |

### 콘솔 변수 사용 예시

```cpp
// 컬링 비활성화 (모든 Pass 실행)
r.RDG.CullPasses 0

// RenderPass 병합 비활성화
r.RDG.MergeRenderPasses 0

// 상세 디버그 모드
r.RDG.Debug 2

// 배리어 디버깅 활성화
r.RDG.Debug.Barriers 1

// 조합 사용 (문제 진단 시)
r.RDG.ImmediateMode 1
r.RDG.CullPasses 0
r.RDG.Debug 1
```

### 디버그 명령

```cpp
// RDG 통계 표시
stat RDG

// RDG 리소스 덤프
r.RDG.DumpResources

// RDG 그래프 시각화 (GraphViz 형식)
r.RDG.DumpGraph

// 현재 프레임 Pass 목록
r.RDG.DumpPasses
```

---

## 11.5.3 디버깅 기법

### 1. 이벤트 이름 활용

GPU 프로파일러와 RenderDoc에서 식별 가능한 명확한 이름을 사용합니다.

```cpp
// 좋은 예: 계층적이고 명확한 이름
GraphBuilder.AddPass(
    RDG_EVENT_NAME("PostProcess::Bloom::Downsample_Mip%d", MipLevel),
    Parameters,
    ERDGPassFlags::Raster,
    Lambda
);

// 나쁜 예: 불명확한 이름
GraphBuilder.AddPass(
    RDG_EVENT_NAME("Pass"),  // 어떤 Pass인지 알 수 없음
    ...
);
```

### 2. 리소스 이름 규칙

```cpp
// 좋은 예: 기능_단계_용도 형식
FRDGTextureRef BlurTempH = GraphBuilder.CreateTexture(
    Desc,
    TEXT("PostProcess_Blur_Horizontal_Temp")
);

// 나쁜 예: 불명확한 이름
FRDGTextureRef Tex = GraphBuilder.CreateTexture(Desc, TEXT("Temp"));
```

### 3. NeverCull을 활용한 디버그 Pass

```cpp
// 디버그용 Pass - 항상 실행됨
GraphBuilder.AddPass(
    RDG_EVENT_NAME("Debug_Visualization"),
    Parameters,
    ERDGPassFlags::Raster | ERDGPassFlags::NeverCull,  // 컬링 방지
    [](FRHICommandList& RHICmdList)
    {
        // 디버그 시각화 코드
    }
);
```

### 4. 브레이크포인트 전략

```cpp
// 즉시 실행 모드에서 Lambda 내부에 브레이크포인트
GraphBuilder.AddPass(
    RDG_EVENT_NAME("DebugPass"),
    Parameters,
    ERDGPassFlags::Compute | ERDGPassFlags::NeverCull,
    [](FRHICommandList& RHICmdList)
    {
        // ← 여기에 브레이크포인트 설정
        int DebugBreakHere = 0;

        // 실제 작업...
    }
);
```

---

## 11.5.4 일반적인 문제와 해결

### 문제 1: Pass가 실행되지 않음

```
┌─────────────────────────────────────────────────────────────────┐
│  증상: Pass Lambda가 호출되지 않음                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  원인 1: 컬링됨 (출력이 사용되지 않음)                          │
│  ───────────────────────────────────────                        │
│  해결:                                                          │
│  • 출력 리소스가 후속 Pass나 추출에서 사용되는지 확인          │
│  • 테스트용으로 NeverCull 플래그 추가                          │
│                                                                 │
│  GraphBuilder.AddPass(                                          │
│      ...,                                                       │
│      ERDGPassFlags::Compute | ERDGPassFlags::NeverCull,        │
│      ...                                                        │
│  );                                                             │
│                                                                 │
│  원인 2: 출력 리소스가 추출되지 않음                            │
│  ───────────────────────────────────────                        │
│  해결:                                                          │
│  • QueueTextureExtraction() 추가                               │
│                                                                 │
│  GraphBuilder.QueueTextureExtraction(OutputTexture, &OutPtr);  │
│                                                                 │
│  진단:                                                          │
│  r.RDG.CullPasses 0  // 컬링 비활성화로 테스트                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 문제 2: 렌더링 결과가 올바르지 않음

```
┌─────────────────────────────────────────────────────────────────┐
│  증상: 텍스처가 예상과 다르게 렌더링됨                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  원인 1: 잘못된 리소스 상태 전환                                │
│  ───────────────────────────────────────                        │
│  진단:                                                          │
│  r.RDG.Debug.Barriers 1  // 배리어 로그 확인                   │
│                                                                 │
│  원인 2: 누락된 의존성                                          │
│  ───────────────────────────────────────                        │
│  진단:                                                          │
│  r.RDG.DumpGraph  // 의존성 그래프 시각화                      │
│                                                                 │
│  원인 3: 잘못된 SRV/UAV 사용                                    │
│  ───────────────────────────────────────                        │
│  확인:                                                          │
│  • 읽기 시 SRV, 쓰기 시 UAV 사용 여부                          │
│  • 포맷이 올바른지                                             │
│                                                                 │
│  원인 4: 렌더 타겟 LoadAction 문제                              │
│  ───────────────────────────────────────                        │
│  확인:                                                          │
│  • EClear: 이전 내용 삭제                                      │
│  • ELoad: 이전 내용 유지                                       │
│  • ENoAction: 내용 미정의 (주의 필요)                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 문제 3: 메모리 사용량 과다

```
┌─────────────────────────────────────────────────────────────────┐
│  진단 방법:                                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. stat RDG로 메모리 통계 확인                                │
│                                                                 │
│  2. r.RDG.Debug.MemoryTracking 1                               │
│     • 리소스별 메모리 사용량 추적                              │
│                                                                 │
│  3. 리소스 크기 검토                                           │
│     • 필요 이상으로 큰 텍스처?                                 │
│     • 불필요한 밉맵?                                           │
│     • 과도한 MSAA 샘플 수?                                     │
│                                                                 │
│  4. 생명주기 확인                                               │
│     • MultiFrame 플래그 남용?                                  │
│     • 외부 리소스 누수?                                        │
│                                                                 │
│  5. 앨리어싱 효율성 확인                                        │
│     • 리소스 크기/포맷 다양성이 앨리어싱 방해                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 문제 4: 비동기 컴퓨트 동기화 이슈

```cpp
// 증상: 비동기 컴퓨트 결과가 불완전하거나 쓰레기 값

// 원인: 잘못된 의존성 또는 리소스 참조 누락

// 해결: AsyncCompute 결과를 사용하는 Pass에서
// 해당 리소스를 명시적으로 참조

// Pass A (AsyncCompute) - 데이터 생성
GraphBuilder.AddPass(
    RDG_EVENT_NAME("AsyncCompute_Generate"),
    ParamsA,
    ERDGPassFlags::AsyncCompute,
    [](FRHICommandList& RHICmdList) { ... }
);

// Pass B (Graphics) - AsyncCompute 결과 사용
FPassBParameters* ParamsB = ...;
ParamsB->AsyncResult = AsyncOutputTexture;  // ← 의존성 생성!

GraphBuilder.AddPass(
    RDG_EVENT_NAME("Graphics_UseAsyncResult"),
    ParamsB,
    ERDGPassFlags::Raster,
    [](FRHICommandList& RHICmdList) { ... }
);
```

---

## 11.5.5 프로파일링

### GPU 프로파일러 통합

```cpp
// RDG_EVENT_NAME이 GPU 프로파일러에 표시됨
// ProfileGPU 콘솔 명령으로 확인

// 콘솔에서
ProfileGPU

// 결과 예시:
// Frame 12345
// - PostProcess (3.2ms)
//   - Bloom (1.5ms)
//     - Downsample (0.8ms)
//     - Blur (0.5ms)
//     - Upsample (0.2ms)
//   - DOF (1.7ms)
```

### RenderDoc 통합

```
┌─────────────────────────────────────────────────────────────────┐
│                    RenderDoc에서 RDG 분석                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. RenderDoc으로 프레임 캡처                                   │
│     • F12 또는 PrintScreen (RenderDoc 오버레이 활성화 시)      │
│                                                                 │
│  2. Event Browser에서 RDG Pass 확인                            │
│     • RDG_EVENT_NAME으로 지정한 이름 표시                      │
│     • 계층 구조 유지 (::로 구분된 이름)                        │
│                                                                 │
│  3. 리소스 검사                                                 │
│     • Texture Viewer에서 중간 결과 확인                        │
│     • RDG 리소스 이름으로 식별                                 │
│     • 각 Pass 전후 상태 비교                                   │
│                                                                 │
│  4. 파이프라인 상태 확인                                        │
│     • 셰이더 바인딩 검증                                       │
│     • 렌더 스테이트 확인                                       │
│     • Draw Call 파라미터 검사                                  │
│                                                                 │
│  5. 타이밍 분석                                                 │
│     • 각 Pass의 GPU 시간                                       │
│     • 배리어 오버헤드                                          │
│     • 병목 지점 식별                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.5.6 검증 체크리스트

### Pass 추가 전 확인사항

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 검증 체크리스트                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  □ 파라미터 구조체가 올바르게 정의됨                           │
│    • SHADER_PARAMETER_RDG_* 매크로 사용                        │
│    • 셰이더와 타입 일치                                        │
│                                                                 │
│  □ 모든 입력 리소스가 유효한 RDG 핸들                          │
│    • nullptr 체크                                              │
│    • 올바른 포맷/크기                                          │
│                                                                 │
│  □ 출력 리소스 크기/포맷이 적절함                              │
│    • 필요한 최소 크기 사용                                     │
│    • 적절한 픽셀 포맷 선택                                     │
│                                                                 │
│  □ Pass 플래그가 올바름                                        │
│    • Raster/Compute/AsyncCompute 중 하나                       │
│    • 필요시 NeverCull, SkipRenderPass 추가                     │
│                                                                 │
│  □ 렌더 타겟 바인딩이 올바름 (Raster Pass)                     │
│    • 올바른 LoadAction 선택                                    │
│    • 슬롯 인덱스 확인                                          │
│                                                                 │
│  □ 셰이더 파라미터 타입이 일치함                               │
│    • CPU 구조체 ↔ HLSL 선언                                   │
│                                                                 │
│  □ Lambda 캡처가 안전함                                        │
│    • 로컬 변수 참조 주의                                       │
│    • 값 복사 또는 파라미터 구조체 사용                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 실행 후 확인사항

```
┌─────────────────────────────────────────────────────────────────┐
│                    실행 검증 체크리스트                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  □ 출력 텍스처가 예상대로 렌더링됨                             │
│    • RenderDoc으로 시각적 확인                                 │
│    • 픽셀 값 샘플링 검사                                       │
│                                                                 │
│  □ GPU 프로파일러에서 Pass 시간 확인                           │
│    • 예상 범위 내인지                                          │
│    • 이상 징후 없는지                                          │
│                                                                 │
│  □ 메모리 사용량이 적절함                                      │
│    • stat RDG 확인                                             │
│    • 임시 리소스 누수 없음                                     │
│                                                                 │
│  □ 콘솔에 경고/오류 없음                                       │
│    • RDG 관련 로그 확인                                        │
│    • 셰이더 컴파일 오류 없음                                   │
│                                                                 │
│  □ 다른 기능과의 상호작용 확인                                 │
│    • 후속 Pass에 영향 없음                                     │
│    • 프레임 간 일관성 유지                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.5.7 총결

### RDG의 핵심 장점

RDG는 유향 비순환 그래프(DAG) 구조를 통해 렌더링 의존성, 리소스 생명주기, 상태 전환을 자동으로 관리합니다. 직접 RHI를 호출하는 것에 비해 다음과 같은 이점을 제공합니다:

| 기능 | 설명 |
|------|------|
| **RenderPass 병합** | BeginRenderPass/EndRenderPass 호출 최소화 |
| **배리어 최적화** | 중복 전환 제거, 배치 처리 |
| **Pass 컬링** | 미사용 Pass 자동 제거 |
| **메모리 앨리어싱** | 생명주기가 겹치지 않는 리소스 메모리 공유 |
| **비동기 컴퓨트** | Graphics/Compute 자동 동기화 |
| **자동 생명주기** | 리소스 할당/해제 자동 관리 |

### 핵심 설계 원칙

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 설계 원칙 요약                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Pass는 실제 사용하는 리소스만 참조                          │
│     • 불필요한 의존성 생성 방지                                │
│     • 컬링/병합 최적화 기회 보존                               │
│                                                                 │
│  2. Pass 내에서 외부 상태 변경 금지                             │
│     • 모든 작업은 Pass Lambda 내에서                           │
│     • 예측 가능한 실행 순서                                    │
│                                                                 │
│  3. 여러 작업을 하나의 Pass에 결합하지 않음                     │
│     • Pass 단위 의존성 분석 유지                               │
│     • 세밀한 컬링 가능                                         │
│                                                                 │
│  4. 유틸리티 함수 활용                                          │
│     • FComputeShaderUtils, FPixelShaderUtils                   │
│     • 검증된 패턴 재사용                                       │
│                                                                 │
│  5. 명확한 이름 규칙 준수                                       │
│     • 디버깅/프로파일링 용이                                   │
│     • 코드 가독성 향상                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 성능 고려사항

- **Pass 실행은 직렬**: CPU 측에서 Pass는 순차 실행되며, GPU 측에서도 큐 제출은 순차
- **주요 최적화는 CPU-GPU 동기화 감소와 메모리 효율화**: RenderPass 병합, 배리어 배치, 앨리어싱
- **비동기 컴퓨트로 GPU 활용률 향상**: Graphics와 Compute 작업 병렬화

### 디버깅 요약

| 상황 | 추천 방법 |
|------|-----------|
| 논리 오류 | 즉시 실행 모드 + 브레이크포인트 |
| 렌더링 결과 확인 | RenderDoc 캡처 |
| 성능 분석 | GPU 프로파일러, `stat RDG` |
| 의존성 문제 | `r.RDG.DumpGraph` |
| 메모리 문제 | `r.RDG.Debug.MemoryTracking` |
| 배리어 문제 | `r.RDG.Debug.Barriers` |
| Pass 컬링 확인 | `r.RDG.CullPasses 0` |

---

## 참고 자료

- [UE 공식 RDG 문서](https://docs.unrealengine.com/5.0/en-US/render-dependency-graph-in-unreal-engine/)
- [GDC 2017 - FrameGraph: Extensible Rendering Architecture in Frostbite](https://www.gdcvault.com/play/1024612/FrameGraph-Extensible-Rendering-Architecture-in)
- [RenderDoc 사용법](https://renderdoc.org/docs/)
- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/15217090.html)
