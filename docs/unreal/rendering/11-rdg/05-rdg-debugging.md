# RDG 디버깅

RDG 디버깅 방법, 즉시 실행 모드, 일반적인 문제 해결 방법을 설명합니다.

---

## 즉시 실행 모드

RDG의 지연 실행 특성으로 디버깅이 어려울 수 있습니다. 즉시 실행 모드는 이 문제를 해결합니다.

### 활성화 방법

```cpp
// 방법 1: 명령줄 인자
UE4Editor.exe -rdgimmediate

// 방법 2: 콘솔 변수
r.RDG.ImmediateMode=1

// 방법 3: 코드에서 설정
static IConsoleVariable* CVarRDGImmediate =
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.RDG.ImmediateMode"));
CVarRDGImmediate->Set(1);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    일반 모드 vs 즉시 실행 모드                   │
├────────────────────────────┬────────────────────────────────────┤
│         일반 모드          │        즉시 실행 모드              │
├────────────────────────────┼────────────────────────────────────┤
│ AddPass() → 큐에 저장      │ AddPass() → 즉시 실행             │
│ Execute()에서 일괄 실행    │ Execute()는 정리만 수행           │
│ 전체 프레임 최적화         │ 최적화 없음                       │
│ 디버깅 어려움              │ 브레이크포인트에서 즉시 확인      │
│ 성능 최적                  │ 성능 저하 (디버그용)              │
└────────────────────────────┴────────────────────────────────────┘
```

---

## 디버그 콘솔 명령

### RDG 관련 콘솔 변수

```cpp
// RDG 유효성 검사 레벨
r.RDG.Debug=0      // 0: 없음, 1: 기본, 2: 상세

// 리소스 추적
r.RDG.Debug.ResourceLifetime=1

// Pass 실행 로깅
r.RDG.Debug.PassExecution=1

// 배리어 디버깅
r.RDG.Debug.Barriers=1

// 메모리 사용량 추적
r.RDG.Debug.MemoryTracking=1

// 즉시 실행 모드
r.RDG.ImmediateMode=1

// 컬링 비활성화 (모든 Pass 실행)
r.RDG.CullPasses=0
```

### 유용한 디버그 명령

```cpp
// RDG 통계 표시
stat RDG

// RDG 리소스 덤프
r.RDG.DumpResources

// RDG 그래프 시각화 (GraphViz 형식)
r.RDG.DumpGraph
```

---

## 디버깅 기법

### 1. 이벤트 이름 활용

```cpp
// GPU 프로파일러에서 식별 가능한 이름 사용
GraphBuilder.AddPass(
    RDG_EVENT_NAME("MyFeature::BlurHorizontal"),  // 명확한 계층 구조
    Parameters,
    ERDGPassFlags::Raster,
    Lambda
);

// 동적 이름
GraphBuilder.AddPass(
    RDG_EVENT_NAME("ProcessLight_%d", LightIndex),
    ...
);
```

### 2. 리소스 이름 규칙

```cpp
// 기능_용도_세부사항 형식
FRDGTextureRef BlurTemp = GraphBuilder.CreateTexture(
    Desc,
    TEXT("Blur_Horizontal_Temp")  // 명확한 이름
);

// 나쁜 예
FRDGTextureRef Tex = GraphBuilder.CreateTexture(Desc, TEXT("Temp"));  // 불명확
```

### 3. 브레이크포인트 전략

```cpp
GraphBuilder.AddPass(
    RDG_EVENT_NAME("DebugPass"),
    Parameters,
    ERDGPassFlags::Compute | ERDGPassFlags::NeverCull,  // 컬링 방지
    [](FRHICommandList& RHICmdList)
    {
        // 여기에 브레이크포인트 설정 (즉시 실행 모드에서)
        int DebugBreak = 0;  // ← 브레이크포인트
    }
);
```

---

## 일반적인 문제와 해결

### 문제 1: 리소스가 예상과 다른 상태

```
┌─────────────────────────────────────────────────────────────────┐
│  증상: 텍스처가 올바르게 렌더링되지 않음                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  원인:                                                          │
│  • 잘못된 리소스 상태 전환                                      │
│  • 누락된 의존성                                                │
│                                                                 │
│  해결:                                                          │
│  1. r.RDG.Debug.Barriers=1 로 배리어 확인                      │
│  2. 의존성 그래프 검토 (r.RDG.DumpGraph)                       │
│  3. 올바른 SRV/UAV 사용 확인                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 문제 2: Pass가 실행되지 않음

```cpp
// 증상: Pass Lambda가 호출되지 않음

