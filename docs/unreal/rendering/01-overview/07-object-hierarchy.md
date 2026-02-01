# 07. 엔진 오브젝트 및 시작 파이프라인

> UObject 계층 구조와 엔진 시작/종료 과정

---

## 목차

1. [UObject 계층 구조](#1-uobject-계층-구조)
2. [AActor와 컴포넌트](#2-aactor와-컴포넌트)
3. [World/Level/Engine 구조](#3-worldlevelengine-구조)
4. [엔진 시작 파이프라인](#4-엔진-시작-파이프라인)
5. [메인 루프](#5-메인-루프)
6. [엔진 종료](#6-엔진-종료)

---

## 1. UObject 계층 구조 {#1-uobject-계층-구조}

### 1.1 UObject 개요

UObject는 UE의 모든 관리 객체의 기본 클래스입니다:

![UObject 계층](../images/ch01/1617944-20201026110828017-1837520317.png)
*UObject 상속 구조*

### 1.2 UObject 핵심 기능

| 기능 | 설명 |
|------|------|
| **리플렉션** | 런타임 타입 정보 (UClass) |
| **직렬화** | 저장/로드 자동 지원 |
| **가비지 컬렉션** | 자동 메모리 관리 |
| **CDO** | Class Default Object 패턴 |
| **네트워킹** | 복제 속성 지원 |

```cpp
class UObject
{
public:
    // 클래스 정보
    UClass* GetClass() const;
    static UClass* StaticClass();

    // 이름
    FName GetFName() const;
    FString GetName() const;
    FString GetPathName() const;

    // 플래그
    EObjectFlags GetFlags() const;
    void SetFlags(EObjectFlags NewFlags);
    bool HasAnyFlags(EObjectFlags FlagsToCheck) const;

    // Outer (소유자)
    UObject* GetOuter() const;
    UPackage* GetOutermost() const;

    // 유효성
    bool IsValidLowLevel() const;
    bool IsPendingKill() const;

    // 직렬화
    virtual void Serialize(FArchive& Ar);

    // CDO
    UObject* GetDefaultObject() const;
};
```

### 1.3 UObject 생성

```cpp
// NewObject - 가장 일반적인 생성 방법
UMyObject* Obj = NewObject<UMyObject>(Outer);
UMyObject* ObjWithName = NewObject<UMyObject>(Outer, FName(TEXT("MyObjectName")));
UMyObject* ObjFromClass = NewObject<UMyObject>(Outer, MyClass);

// 템플릿 기반 생성
UMyObject* ObjFromTemplate = NewObject<UMyObject>(Outer, Template);

// 팩토리 사용 (에셋 임포트 등)
UFactory* Factory = NewObject<UTextureFactory>();
UObject* ImportedAsset = Factory->ImportObject(...);

// CDO 접근
UMyObject* CDO = GetMutableDefault<UMyObject>();
const UMyObject* CDOConst = GetDefault<UMyObject>();
```

### 1.4 객체 플래그

```cpp
// 주요 객체 플래그
enum EObjectFlags
{
    RF_NoFlags              = 0x00000000,

    // GC 관련
    RF_Public               = 0x00000001,  // 패키지 외부에서 참조 가능
    RF_Standalone           = 0x00000002,  // 직접 삭제 불가
    RF_MarkAsRootSet        = 0x00000004,  // GC 루트
    RF_MarkAsNative         = 0x00000008,  // 네이티브 객체

    // 로딩/저장
    RF_Transactional        = 0x00000010,  // 트랜잭션 지원
    RF_ClassDefaultObject   = 0x00000020,  // CDO
    RF_Transient            = 0x00000040,  // 저장 안 됨

    // 상태
    RF_PendingKill          = 0x00000080,  // 삭제 예정 (deprecated in UE5)
    RF_TagGarbageTemp       = 0x00000100,  // GC 임시 태그
    RF_NeedLoad             = 0x00000200,  // 로드 필요
    RF_KeepForCooker        = 0x00000400,  // 쿠커에서 유지
    // ...
};

// 플래그 사용
MyObject->SetFlags(RF_Transient);
if (MyObject->HasAnyFlags(RF_Transient | RF_Transactional))
{
    // ...
}
```

---

## 2. AActor와 컴포넌트 {#2-aactor와-컴포넌트}

### 2.1 AActor 계층

```
UObject (모든 관리 객체의 기반)
│
└─ AActor (월드에 배치 가능)
   │
   ├─ APawn (물리적 표현을 가진 액터)
   │  │
   │  └─ ACharacter (이동, 충돌, 애니메이션)
   │
   ├─ AController (Pawn 제어)
   │  ├─ APlayerController (플레이어 입력)
   │  └─ AAIController (AI 제어)
   │
   ├─ AGameModeBase (게임 규칙)
   │  └─ AGameMode (확장 게임 모드)
   │
   ├─ APlayerState (플레이어 상태)
   │
   ├─ AInfo (정보 액터)
   │  ├─ AWorldSettings
   │  └─ AGameStateBase
   │
   └─ ALight (조명)
      ├─ ADirectionalLight
      ├─ APointLight
      ├─ ASpotLight
      └─ ARectLight
```

### 2.2 컴포넌트 계층

```
UActorComponent (Actor에 부착 가능)
│
├─ USceneComponent (트랜스폼 보유)
│  │
│  ├─ UPrimitiveComponent (렌더링/물리)
│  │  │
│  │  ├─ UMeshComponent
│  │  │  ├─ UStaticMeshComponent
│  │  │  └─ USkeletalMeshComponent
│  │  │
│  │  ├─ UShapeComponent
│  │  │  ├─ UBoxComponent
│  │  │  ├─ USphereComponent
│  │  │  └─ UCapsuleComponent
│  │  │
│  │  └─ UTextRenderComponent
│  │
│  ├─ UCameraComponent
│  │
│  ├─ ULightComponent
│  │  ├─ UDirectionalLightComponent
│  │  ├─ UPointLightComponent
│  │  └─ USpotLightComponent
│  │
│  └─ UAudioComponent
│
└─ UActorComponent (비공간적)
   ├─ UMovementComponent
   │  └─ UCharacterMovementComponent
   │
   ├─ UInputComponent
   │
   └─ UWidgetComponent
```

### 2.3 컴포넌트 사용

```cpp
UCLASS()
class AMyActor : public AActor
{
    GENERATED_BODY()

public:
    AMyActor()
    {
        // 루트 컴포넌트 생성
        RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));

        // 메시 컴포넌트
        MeshComponent = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Mesh"));
        MeshComponent->SetupAttachment(RootComponent);

        // 충돌 컴포넌트
        CollisionComponent = CreateDefaultSubobject<UCapsuleComponent>(TEXT("Collision"));
        CollisionComponent->SetupAttachment(RootComponent);
    }

private:
    UPROPERTY(VisibleAnywhere)
    UStaticMeshComponent* MeshComponent;

    UPROPERTY(VisibleAnywhere)
    UCapsuleComponent* CollisionComponent;
};

// 런타임 컴포넌트 추가
void AMyActor::AddDynamicComponent()
{
    UPointLightComponent* Light = NewObject<UPointLightComponent>(this);
    Light->SetupAttachment(RootComponent);
    Light->RegisterComponent();
}
```

---

## 3. World/Level/Engine 구조 {#3-worldlevelengine-구조}

### 3.1 계층 구조

```
UEngine (엔진 인스턴스)
│
├─ UGameEngine (게임 빌드)
│  │
│  └─ UGameInstance (게임 인스턴스)
│
└─ UEditorEngine (에디터 빌드)
   │
   └─ UEditorEngine 전용 기능

GEngine (전역 싱글톤)
    │
    └─ UWorld (월드, 게임 세션당 하나)
        │
        ├─ ULevel (Persistent Level)
        │  └─ AActor[] (레벨의 액터들)
        │
        ├─ ULevel[] (Streaming Levels)
        │
        ├─ FScene (렌더링 데이터)
        │
        ├─ PhysicsScene (물리 시뮬레이션)
        │
        └─ UWorldSettings (월드 설정)
```

### 3.2 UWorld

```cpp
class UWorld : public UObject
{
public:
    // 레벨
    ULevel* PersistentLevel;
    TArray<ULevelStreaming*> StreamingLevels;

    // 액터 관리
    template<class T>
    T* SpawnActor(UClass* Class, const FTransform& Transform);
    bool DestroyActor(AActor* Actor);

    // 게임 모드
    AGameModeBase* GetAuthGameMode() const;

    // 월드 설정
    AWorldSettings* GetWorldSettings() const;

    // 레벨 스트리밍
    void LoadStreamingLevel(const FName& LevelName);
    void UnloadStreamingLevel(const FName& LevelName);

    // 월드 타입
    EWorldType::Type WorldType;  // Game, Editor, PIE, Preview, etc.
};

// 월드 접근
UWorld* World = GetWorld();
UWorld* WorldFromContext = GEngine->GetWorldFromContextObject(ContextObject);
```

### 3.3 FScene (렌더링)

```cpp
// FScene은 UWorld의 렌더링 표현
class FScene
{
public:
    // 프리미티브 관리
    void AddPrimitive(UPrimitiveComponent* Primitive);
    void RemovePrimitive(UPrimitiveComponent* Primitive);
    void UpdatePrimitiveTransform(UPrimitiveComponent* Primitive);

    // 라이트 관리
    void AddLight(ULightComponent* Light);
    void RemoveLight(ULightComponent* Light);

    // 렌더링 데이터
    TArray<FPrimitiveSceneInfo*> Primitives;
    TArray<FLightSceneInfo*> Lights;

    // GPU Scene (UE4.22+)
    FGPUScene GPUScene;
};
```

---

## 4. 엔진 시작 파이프라인 {#4-엔진-시작-파이프라인}

### 4.1 시작 단계 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                    엔진 시작 파이프라인                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Phase 1: Static Initialization                           │   │
│  │ - CRT 초기화                                             │   │
│  │ - 정적 변수 초기화                                        │   │
│  │ - 모듈 정적 초기화                                        │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Phase 2: PreInit (FEngineLoop::PreInit)                  │   │
│  │ - 명령줄 파싱                                            │   │
│  │ - 메모리 설정                                            │   │
│  │ - 스레드 풀 초기화                                        │   │
│  │ - 코어 모듈 로드                                          │   │
│  │ - RHI 초기화                                              │   │
│  │ - 셰이더 캐시 로드                                        │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Phase 3: Init (FEngineLoop::Init)                        │   │
│  │ - GEngine 생성                                           │   │
│  │ - 서브시스템 초기화                                       │   │
│  │ - 시작 맵 로드                                            │   │
│  │ - 게임 인스턴스 생성                                      │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Phase 4: Tick (메인 루프)                                │   │
│  │ - 반복 실행                                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 PreInit 상세

| 순서 | 작업 | 설명 |
|------|------|------|
| 1 | 시작 화면 표시 | 스플래시 스크린 |
| 2 | 명령줄 파싱 | FCommandLine |
| 3 | 로그 시스템 초기화 | GLog 설정 |
| 4 | 메모리 할당자 설정 | GMalloc 초기화 |
| 5 | 스레드 풀 시작 | FQueuedThreadPool |
| 6 | 코어 모듈 로드 | Core, CoreUObject |
| 7 | RHI 초기화 | 그래픽 API 설정 |
| 8 | 셰이더 캐시 로드 | PSO 캐시 |

```cpp
int32 FEngineLoop::PreInit(const TCHAR* CmdLine)
{
    // 명령줄 설정
    FCommandLine::Set(CmdLine);

    // 메모리 초기화
    FMemory::Init();
    GMalloc = FPlatformMemory::BaseAllocator();

    // 태스크 그래프 시작
    FTaskGraphInterface::Startup(FPlatformMisc::NumberOfCores());

    // 모듈 로드
    FModuleManager::Get().LoadModule(TEXT("Core"));
    FModuleManager::Get().LoadModule(TEXT("CoreUObject"));

    // RHI 초기화
    RHIInit(bIsNullRHI);

    // 셰이더 컴파일러 시작
    GetOnDemandShaderCompiler();

    return 0;
}
```

### 4.3 Init 상세

```cpp
int32 FEngineLoop::Init()
{
    // GEngine 생성
    GEngine = NewObject<UGameEngine>();

    // 엔진 초기화
    GEngine->Init(this);

    // 게임 인스턴스 생성
    GEngine->GameInstance = NewObject<UGameInstance>(GEngine);
    GEngine->GameInstance->InitializeStandalone();

    // 시작 맵 로드
    FString MapName = GEngine->GetStartupMap();
    GEngine->LoadMap(MapName);

    // 렌더러 초기화
    GetRendererModule().BeginRenderingViewFamilies();

    return 0;
}
```

---

## 5. 메인 루프 {#5-메인-루프}

### 5.1 Tick 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    프레임 틱 순서                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. FEngineLoop::Tick()                                         │
│     │                                                           │
│     ├─ 스레드 하트비트 (FThreadHeartBeat::Get().HeartBeat())    │
│     │                                                           │
│     ├─ 이전 프레임 렌더 명령 플러시                              │
│     │                                                           │
│     ├─ 입력 처리                                                │
│     │                                                           │
│     ├─ GEngine->Tick()                                          │
│     │  │                                                        │
│     │  ├─ 월드 틱 (World->Tick())                               │
│     │  │  ├─ Actor BeginPlay (새 액터)                          │
│     │  │  ├─ Actor Tick                                         │
│     │  │  ├─ Component Tick                                     │
│     │  │  └─ Physics Tick                                       │
│     │  │                                                        │
│     │  └─ 레벨 스트리밍 업데이트                                 │
│     │                                                           │
│     ├─ 애니메이션/스켈레탈 업데이트                              │
│     │                                                           │
│     ├─ 렌더링 명령 생성 (RenderThread)                          │
│     │                                                           │
│     ├─ 오디오 업데이트                                          │
│     │                                                           │
│     └─ Slate/UI 업데이트                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 FEngineLoop::Tick 코드

```cpp
void FEngineLoop::Tick()
{
    // 스레드 하트비트
    FThreadHeartBeat::Get().HeartBeat();

    // 렌더 명령 플러시
    FlushRenderingCommands();

    // 시간 업데이트
    FApp::UpdateLastTime();

    // 입력 업데이트
    FSlateApplication::Get().PollGameDeviceState();

    // 엔진 틱
    GEngine->Tick(FApp::GetDeltaTime(), false);

    // 렌더링 (게임 스레드 작업)
    Render();

    // GC 처리
    if (bShouldCollectGarbage)
    {
        CollectGarbage(GARBAGE_COLLECTION_KEEPFLAGS);
    }

    // 프레임 종료
    FCoreDelegates::OnEndFrame.Broadcast();
}
```

### 5.3 병렬 실행

```
시간 ─────────────────────────────────────────→

Game Thread:   [Frame N+2 Tick] [Frame N+3 Tick] [Frame N+4 Tick]
                     │
                     ▼ 렌더 명령 생성
Render Thread:       │    [Frame N+1 Render] [Frame N+2 Render]
                     │          │
                     │          ▼ RHI 명령 생성
RHI Thread:          │          │    [Frame N Submit] [Frame N+1 Submit]
                     │          │          │
                     │          │          ▼
GPU:                 │          │          │    [Frame N-1] [Frame N]
```

---

## 6. 엔진 종료 {#6-엔진-종료}

### 6.1 종료 순서

```cpp
void FEngineLoop::Exit()
{
    // 1. 렌더 명령 완료 대기
    FlushRenderingCommands();

    // 2. 월드/액터 정리
    if (GEngine->GetWorldContexts().Num() > 0)
    {
        for (FWorldContext& Context : GEngine->GetWorldContexts())
        {
            if (Context.World())
            {
                Context.World()->DestroyWorld(true);
            }
        }
    }

    // 3. 엔진 종료
    GEngine->PreExit();

    // 4. 모듈 언로드
    FModuleManager::Get().UnloadModulesAtShutdown();

    // 5. RHI 종료
    RHIExitAndStopRHIThread();

    // 6. 태스크 그래프 종료
    FTaskGraphInterface::Shutdown();

    // 7. 메모리 정리
    FMemory::Shutdown();
}
```

### 6.2 종료 시 주의사항

```cpp
// 안전한 종료를 위한 패턴
class FMySubsystem
{
public:
    void Initialize()
    {
        // 리소스 할당
        Resource = AllocateResource();

        // 종료 델리게이트 등록
        FCoreDelegates::OnPreExit.AddRaw(this, &FMySubsystem::OnPreExit);
    }

    void OnPreExit()
    {
        // 종료 전 정리
        if (Resource)
        {
            FreeResource(Resource);
            Resource = nullptr;
        }
    }

private:
    void* Resource;
};
```

---

## 요약

| 주제 | 핵심 내용 |
|------|----------|
| **UObject** | 리플렉션, 직렬화, GC의 기반 클래스 |
| **AActor** | 월드 배치 가능, 컴포넌트 컨테이너 |
| **UWorld** | 게임 세션, 레벨 관리, FScene 소유 |
| **시작** | PreInit(하위시스템) → Init(GEngine) → Tick(루프) |
| **메인 루프** | 입력 → 게임 → 물리 → 렌더링 → GC |
| **종료** | 역순 정리, 델리게이트 통한 알림 |

---

## 다음 챕터

[Ch.02 멀티스레드 렌더링](../02-multithreading/index.md)에서 UE의 멀티스레딩 아키텍처를 살펴봅니다.

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13877623.html)
- [Unreal Engine 공식 문서](https://docs.unrealengine.com/)
- [Epic Games GitHub](https://github.com/EpicGames/UnrealEngine)
