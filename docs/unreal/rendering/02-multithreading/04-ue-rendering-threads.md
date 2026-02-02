# 04. UE 렌더링 스레드 아키텍처

> Game/Render/RHI 스레드 분리와 프레임 파이프라이닝

---

## 목차

1. [스레드 분리 철학](#1-스레드-분리-철학)
2. [3-스레드 모델](#2-3-스레드-모델)
3. [프레임 파이프라이닝](#3-프레임-파이프라이닝)
4. [명령 큐잉](#4-명령-큐잉)
5. [동기화 지점](#5-동기화-지점)
6. [디버깅과 프로파일링](#6-디버깅과-프로파일링)

---

## 1. 스레드 분리 철학 {#1-스레드-분리-철학}

### 1.1 왜 스레드를 분리하는가?

> "렌더링 스레드는 GPU 실행을 게임 로직으로부터 분리하여, 물리/애니메이션/로직이 GPU가 이전 프레임의 명령을 소비하는 동안 진행할 수 있게 합니다."

```
┌─────────────────────────────────────────────────────────────────┐
│                    단일 스레드 (비효율)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame N:  [Game Logic] [Render Setup] [GPU Wait] [GPU Execute] │
│                                                                 │
│  Frame N+1:              대기                    [Game Logic]...│
│                                                                 │
│  CPU 활용률: ~25%                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    멀티 스레드 (효율적)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game:   [Frame N+2] [Frame N+3] [Frame N+4] ...                │
│  Render:        [Frame N+1] [Frame N+2] [Frame N+3] ...         │
│  GPU:                  [Frame N] [Frame N+1] [Frame N+2] ...    │
│                                                                 │
│  CPU 활용률: ~75%+                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 분리의 이점

| 이점 | 설명 |
|------|------|
| **CPU/GPU 병렬화** | GPU 실행 중 CPU 작업 진행 |
| **지연 시간 은폐** | API 호출 오버헤드 숨김 |
| **안정적 프레임레이트** | 프레임 간 부하 분산 |
| **확장성** | 코어 수에 따른 성능 향상 |

---

## 2. 3-스레드 모델 {#2-3-스레드-모델}

### 2.1 역할 분담

| 스레드 | 역할 | 핵심 작업 |
|--------|------|----------|
| **Game Thread** | 게임 로직 | 틱, 입력, 물리, AI |
| **Render Thread** | 렌더링 로직 | 가시성, 드로우 명령 생성 |
| **RHI Thread** | GPU 통신 | API 호출, 명령 제출 |

```cpp
// 스레드별 Named Thread ID
namespace ENamedThreads
{
    enum Type
    {
        GameThread,
        ActualRenderingThread,  // Render Thread
        RHIThread,

        // 워커 스레드들
        AnyThread,
        AnyHiPriThreadNormalTask,
        AnyBackgroundThreadNormalTask,
        // ...
    };
}
```

### 2.2 스레드 생성

```cpp
// 엔진 초기화 시 스레드 생성
void FEngineLoop::PreInit()
{
    // Render Thread 생성
    if (GIsThreadedRendering)
    {
        StartRenderingThread();
    }

    // RHI Thread 생성 (플랫폼/설정에 따라)
    if (GRHIThread_InternalUseOnly)
    {
        StartRHIThread();
    }
}

// Render Thread 시작
void StartRenderingThread()
{
    FRunnableThread* Thread = FRunnableThread::Create(
        new FRenderingThread(),
        TEXT("RenderThread"),
        0,
        TPri_AboveNormal,
        FPlatformAffinity::GetRenderingThreadMask()
    );

    GIsRunningRenderingThread = true;
}
```

### 2.3 데이터 소유권

```cpp
// Game Thread 소유 데이터
class AActor
{
    // 게임 스레드에서만 접근
    FTransform ActorTransform;
    UActorComponent* Components[];
};

// Render Thread 소유 데이터
class FPrimitiveSceneProxy
{
    // 렌더 스레드에서만 접근
    FMatrix LocalToWorld;
    FBoxSphereBounds Bounds;
};

// Game → Render 데이터 전달
void UPrimitiveComponent::SendRenderTransform_Concurrent()
{
    FMatrix Transform = GetComponentTransform().ToMatrixWithScale();

    ENQUEUE_RENDER_COMMAND(UpdateTransform)(
        [Proxy = SceneProxy, Transform](FRHICommandListImmediate&)
        {
            Proxy->SetTransform_RenderThread(Transform);
        });
}
```

---

## 3. 프레임 파이프라이닝 {#3-프레임-파이프라이닝}

### 3.1 Triple Buffering 개념

```
시간 ─────────────────────────────────────────→

Game Thread:   [Frame N+2] [Frame N+3] [Frame N+4]
                   │
                   ▼ 렌더 명령 큐잉
Render Thread:     │    [Frame N+1] [Frame N+2] [Frame N+3]
                   │        │
                   │        ▼ RHI 명령 큐잉
RHI Thread:        │        │    [Frame N Submit] [Frame N+1 Submit]
                   │        │          │
                   │        │          ▼
GPU:               │        │          │    [Frame N-1] [Frame N]
```

### 3.2 프레임 인덱스 추적

```cpp
// 각 스레드가 처리 중인 프레임
struct FFrameState
{
    uint32 GameThreadFrameNumber;      // Frame N
    uint32 RenderThreadFrameNumber;    // Frame N-1
    uint32 RHIThreadFrameNumber;       // Frame N-2
};

// 프레임 시작
void FEngineLoop::Tick()
{
    // 게임 스레드 프레임 증가
    GFrameCounter++;

    // 렌더 스레드에 프레임 시작 알림
    ENQUEUE_RENDER_COMMAND(BeginFrame)(
        [FrameNumber = GFrameCounter](FRHICommandListImmediate& RHICmdList)
        {
            GRenderThreadFrameNumber = FrameNumber;
            RHICmdList.BeginFrame();
        });

    // 게임 로직 실행
    GEngine->Tick(DeltaTime);

    // 렌더 스레드에 프레임 종료 알림
    ENQUEUE_RENDER_COMMAND(EndFrame)(...);
}
```

### 3.3 프레임 지연 (Latency)

| 구성 | 입력-출력 지연 | 메모리 사용 |
|------|---------------|------------|
| **Single Thread** | 1 프레임 | 1x |
| **Game + Render** | 2 프레임 | 2x |
| **Game + Render + RHI** | 3 프레임 | 3x |

```cpp
// 최대 프레임 지연 설정
// r.OneFrameThreadLag=0: 완전 동기화 (저지연, 저성능)
// r.OneFrameThreadLag=1: 기본값 (균형)
static TAutoConsoleVariable<int32> CVarOneFrameThreadLag(
    TEXT("r.OneFrameThreadLag"),
    1,
    TEXT("Whether to allow the render thread to lag one frame behind."));
```

---

## 4. 명령 큐잉 {#4-명령-큐잉}

### 4.1 ENQUEUE_RENDER_COMMAND

게임 스레드에서 렌더 스레드로 명령 전달:

```cpp
// 기본 사용법
ENQUEUE_RENDER_COMMAND(CommandName)(
    [CapturedData](FRHICommandListImmediate& RHICmdList)
    {
        // 렌더 스레드에서 실행
        UseData(CapturedData);
    });

// 매크로 확장
#define ENQUEUE_RENDER_COMMAND(Type) \
    struct Type##Name { static const TCHAR* CStr() { return TEXT(#Type); } }; \
    EnqueueUniqueRenderCommand<Type##Name>

// 실제 큐잉
template<typename TName>
void EnqueueUniqueRenderCommand(TFunctionRef<void(FRHICommandListImmediate&)> Lambda)
{
    if (IsInRenderingThread())
    {
        // 이미 렌더 스레드면 즉시 실행
        Lambda(GetImmediateCommandList_ForRenderCommand());
    }
    else
    {
        // 렌더 큐에 추가
        FRenderCommand* Command = new FRenderCommand(Lambda);
        GRenderCommandQueue.Enqueue(Command);
    }
}
```

### 4.2 FRHICommand

렌더 스레드에서 RHI 스레드로 명령 전달:

```cpp
// RHI 명령 기본 클래스
class FRHICommand
{
public:
    virtual void Execute(FRHICommandListBase& CmdList) = 0;
};

// 구체적 명령 예시
class FRHICommandSetViewport : public FRHICommand
{
    FIntRect Viewport;

public:
    virtual void Execute(FRHICommandListBase& CmdList) override
    {
        RHISetViewport(Viewport.Min.X, Viewport.Min.Y,
                       Viewport.Width(), Viewport.Height(),
                       0.0f, 1.0f);
    }
};

// FRHICommandList를 통한 명령 추가
void FRHICommandList::SetViewport(uint32 X, uint32 Y, uint32 W, uint32 H)
{
    if (Bypass())
    {
        // 즉시 모드
        RHISetViewport(X, Y, W, H, 0.0f, 1.0f);
    }
    else
    {
        // 명령 큐잉
        ALLOC_COMMAND(FRHICommandSetViewport)(FIntRect(X, Y, X+W, Y+H));
    }
}
```

### 4.3 명령 리스트 제출

```cpp
// 렌더 스레드에서 RHI 명령 리스트 제출
void FRenderingThread::Tick()
{
    // 렌더 명령 처리
    ProcessRenderCommands();

    // RHI 명령 리스트 완성
    FRHICommandListImmediate& RHICmdList = GetImmediateCommandList();

    // RHI 스레드로 제출
    RHICmdList.SubmitCommandsHint();
}

// RHI 스레드에서 실제 API 호출
void FRHIThread::ProcessCommands()
{
    while (FRHICommandListBase* CmdList = DequeueCommandList())
    {
        // 각 명령 실행 (실제 GPU API 호출)
        CmdList->Execute();
    }
}
```

---

## 5. 동기화 지점 {#5-동기화-지점}

### 5.1 FlushRenderingCommands

```cpp
// 렌더 스레드 완료 대기
void FlushRenderingCommands()
{
    if (!GIsRenderingThreadSuspended)
    {
        // 완료 이벤트 생성
        FGraphEventRef CompletionFence = FGraphEvent::CreateGraphEvent();

        // 렌더 스레드에 펜스 명령 전송
        ENQUEUE_RENDER_COMMAND(FlushCommand)(
            [CompletionFence](FRHICommandListImmediate&)
            {
                CompletionFence->DispatchSubsequents();
            });

        // 게임 스레드에서 대기
        FTaskGraphInterface::Get().WaitUntilTaskCompletes(CompletionFence);
    }
}

// 사용 예시
void UWorld::DestroyWorld(bool bInformEngineOfWorld)
{
    // 렌더링 완료 대기 후 월드 파괴
    FlushRenderingCommands();
    DestroyWorldInternal();
}
```

### 5.2 프레임 동기화

```cpp
// 프레임 경계 동기화
void FEngineLoop::Tick()
{
    // 이전 프레임 렌더링 완료 대기 (선택적)
    if (!CVarOneFrameThreadLag.GetValueOnGameThread())
    {
        FlushRenderingCommands();
    }

    // 새 프레임 시작
    GFrameCounter++;

    // 게임 틱
    GEngine->Tick(DeltaTime);

    // 렌더 명령 생성
    EnqueueRenderCommands();
}
```

### 5.3 Scene Proxy 생성/파괴

```cpp
// 안전한 Scene Proxy 파괴
void UPrimitiveComponent::DestroyRenderState_Concurrent()
{
    if (SceneProxy)
    {
        FPrimitiveSceneProxy* Proxy = SceneProxy;
        SceneProxy = nullptr;

        // 렌더 스레드에서 파괴
        ENQUEUE_RENDER_COMMAND(DestroyProxy)(
            [Proxy](FRHICommandListImmediate&)
            {
                // 렌더 스레드 전용 정리
                Proxy->DestroyRenderThreadResources();
                delete Proxy;
            });
    }
}
```

---

## 6. 디버깅과 프로파일링 {#6-디버깅과-프로파일링}

### 6.1 스레드 검증

```cpp
// 스레드 검증 매크로
check(IsInGameThread());           // 게임 스레드 확인
check(IsInRenderingThread());      // 렌더 스레드 확인
check(IsInRHIThread());            // RHI 스레드 확인

// 조건부 실행
if (IsInGameThread())
{
    // 게임 스레드 경로
}
else if (IsInRenderingThread())
{
    // 렌더 스레드 경로
}
```

### 6.2 프로파일링 도구

```cpp
// 스코프 기반 프로파일링
SCOPE_CYCLE_COUNTER(STAT_GameThread);
SCOPE_CYCLE_COUNTER(STAT_RenderThread);

// 커스텀 통계
DECLARE_CYCLE_STAT(TEXT("My Render Work"), STAT_MyRenderWork, STATGROUP_Renderer);

void DoRenderWork()
{
    SCOPE_CYCLE_COUNTER(STAT_MyRenderWork);
    // 작업 수행
}
```

### 6.3 디버그 명령

```cpp
// 콘솔 명령
// r.RHICmdBypass=1          RHI 명령 즉시 실행 (디버깅용)
// r.RHIThread.Enable=0      RHI 스레드 비활성화
// r.OneFrameThreadLag=0     프레임 지연 없음

// 스레드 정보 출력
stat threading          // 스레드 통계
stat rhi               // RHI 통계
stat gpu               // GPU 통계
```

---

## 요약 다이어그램

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE 렌더링 스레드 아키텍처                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game Thread (Frame N)                                          │
│  ├─ Input Processing                                            │
│  ├─ Actor/Component Tick                                        │
│  ├─ Physics Simulation                                          │
│  └─ ENQUEUE_RENDER_COMMAND() ──────────────────┐               │
│                                                 │               │
│                                                 ▼               │
│  Render Thread (Frame N-1)                                      │
│  ├─ Visibility Culling                                          │
│  ├─ FMeshDrawCommand Generation                                 │
│  ├─ Sort/Merge Commands                                         │
│  └─ FRHICommandList::Submit() ─────────────────┐               │
│                                                 │               │
│                                                 ▼               │
│  RHI Thread (Frame N-2)                                         │
│  ├─ Execute FRHICommands                                        │
│  ├─ D3D12/Vulkan/Metal API calls                               │
│  └─ GPU Command Submission ────────────────────┐               │
│                                                 │               │
│                                                 ▼               │
│  GPU (Frame N-3)                                                │
│  └─ Actual Rendering                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 문서

[05. 엔진 패턴 및 동기화](05-engine-patterns-sync.md)에서 다른 엔진들의 패턴과 동기화 프리미티브를 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../03-graphics-api-threading/" style="text-decoration: none;">← 이전: 03. 그래픽 API 멀티스레딩</a>
  <a href="../05-engine-patterns-sync/" style="text-decoration: none;">다음: 05. 엔진 패턴 및 동기화 →</a>
</div>
