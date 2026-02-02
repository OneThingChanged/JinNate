# RDG 메커니즘

> 원문: [剖析虚幻渲染体系（11）- RDG](https://www.cnblogs.com/timlly/p/15217090.html)

RDG의 AddPass, Compile, Execute 메커니즘을 상세히 분석합니다.

---

## 11.3.1 RDG 작업 흐름 개요

RDG의 핵심 작업 흐름은 네 단계로 구성됩니다: **Pass 수집 → 컴파일 → 실행 → 정리**. 이 체계는 유향 비순환 그래프(DAG) 구조 기반으로, 렌더링 명령의 지연 실행을 통해 전체 프레임 최적화를 수행합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 전체 작업 흐름                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  1. Pass 수집 (AddPass)                                    ││
│  │     • TRDGLambdaPass 인스턴스 생성                         ││
│  │     • Pass 목록에 추가                                     ││
│  │     • SetupPass()로 리소스 상태 처리                       ││
│  └────────────────────────────────────────────────────────────┘│
│                              ▼                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  2. 컴파일 (Compile)                                       ││
│  │     • 의존성 관계 구축 (생산자/소비자)                     ││
│  │     • Pass 컬링 (Dead Code 제거)                           ││
│  │     • 리소스 상태 병합                                     ││
│  │     • 비동기 컴퓨트 처리 (Fork/Join)                       ││
│  │     • RenderPass 병합                                      ││
│  └────────────────────────────────────────────────────────────┘│
│                              ▼                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  3. 실행 (Execute)                                         ││
│  │     • EpiloguePass 전 sentinel 생성                        ││
│  │     • 컴파일 결과 순서대로 Pass 실행                       ││
│  │     • 각 Pass: Prologue → Body → Epilogue                  ││
│  └────────────────────────────────────────────────────────────┘│
│                              ▼                                  │
│  ┌────────────────────────────────────────────────────────────┐│
│  │  4. 정리 (Cleanup)                                         ││
│  │     • 텍스처/버퍼 추출 처리                                ││
│  │     • 모든 메모리 해제                                     ││
│  │     • 데이터 구조 리셋                                     ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.3.2 AddPass 메커니즘

### AddPass 함수 시그니처

```cpp
template<typename TParameterStruct, typename TLambda>
void FRDGBuilder::AddPass(
    FRDGEventName&& Name,           // Pass 이름 (GPU 프로파일러 표시)
    TParameterStruct* ParameterStruct, // 셰이더 파라미터 구조체
    ERDGPassFlags Flags,            // Pass 타입 플래그
    TLambda&& Lambda                // 실행 Lambda 함수
)
```

### AddPass 내부 구현

`AddPass` 호출 시 다음 작업이 수행됩니다:

```cpp
template<typename TParameterStruct, typename TLambda>
void FRDGBuilder::AddPass(...)
{
    // 1. TRDGLambdaPass 인스턴스 생성
    FRDGPassHandle PassHandle(Passes.Num());

    TRDGLambdaPass<TParameterStruct, TLambda>* Pass =
        Allocator.Alloc<TRDGLambdaPass<TParameterStruct, TLambda>>(
            Name,
            PassHandle,
            ParameterStruct,
            Flags,
            MoveTemp(Lambda)
        );

    // 2. Pass 목록에 추가
    Passes.Add(Pass);

    // 3. SetupPass 호출 - 리소스 상태 처리
    SetupPass(Pass);
}
```

### SetupPass 함수

`SetupPass`는 Pass가 사용하는 모든 리소스의 상태를 처리합니다:

```cpp
void FRDGBuilder::SetupPass(FRDGPass* Pass)
{
    // 1. 파라미터 구조체에서 리소스 참조 추출
    const FShaderParametersMetadata* Metadata = Pass->ParameterMetadata;

    // 2. 텍스처 처리
    for (각 텍스처 파라미터)
    {
        FRDGTextureRef Texture = 파라미터에서 추출;

        // 참조 카운트 증가
        Texture->ReferenceCount++;

        // 첫 사용이면 FirstPass 설정
        if (Texture->FirstPass.IsNull())
        {
            Texture->FirstPass = Pass->Handle;
        }

        // LastPass 업데이트
        Texture->LastPass = Pass->Handle;

        // 접근 권한 기록 (SRV, UAV, RenderTarget 등)
        Pass->TextureStates.Add(Texture, 접근 상태);
    }

    // 3. 버퍼 처리 (텍스처와 유사)
    for (각 버퍼 파라미터)
    {
        // ... 동일한 처리
    }

    // 4. 렌더 타겟 바인딩 처리 (Raster Pass)
    if (Pass->Flags & ERDGPassFlags::Raster)
    {
        // RenderTarget 슬롯에서 텍스처 추출 및 상태 기록
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    SetupPass 처리 흐름                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  입력: FRDGPass* Pass                                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 파라미터 구조체 분석                                 │   │
│  │     └── SHADER_PARAMETER_RDG_* 매크로 파싱              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  2. 각 리소스에 대해:                                    │   │
│  │     ├── ReferenceCount++                                │   │
│  │     ├── FirstPass 설정 (첫 사용 시)                     │   │
│  │     ├── LastPass 업데이트                               │   │
│  │     └── Pass->TextureStates/BufferStates에 접근 상태 기록│   │
│  └─────────────────────────────────────────────────────────┘   │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  3. 결과:                                                │   │
│  │     • 리소스 생명주기 범위 파악 (First~Last Pass)       │   │
│  │     • Pass별 리소스 접근 패턴 기록                      │   │
│  │     • 컴파일 단계 의존성 분석의 기초 데이터             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.3.3 컴파일 단계 (Compile)

컴파일 단계는 RDG에서 가장 복잡한 과정으로, 여러 서브 단계로 구성됩니다.

### Compile 함수 구조

```cpp
void FRDGBuilder::Compile()
{
    // 1. 의존성 관계 구축
    SetupPassDependencies();

    // 2. Pass 컬링 최적화
    SetupPassCulling();

    // 3. 리소스 상태 전환 설정
    SetupResourceTransitions();

    // 4. 비동기 컴퓨트 처리
    SetupAsyncComputePasses();

    // 5. RenderPass 병합
    MergeRasterPasses();

    // 6. 배리어 수집
    CollectPassBarriers();
}
```

### 11.3.3.1 의존성 관계 구축 (SetupPassDependencies)

모든 Pass를 순회하며 각 리소스의 생산자(Producer)와 소비자(Consumer)를 추적합니다.

```cpp
void FRDGBuilder::SetupPassDependencies()
{
    // 리소스별 마지막 쓰기 Pass 추적
    TMap<FRDGResource*, FRDGPassHandle> LastWritePass;

    for (FRDGPass* Pass : Passes)
    {
        // 텍스처 의존성 처리
        for (auto& [Texture, State] : Pass->TextureStates)
        {
            if (State.IsWriteAccess())  // UAV, RenderTarget
            {
                // 이전 쓰기 Pass가 있으면 생산자로 추가
                if (FRDGPassHandle* Producer = LastWritePass.Find(Texture))
                {
                    Pass->Producers.Add(*Producer);
                }

                // 현재 Pass를 새 쓰기자로 등록
                LastWritePass.FindOrAdd(Texture) = Pass->Handle;
            }
            else  // SRV (읽기)
            {
                // 마지막 쓰기 Pass가 생산자
                if (FRDGPassHandle* Producer = LastWritePass.Find(Texture))
                {
                    Pass->Producers.Add(*Producer);
                }
            }
        }

        // 버퍼도 동일하게 처리
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    의존성 관계 예시                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Pass A: Texture1 Write (RenderTarget)                         │
│       │                                                         │
│       ▼  Texture1 의존성                                        │
│  Pass B: Texture1 Read (SRV), Texture2 Write (UAV)             │
│       │                                                         │
│       ▼  Texture2 의존성                                        │
│  Pass C: Texture2 Read (SRV)                                   │
│                                                                 │
│  결과:                                                          │
│  • Pass B.Producers = [Pass A]                                 │
│  • Pass C.Producers = [Pass B]                                 │
│                                                                 │
│  의존성 규칙:                                                   │
│  • Write → Read: 명시적 의존성 (배리어 필요)                   │
│  • Write → Write: 순서 의존성 (배리어 필요)                    │
│  • Read → Read: 의존성 없음 (병렬 가능)                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 11.3.3.2 Pass 컬링 (SetupPassCulling)

출력에 영향을 주지 않는 "Dead Code" Pass를 식별하고 제거합니다.

```cpp
void FRDGBuilder::SetupPassCulling()
{
    // 1. 모든 Pass를 컬링 대상으로 초기화
    for (FRDGPass* Pass : Passes)
    {
        Pass->bCulled = true;
    }

    // 2. 외부로 추출되는 리소스의 생산 Pass 마킹
    for (auto& Extraction : TextureExtractions)
    {
        FRDGTextureRef Texture = Extraction.Texture;
        MarkPassAsRequired(Passes[Texture->LastPass.GetIndex()]);
    }

    // 3. NeverCull 플래그가 있는 Pass 마킹
    for (FRDGPass* Pass : Passes)
    {
        if (Pass->Flags & ERDGPassFlags::NeverCull)
        {
            MarkPassAsRequired(Pass);
        }
    }
}

void FRDGBuilder::MarkPassAsRequired(FRDGPass* Pass)
{
    if (!Pass->bCulled)
        return;  // 이미 마킹됨

    Pass->bCulled = false;

    // DFS로 생산자 체인 역추적
    for (FRDGPassHandle ProducerHandle : Pass->Producers)
    {
        MarkPassAsRequired(Passes[ProducerHandle.GetIndex()]);
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 컬링 결정 트리                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                       Pass 분석                                 │
│                           │                                     │
│              ┌────────────┴────────────┐                       │
│              ▼                         ▼                       │
│        NeverCull?                출력이 추출됨?                 │
│           │                           │                        │
│     ┌─────┴─────┐               ┌─────┴─────┐                  │
│     ▼           ▼               ▼           ▼                  │
│    Yes         No              Yes         No                  │
│     │           │               │           │                  │
│     ▼           │               ▼           │                  │
│  [필수]        │            [필수]         │                  │
│                │                           │                  │
│                └───────────┬───────────────┘                  │
│                            ▼                                   │
│                     생산자가 필수?                              │
│                            │                                   │
│                      ┌─────┴─────┐                             │
│                      ▼           ▼                             │
│                     Yes         No                             │
│                      │           │                             │
│                      ▼           ▼                             │
│                   [필수]      [컬링]                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 11.3.3.3 리소스 상태 전환 (SetupResourceTransitions)

각 Pass의 리소스 접근 상태를 분석하여 필요한 상태 전환을 식별합니다.

```cpp
void FRDGBuilder::SetupResourceTransitions()
{
    for (FRDGPass* Pass : Passes)
    {
        if (Pass->bCulled)
            continue;

        for (auto& [Texture, DesiredState] : Pass->TextureStates)
        {
            // 현재 상태 가져오기
            FRDGTextureState& CurrentState = Texture->CurrentState;

            // 상태 전환 필요 여부 확인
            if (NeedsTransition(CurrentState, DesiredState))
            {
                // 병합 가능한 상태인지 확인
                if (CanMergeStates(CurrentState, DesiredState))
                {
                    // 상태 병합 (Read + Read = Read)
                    CurrentState = MergeStates(CurrentState, DesiredState);
                }
                else
                {
                    // 새 전환점 생성
                    Pass->TransitionsToBegin.Add(Texture, DesiredState);
                    CurrentState = DesiredState;
                }
            }
        }
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    리소스 상태 전환 예시                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Pass 1: Texture → RenderTarget (Write)                        │
│       │                                                         │
│       ▼  전환 필요: RT → SRV                                   │
│  Pass 2: Texture → ShaderResource (Read)                       │
│       │                                                         │
│       │  전환 불필요: SRV → SRV (Read + Read)                  │
│  Pass 3: Texture → ShaderResource (Read)                       │
│       │                                                         │
│       ▼  전환 필요: SRV → UAV                                  │
│  Pass 4: Texture → UnorderedAccess (Write)                     │
│                                                                 │
│  최적화 결과:                                                   │
│  • Pass 1 → Pass 2: 배리어 (RT → SRV)                         │
│  • Pass 2 → Pass 3: 배리어 없음 (병합됨)                      │
│  • Pass 3 → Pass 4: 배리어 (SRV → UAV)                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 11.3.3.4 비동기 컴퓨트 처리 (SetupAsyncComputePasses)

Graphics와 AsyncCompute 두 파이프라인 간의 경계를 식별하고 동기화 포인트를 설정합니다.

```cpp
void FRDGBuilder::SetupAsyncComputePasses()
{
    // 1. 분기점(Fork) 찾기: Graphics → AsyncCompute 전환
    // 2. 합류점(Join) 찾기: AsyncCompute → Graphics 전환

    for (각 AsyncCompute 영역)
    {
        // Fork Pass: AsyncCompute로 전환하기 전 마지막 Graphics Pass
        FRDGPass* ForkPass = FindForkPass(AsyncComputeRegion);
        ForkPass->bAsyncComputeBegin = true;

        // Join Pass: AsyncCompute 완료 후 첫 Graphics Pass
        FRDGPass* JoinPass = FindJoinPass(AsyncComputeRegion);
        JoinPass->bAsyncComputeEnd = true;

        // 비동기 영역 내 리소스 생명주기 연장
        ExtendResourceLifetimes(AsyncComputeRegion);
    }
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    비동기 컴퓨트 Fork-Join 모델                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Graphics Queue              Async Compute Queue               │
│       │                                                         │
│  ┌────┴────┐                                                   │
│  │ Pass A  │                                                   │
│  │(Graphics)│                                                   │
│  └────┬────┘                                                   │
│       │                                                         │
│       ├─────────── Fork ───────────▶ ┌────────────┐            │
│       │           (Fence)             │  Pass B    │            │
│       │                               │(AsyncComp) │            │
│       │                               └─────┬──────┘            │
│  ┌────┴────┐                               │                   │
│  │ Pass C  │  ← 병렬 실행                  │                   │
│  │(Graphics)│                               │                   │
│  └────┬────┘                               │                   │
│       │                                     │                   │
│       │◀────────── Join ──────────────────┘                   │
│       │           (Fence)                                       │
│  ┌────┴────┐                                                   │
│  │ Pass D  │  ← Pass B 결과 사용                               │
│  │(Graphics)│                                                   │
│  └─────────┘                                                   │
│                                                                 │
│  Fork: Graphics 큐에서 Fence 신호 발생                         │
│  Join: AsyncCompute 완료 대기 후 Graphics 진행                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 11.3.3.5 RenderPass 병합 (MergeRasterPasses)

동일한 렌더 타겟 구성을 사용하는 연속 래스터 Pass를 하나의 RHI RenderPass로 병합합니다.

```cpp
void FRDGBuilder::MergeRasterPasses()
{
    FRDGPass* CurrentMergeHead = nullptr;
    FRenderTargetBindingSlots CurrentRT;

    for (FRDGPass* Pass : Passes)
    {
        if (Pass->bCulled)
            continue;

        if (!(Pass->Flags & ERDGPassFlags::Raster))
        {
            // Compute/Copy Pass면 병합 종료
            CurrentMergeHead = nullptr;
            continue;
        }

        FRenderTargetBindingSlots PassRT = Pass->GetRenderTargets();

        if (CurrentMergeHead && CanMerge(CurrentRT, PassRT))
        {
            // 동일 RT → 병합
            Pass->MergeHead = CurrentMergeHead;
        }
        else
        {
            // 새 병합 그룹 시작
            CurrentMergeHead = Pass;
            CurrentRT = PassRT;
        }
    }
}
```

---

## 11.3.4 실행 단계 (Execute)

### Execute 함수 구조

```cpp
void FRDGBuilder::Execute()
{
    // 1. 컴파일 (아직 안 했으면)
    if (!bCompiled)
    {
        Compile();
    }

    // 2. EpiloguePass 전 sentinel 생성 (경계 처리 단순화)
    FRDGPass* SentinelPass = CreateSentinelPass();

    // 3. Pass 순회 실행
    for (FRDGPass* Pass : Passes)
    {
        if (Pass->bCulled)
            continue;

        // 3.1 Prologue: 전위 처리
        ExecutePassPrologue(Pass);

        // 3.2 Body: Lambda 실행
        Pass->Execute(RHICmdList);

        // 3.3 Epilogue: 후위 처리
        ExecutePassEpilogue(Pass);
    }

    // 4. 리소스 추출 처리
    ProcessExtractions();

    // 5. 정리
    Cleanup();
}
```

### Pass 실행 구조 (Prologue / Body / Epilogue)

```cpp
void FRDGBuilder::ExecutePassPrologue(FRDGPass* Pass)
{
    // 1. 전위 배리어 시작
    if (Pass->PrologueBarriersToBegin)
    {
        BeginResourceTransitions(Pass->PrologueBarriersToBegin);
    }

    // 2. 전위 배리어 종료
    if (Pass->PrologueBarriersToEnd)
    {
        EndResourceTransitions(Pass->PrologueBarriersToEnd);
    }

    // 3. RenderPass 시작 (Raster Pass이고 병합 헤드일 때)
    if ((Pass->Flags & ERDGPassFlags::Raster) &&
        Pass->MergeHead == Pass)
    {
        BeginRenderPass(Pass);
    }

    // 4. AsyncCompute Fork (필요시)
    if (Pass->bAsyncComputeBegin)
    {
        SignalAsyncComputeFence();
    }
}

void FRDGBuilder::ExecutePassEpilogue(FRDGPass* Pass)
{
    // 1. RenderPass 종료 (병합 그룹의 마지막 Pass일 때)
    if ((Pass->Flags & ERDGPassFlags::Raster) &&
        IsLastInMergeGroup(Pass))
    {
        EndRenderPass();
    }

    // 2. AsyncCompute Join (필요시)
    if (Pass->bAsyncComputeEnd)
    {
        WaitForAsyncComputeFence();
    }

    // 3. 후위 배리어
    if (Pass->EpilogueBarriersToBegin)
    {
        BeginResourceTransitions(Pass->EpilogueBarriersToBegin);
    }
    if (Pass->EpilogueBarriersToEnd)
    {
        EndResourceTransitions(Pass->EpilogueBarriersToEnd);
    }

    // 4. 리소스 해제 (마지막 사용 Pass일 때)
    ReleaseUnusedResources(Pass);
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 실행 구조                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────── Pass N ───────────────┐                      │
│  │                                       │                      │
│  │  Prologue:                           │                      │
│  │  ├── BeginBarrierBatch()             │  ← 전위 배리어 시작  │
│  │  ├── EndBarrierBatch()               │  ← 전위 배리어 종료  │
│  │  ├── BeginRenderPass() (Raster)      │  ← RT 설정          │
│  │  └── SignalFence() (Fork)            │  ← AsyncCompute 분기 │
│  │                                       │                      │
│  │  Body:                               │                      │
│  │  └── Pass->Execute(RHICmdList)       │  ← 사용자 Lambda    │
│  │                                       │                      │
│  │  Epilogue:                           │                      │
│  │  ├── EndRenderPass() (Raster)        │  ← RT 해제          │
│  │  ├── WaitFence() (Join)              │  ← AsyncCompute 합류 │
│  │  ├── BeginBarrierBatch()             │  ← 후위 배리어 시작  │
│  │  ├── EndBarrierBatch()               │  ← 후위 배리어 종료  │
│  │  └── ReleaseResources()              │  ← 미사용 리소스 해제│
│  │                                       │                      │
│  └───────────────────────────────────────┘                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.3.5 배리어 메커니즘

### FRDGBarrierBatch 구조

배리어는 Begin/End 쌍으로 관리되어 정밀한 타이밍 제어가 가능합니다.

```cpp
// 배리어 시작 - 전환할 리소스 정보 수집
class FRDGBarrierBatchBegin
{
    TArray<FRHITransitionInfo> Transitions;  // 전환 정보 목록
    ERHIPipeline Pipeline;                    // 대상 파이프라인

    void AddTransition(FRDGResource* Resource,
                       ERHIAccess Before,
                       ERHIAccess After);
};

// 배리어 종료 - 실제 전환 수행
class FRDGBarrierBatchEnd
{
    FRDGBarrierBatchBegin* Begin;  // 연결된 Begin
    ERHIPipeline Pipeline;          // 대상 파이프라인

    void Submit(FRHICommandList& RHICmdList);
};
```

### 배리어 배치 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                    배리어 배치 최적화                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  비최적화:                                                      │
│  ┌────┐ Barrier ┌────┐ Barrier ┌────┐ Barrier ┌────┐          │
│  │ P1 │────────▶│ P2 │────────▶│ P3 │────────▶│ P4 │          │
│  └────┘  Tex1   └────┘  Tex2   └────┘  Tex3   └────┘          │
│                                                                 │
│  최적화:                                                        │
│  ┌────┐          ┌────┐          ┌────┐          ┌────┐        │
│  │ P1 │─────────▶│ P2 │─────────▶│ P3 │─────────▶│ P4 │        │
│  └────┘          └────┘          └────┘          └────┘        │
│       └─────────────────────────────────────────────┘          │
│           Batched Barrier (Tex1 + Tex2 + Tex3)                 │
│                                                                 │
│  최적화 원리:                                                   │
│  • 연속된 배리어를 하나의 API 호출로 병합                      │
│  • Read → Read 전환 완전 생략                                  │
│  • 호환 가능한 상태 전환 병합                                   │
│  • 최소 동기화 포인트로 파이프라인 효율 극대화                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.3.6 서브리소스 상태 추적

### FRDGSubresourceState

밉맵, 배열 슬라이스 등 서브리소스 단위의 세밀한 상태 추적을 지원합니다.

```cpp
struct FRDGSubresourceState
{
    // 접근 권한
    ERHIAccess Access;

    // 소속 파이프라인 (Graphics / AsyncCompute)
    ERHIPipeline Pipeline;

    // 마지막 사용 Pass
    FRDGPassHandle LastPass;

    // 상태 플래그
    uint8 bWritable : 1;
    uint8 bCompressed : 1;
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    서브리소스별 상태 추적                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Texture (2048x2048, 6 Mips)                                   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ Mip 0: 2048x2048                                       │    │
│  │        State: SRV_Graphics                             │    │
│  ├────────────────────────────────────────────────────────┤    │
│  │ Mip 1: 1024x1024                                       │    │
│  │        State: UAV_Compute   ← 다른 상태 가능          │    │
│  ├────────────────────────────────────────────────────────┤    │
│  │ Mip 2: 512x512                                         │    │
│  │        State: SRV_Graphics                             │    │
│  ├────────────────────────────────────────────────────────┤    │
│  │ Mip 3-5: ...                                           │    │
│  │        State: Unknown (미사용)                         │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  장점:                                                          │
│  • 밉맵 생성 시 각 레벨 독립적 전환                            │
│  • 동일 텍스처의 다른 밉을 동시에 다른 용도로 사용             │
│  • 불필요한 전체 텍스처 배리어 방지                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11.3.7 리소스 생명주기 관리

### 자동 할당 및 해제

```
┌─────────────────────────────────────────────────────────────────┐
│                    리소스 생명주기                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  시간 →   Pass1    Pass2    Pass3    Pass4    Pass5            │
│            │        │        │        │        │               │
│                                                                 │
│  Tex A:    ████████████████                                    │
│           ↑생성    사용      ↑마지막사용                        │
│           │                  └─ 풀로 반환                       │
│           │                                                     │
│  Tex B:             ███████████████████████                    │
│                    ↑생성     사용      사용    ↑마지막          │
│                    │                          └─ 풀로 반환     │
│                    │                                            │
│  Tex C:                      █████████                         │
│                             ↑생성 ↑마지막                       │
│                             │     └─ 풀로 반환                 │
│                             │                                   │
│                             └─ Tex A가 반환한 메모리 재사용!   │
│                                                                 │
│  핵심:                                                          │
│  • FirstPass 실행 시 풀에서 할당                               │
│  • LastPass 실행 후 즉시 풀로 반환                             │
│  • 생명주기가 겹치지 않으면 메모리 앨리어싱                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

[RDG 개발 가이드](04-rdg-development.md)에서 실제 사용법과 코드 예제를 알아봅니다.