// 원인 1: 컬링됨 (출력 미사용)
// 해결: NeverCull 플래그 추가 또는 출력 확인
GraphBuilder.AddPass(
    ...,
    ERDGPassFlags::Compute | ERDGPassFlags::NeverCull,  // 컬링 방지
    ...
);

// 원인 2: 출력 리소스가 추출되지 않음
// 해결: QueueTextureExtraction 추가
GraphBuilder.QueueTextureExtraction(OutputTexture, &ExtractedRT);
```

### 문제 3: 메모리 사용량 과다

```
┌─────────────────────────────────────────────────────────────────┐
│  진단 방법:                                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. stat RDG로 메모리 통계 확인                                │
│                                                                 │
│  2. 리소스 크기 검토                                           │
│     • 필요 이상으로 큰 텍스처?                                 │
│     • 불필요한 밉맵?                                           │
│                                                                 │
│  3. 생명주기 확인                                               │
│     • MultiFrame 플래그 남용?                                  │
│     • 외부 리소스 누수?                                        │
│                                                                 │
│  4. 풀링 효율성                                                │
│     • r.RDG.Debug.MemoryTracking=1                            │
│     • 리소스 앨리어싱 확인                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 문제 4: 비동기 컴퓨트 동기화 이슈

```cpp
// 증상: 비동기 컴퓨트 결과가 불완전

// 원인: 잘못된 동기화 또는 리소스 의존성 누락

// 해결: 명시적 의존성 확인
// Pass A (Graphics) → AsyncCompute Pass → Pass B (Graphics)

// Pass B가 AsyncCompute 결과를 사용하는지 확인
FPassBParameters* PassB_Params = ...;
PassB_Params->AsyncComputeResult = AsyncComputeOutput;  // 의존성 생성
```

---

## 프로파일링

### GPU 프로파일러 통합

```cpp
// RDG_EVENT_NAME이 GPU 프로파일러에 표시됨
// ProfileGPU 명령으로 확인

// 콘솔에서
ProfileGPU

// 결과 예시:
// - MyFeature (2.5ms)
//   - BlurHorizontal (1.2ms)
//   - BlurVertical (1.3ms)
```

### RenderDoc 통합

```
┌─────────────────────────────────────────────────────────────────┐
│                    RenderDoc에서 RDG 분석                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. RenderDoc으로 프레임 캡처                                   │
│                                                                 │
│  2. Event Browser에서 RDG Pass 확인                            │
│     • RDG_EVENT_NAME으로 지정한 이름 표시                      │
│     • 계층 구조 유지                                           │
│                                                                 │
│  3. 리소스 검사                                                 │
│     • Texture Viewer에서 중간 결과 확인                        │
│     • 리소스 이름으로 식별                                     │
│                                                                 │
│  4. 파이프라인 상태 확인                                        │
│     • 셰이더 바인딩                                            │
│     • 렌더 스테이트                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 검증 체크리스트

### Pass 추가 전 확인사항

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 검증 체크리스트                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  □ 파라미터 구조체가 올바르게 정의됨                           │
│  □ 모든 입력 리소스가 유효한 RDG 핸들                          │
│  □ 출력 리소스 크기/포맷이 적절함                              │
│  □ Pass 플래그가 올바름 (Raster/Compute/AsyncCompute)          │
│  □ 렌더 타겟 바인딩이 올바름 (Raster Pass)                     │
│  □ 셰이더 파라미터 타입이 일치함                               │
│  □ Lambda 캡처가 안전함 (로컬 변수 참조 주의)                  │
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
│  □ GPU 프로파일러에서 Pass 시간 확인                           │
│  □ 메모리 사용량이 적절함                                      │
│  □ 콘솔에 경고/오류 없음                                       │
│  □ 다른 기능과의 상호작용 확인                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 요약

| 상황 | 추천 도구/방법 |
|------|----------------|
| 논리 오류 디버깅 | 즉시 실행 모드 + 브레이크포인트 |
| 렌더링 결과 확인 | RenderDoc 캡처 |
| 성능 분석 | GPU 프로파일러, stat RDG |
| 의존성 문제 | r.RDG.DumpGraph |
| 메모리 문제 | r.RDG.Debug.MemoryTracking |
| 배리어 문제 | r.RDG.Debug.Barriers |

---

## 참고 자료

- [UE 공식 RDG 문서](https://docs.unrealengine.com/5.0/en-US/render-dependency-graph-in-unreal-engine/)
- [RenderDoc 사용법](https://renderdoc.org/docs/)
- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/15217090.html)
