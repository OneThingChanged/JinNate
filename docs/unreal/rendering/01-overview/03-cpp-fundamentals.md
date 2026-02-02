# 03. C++ 언어 기능 및 기초

> Unreal Engine에서 사용되는 C++ 언어 기능과 코딩 컨벤션

---

## 목차

1. [Lambda 표현식](#1-lambda-표현식)
2. [스마트 포인터 시스템](#2-스마트-포인터-시스템)
3. [델리게이트 시스템](#3-델리게이트-시스템)
4. [네이밍 컨벤션](#4-네이밍-컨벤션)
5. [매크로 시스템](#5-매크로-시스템)
6. [리플렉션 시스템](#6-리플렉션-시스템)

---

## 1. Lambda 표현식 {#1-lambda-표현식}

### 1.1 렌더링 명령 큐잉

UE는 명령 큐잉을 위해 C++11 람다를 광범위하게 사용합니다:

```cpp
// 렌더 스레드로 명령 전달
ENQUEUE_RENDER_COMMAND(AddPrimitiveCommand)(
    [Params = MoveTemp(Params), Scene, PrimitiveSceneInfo](FRHICommandListImmediate& RHICmdList)
    {
        // 렌더 스레드에서 실행
        SceneProxy->CreateRenderThreadResources();
        Scene->AddPrimitiveSceneInfo_RenderThread(PrimitiveSceneInfo, PreviousTransform);
    });
```

### 1.2 캡처 모드

```cpp
// 값 캡처 - 복사본 생성
auto ByValue = [Value]() { return Value; };

// 참조 캡처 - 위험할 수 있음 (생명주기 주의)
auto ByRef = [&Value]() { return Value; };

// 이동 캡처 (C++14) - UE에서 권장
auto ByMove = [Value = MoveTemp(Value)]() { return Value; };

// 혼합 캡처
auto Mixed = [this, Value = MoveTemp(Value), &Ref]()
{
    this->DoSomething(Value, Ref);
};
```

### 1.3 태스크 그래프에서의 사용

```cpp
// 비동기 태스크 실행
FFunctionGraphTask::CreateAndDispatchWhenReady(
    [this]()
    {
        // 워커 스레드에서 실행
        PerformHeavyComputation();
    },
    TStatId(),
    nullptr,
    ENamedThreads::AnyThread
);

// 게임 스레드로 복귀
AsyncTask(ENamedThreads::GameThread, [this, Result]()
{
    // 게임 스레드에서 결과 처리
    OnComputationComplete(Result);
});
```

### 1.4 람다와 생명주기

```cpp
// 잘못된 예: 참조 캡처된 로컬 변수
void BadExample()
{
    int LocalValue = 42;

    ENQUEUE_RENDER_COMMAND(BadCommand)(
        [&LocalValue](FRHICommandListImmediate& RHICmdList)  // 위험!
        {
            // LocalValue는 이미 스코프를 벗어났을 수 있음
            UseValue(LocalValue);
        });
}  // LocalValue 파괴됨

// 올바른 예: 값 또는 이동 캡처
void GoodExample()
{
    int LocalValue = 42;

    ENQUEUE_RENDER_COMMAND(GoodCommand)(
        [LocalValue](FRHICommandListImmediate& RHICmdList)  // 값 복사
        {
            UseValue(LocalValue);
        });
}
```

---

## 2. 스마트 포인터 시스템 {#2-스마트-포인터-시스템}

### 2.1 포인터 타입 비교

| UE 타입 | C++ 표준 | 용도 | 스레드 안전 |
|---------|---------|------|------------|
| **TSharedPtr** | shared_ptr | 참조 카운팅 소유권 | 선택적 |
| **TSharedRef** | — | null 불가 공유 참조 | 선택적 |
| **TWeakPtr** | weak_ptr | 비소유 참조 | 선택적 |
| **TUniquePtr** | unique_ptr | 독점 소유권 | 불필요 |

### 2.2 TSharedPtr 상세

```cpp
// 생성
TSharedPtr<FMyClass> Ptr = MakeShared<FMyClass>(ConstructorArgs);

// 스레드 안전 모드
TSharedPtr<FMyClass, ESPMode::ThreadSafe> ThreadSafePtr =
    MakeShared<FMyClass, ESPMode::ThreadSafe>();

// 참조 카운트 확인
int32 RefCount = Ptr.GetSharedReferenceCount();

// 유효성 검사
if (Ptr.IsValid())
{
    Ptr->DoSomething();
}

// 리셋
Ptr.Reset();  // 참조 해제
Ptr = nullptr;  // 동일
```

### 2.3 TSharedRef 특징

```cpp
// TSharedRef는 항상 유효한 객체를 가리킴
TSharedRef<FMyClass> Ref = MakeShared<FMyClass>();

// null 체크 불필요 - 항상 유효
Ref->DoSomething();  // 안전

// TSharedPtr로 변환 가능
TSharedPtr<FMyClass> Ptr = Ref;

// TSharedPtr에서 TSharedRef로 변환 (유효성 검사 필요)
if (Ptr.IsValid())
{
    TSharedRef<FMyClass> RefFromPtr = Ptr.ToSharedRef();
}
```

### 2.4 TWeakPtr 사용

```cpp
// 순환 참조 방지
class FNode
{
    TSharedPtr<FNode> Child;    // 강한 참조 - 자식 소유
    TWeakPtr<FNode> Parent;     // 약한 참조 - 부모 참조만

public:
    void SetParent(TSharedPtr<FNode> InParent)
    {
        Parent = InParent;  // 암시적 변환
    }

    TSharedPtr<FNode> GetParent()
    {
        // Pin()으로 임시 TSharedPtr 획득
        return Parent.Pin();
    }
};

// 유효성 검사
if (TSharedPtr<FNode> ParentPtr = WeakParent.Pin())
{
    // 이 스코프 내에서 ParentPtr은 유효함 보장
    ParentPtr->DoSomething();
}
```

### 2.5 TUniquePtr 사용

```cpp
// 독점 소유권
TUniquePtr<FResource> Resource = MakeUnique<FResource>();

// 이동만 가능, 복사 불가
TUniquePtr<FResource> MovedResource = MoveTemp(Resource);

// 원시 포인터 접근
FResource* RawPtr = Resource.Get();

// 소유권 해제
FResource* ReleasedPtr = Resource.Release();

// 커스텀 삭제자
TUniquePtr<FResource, TCustomDeleter> CustomResource(
    new FResource(),
    TCustomDeleter()
);
```

---

## 3. 델리게이트 시스템 {#3-델리게이트-시스템}

### 3.1 델리게이트 타입

```cpp
// 단일 바인딩 델리게이트
DECLARE_DELEGATE(FSimpleDelegate);
DECLARE_DELEGATE_OneParam(FOneParamDelegate, int32);
DECLARE_DELEGATE_TwoParams(FTwoParamsDelegate, int32, FString);
DECLARE_DELEGATE_RetVal(bool, FRetValDelegate);
DECLARE_DELEGATE_RetVal_OneParam(bool, FRetValOneParamDelegate, int32);

// 멀티캐스트 델리게이트 (여러 바인딩)
DECLARE_MULTICAST_DELEGATE(FMulticastDelegate);
DECLARE_MULTICAST_DELEGATE_OneParam(FOnValueChanged, float);

// 동적 델리게이트 (Blueprint 호출 가능)
DECLARE_DYNAMIC_DELEGATE(FDynamicDelegate);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnHealthChanged, float, NewHealth);
```

### 3.2 바인딩 방법

```cpp
// 정적 함수
Delegate.BindStatic(&GlobalFunction);

// 람다
Delegate.BindLambda([](int32 Value) { /* ... */ });

// 원시 포인터 (위험)
Delegate.BindRaw(RawPtr, &FMyClass::MemberFunction);

// 공유 포인터 (안전)
Delegate.BindSP(SharedPtr, &FMyClass::MemberFunction);

// UObject (GC 안전)
Delegate.BindUObject(UObjectPtr, &UMyClass::MemberFunction);

// 약한 람다 (객체 유효시에만 실행)
Delegate.BindWeakLambda(UObjectPtr, [](int32 Value) { /* ... */ });
```

### 3.3 실행

```cpp
// 단일 델리게이트
if (Delegate.IsBound())
{
    Delegate.Execute(Argument);
}

// 또는 안전한 실행
Delegate.ExecuteIfBound(Argument);

// 반환값이 있는 경우
bool bResult = false;
if (RetValDelegate.IsBound())
{
    bResult = RetValDelegate.Execute(Argument);
}

// 멀티캐스트 델리게이트
MulticastDelegate.Broadcast(Argument);
```

### 3.4 실제 사용 예시

```cpp
// 헤더
DECLARE_MULTICAST_DELEGATE_TwoParams(FOnDamageReceived, float, AActor*);

UCLASS()
class AMyCharacter : public ACharacter
{
    GENERATED_BODY()

public:
    // 델리게이트 인스턴스
    FOnDamageReceived OnDamageReceived;

    void TakeDamage(float Amount, AActor* Instigator)
    {
        Health -= Amount;

        // 모든 구독자에게 알림
        OnDamageReceived.Broadcast(Amount, Instigator);
    }
};

// 사용측
void AMyHUD::BeginPlay()
{
    Super::BeginPlay();

    if (AMyCharacter* Character = GetOwningCharacter())
    {
        // 이벤트 구독
        Character->OnDamageReceived.AddUObject(
            this, &AMyHUD::OnCharacterDamaged);
    }
}

void AMyHUD::OnCharacterDamaged(float Amount, AActor* Instigator)
{
    // 데미지 표시 UI 업데이트
    ShowDamageIndicator(Amount);
}
```

---

## 4. 네이밍 컨벤션 {#4-네이밍-컨벤션}

### 4.1 클래스 접두사

| 접두사 | 의미 | 예시 |
|--------|------|------|
| **U** | UObject 파생 클래스 | UStaticMesh, UTexture |
| **A** | AActor 파생 클래스 | ACharacter, APlayerController |
| **S** | Slate 위젯 | SButton, STextBlock |
| **F** | 구조체/일반 클래스 | FVector, FString, FName |
| **T** | 템플릿 | TArray, TMap, TSharedPtr |
| **I** | 인터페이스 | IInputProcessor, IDamageable |
| **E** | 열거형 | EBlendMode, ECollisionChannel |

### 4.2 변수 접두사

| 접두사 | 의미 | 예시 |
|--------|------|------|
| **b** | Boolean | bIsVisible, bCanJump |
| **n** | 정수 (일부 코드) | nCount |
| **f** | float (일부 코드) | fDelta |
| — | 기타 | Name, Value, Index |

### 4.3 함수 네이밍

```cpp
class UMyComponent : public UActorComponent
{
public:
    // Getter - Get 접두사
    float GetHealth() const { return Health; }
    bool IsAlive() const { return Health > 0; }  // Is/Has/Can 접두사

    // Setter - Set 접두사
    void SetHealth(float NewHealth) { Health = NewHealth; }

    // 이벤트 핸들러 - On/Handle 접두사
    void OnDamageReceived(float Amount);
    void HandleCollision(const FHitResult& Hit);

    // 내부 함수 - Internal 접미사 또는 _Implementation
    void UpdateHealth_Internal();

    // Blueprint 네이티브 이벤트
    UFUNCTION(BlueprintNativeEvent)
    void OnHealthChanged(float NewHealth);
    void OnHealthChanged_Implementation(float NewHealth);

private:
    float Health;
};
```

### 4.4 매크로/상수

```cpp
// 매크로 - 대문자 + 밑줄
#define LOCTEXT_NAMESPACE "MyModule"
#define MY_CUSTOM_FLAG 0x0001

// 상수 - 접두사 없음 또는 k 접두사 (드물게)
static const int32 MaxPlayers = 64;
static constexpr float DefaultHealth = 100.0f;
```

![코드 주석](../images/ch01/1617944-20201026204640162-1352686621.png)
*C++ 컴포넌트 변수에 주석 추가 시 UE 컴파일 시스템이 캡처하여 에디터 툴팁에 적용*

---

## 5. 매크로 시스템 {#5-매크로-시스템}

### 5.1 로깅 매크로

```cpp
// 기본 로그
UE_LOG(LogTemp, Log, TEXT("Simple message"));
UE_LOG(LogTemp, Warning, TEXT("Warning: Value is %d"), Value);
UE_LOG(LogTemp, Error, TEXT("Error: %s failed"), *FunctionName);

// 조건부 로그
UE_CLOG(bCondition, LogTemp, Warning, TEXT("Conditional warning"));

// 커스텀 로그 카테고리
DECLARE_LOG_CATEGORY_EXTERN(LogMyGame, Log, All);
DEFINE_LOG_CATEGORY(LogMyGame);

UE_LOG(LogMyGame, Display, TEXT("Game specific log"));
```

### 5.2 체크/검증 매크로

```cpp
// check - Development/Debug 빌드에서만 활성화
check(Pointer != nullptr);
checkf(Value > 0, TEXT("Value must be positive: %d"), Value);
checkNoEntry();  // 실행되면 안 되는 코드
checkNoReentry();  // 재진입 방지

// verify - 항상 표현식 평가, 실패시 Development/Debug에서 중단
verify(ImportantFunction());

// ensure - 한 번만 보고, 실행 계속
if (ensure(Pointer != nullptr))
{
    Pointer->DoSomething();
}

// ensureMsgf - 메시지 포함
ensureMsgf(Value > 0, TEXT("Invalid value: %d"), Value);
```

### 5.3 UPROPERTY 매크로

```cpp
UCLASS()
class UMyClass : public UObject
{
    GENERATED_BODY()

public:
    // 에디터에서 편집 가능
    UPROPERTY(EditAnywhere, Category = "Settings")
    float MaxHealth = 100.0f;

    // Blueprint에서 읽기/쓰기
    UPROPERTY(BlueprintReadWrite, Category = "State")
    float CurrentHealth;

    // Blueprint에서 읽기만
    UPROPERTY(BlueprintReadOnly, Category = "State")
    bool bIsDead;

    // 저장됨
    UPROPERTY(SaveGame)
    int32 Score;

    // 네트워크 복제
    UPROPERTY(Replicated)
    FVector Position;

    // 변경시 함수 호출
    UPROPERTY(ReplicatedUsing = OnRep_Health)
    float ReplicatedHealth;

    UFUNCTION()
    void OnRep_Health();

    // 트랜지언트 - 저장/복제 안됨
    UPROPERTY(Transient)
    float CachedValue;
};
```

### 5.4 UFUNCTION 매크로

```cpp
UCLASS()
class AMyActor : public AActor
{
    GENERATED_BODY()

public:
    // Blueprint에서 호출 가능
    UFUNCTION(BlueprintCallable, Category = "Combat")
    void Attack(AActor* Target);

    // Blueprint에서 구현
    UFUNCTION(BlueprintImplementableEvent, Category = "Events")
    void OnLevelUp(int32 NewLevel);

    // C++ 기본 구현 + Blueprint 오버라이드 가능
    UFUNCTION(BlueprintNativeEvent, Category = "Events")
    void OnDeath();
    void OnDeath_Implementation();

    // Blueprint 순수 함수 (실행선 없음)
    UFUNCTION(BlueprintPure, Category = "Utility")
    static float CalculateDamage(float BaseDamage, float Multiplier);

    // 서버에서 실행 (네트워크)
    UFUNCTION(Server, Reliable, WithValidation)
    void ServerAttack(AActor* Target);
    void ServerAttack_Implementation(AActor* Target);
    bool ServerAttack_Validate(AActor* Target);

    // 클라이언트에서 실행
    UFUNCTION(Client, Unreliable)
    void ClientShowDamage(float Amount);
    void ClientShowDamage_Implementation(float Amount);

    // 콘솔 명령
    UFUNCTION(Exec)
    void DebugKill();
};
```

---

## 6. 리플렉션 시스템 {#6-리플렉션-시스템}

### 6.1 UClass 접근

```cpp
// 클래스 정보 획득
UClass* MyClass = AMyActor::StaticClass();
UClass* RuntimeClass = MyActorInstance->GetClass();

// 상속 체크
if (MyClass->IsChildOf(AActor::StaticClass()))
{
    // AActor의 자식 클래스
}

// 인터페이스 구현 체크
if (MyActorInstance->Implements<IMyInterface>())
{
    IMyInterface::Execute_InterfaceFunction(MyActorInstance);
}
```

### 6.2 프로퍼티 접근

```cpp
// 프로퍼티 반복
for (TFieldIterator<FProperty> It(MyClass); It; ++It)
{
    FProperty* Property = *It;
    FString PropertyName = Property->GetName();
    FString PropertyType = Property->GetCPPType();

    UE_LOG(LogTemp, Log, TEXT("Property: %s (%s)"), *PropertyName, *PropertyType);
}

// 이름으로 프로퍼티 찾기
FProperty* HealthProperty = MyClass->FindPropertyByName(TEXT("Health"));
if (HealthProperty)
{
    float* HealthPtr = HealthProperty->ContainerPtrToValuePtr<float>(MyActorInstance);
    *HealthPtr = 100.0f;
}
```

### 6.3 함수 호출

```cpp
// 이름으로 함수 찾기
UFunction* AttackFunction = MyClass->FindFunctionByName(TEXT("Attack"));

if (AttackFunction)
{
    // 파라미터 구조체
    struct FAttackParams
    {
        AActor* Target;
    };

    FAttackParams Params;
    Params.Target = TargetActor;

    // 함수 호출
    MyActorInstance->ProcessEvent(AttackFunction, &Params);
}
```

### 6.4 동적 객체 생성

```cpp
// NewObject - 가장 일반적
UMyComponent* Comp = NewObject<UMyComponent>(Owner);

// SpawnActor - 액터 전용
FActorSpawnParameters SpawnParams;
SpawnParams.Owner = this;
AMyActor* Actor = GetWorld()->SpawnActor<AMyActor>(
    AMyActor::StaticClass(),
    SpawnLocation,
    SpawnRotation,
    SpawnParams
);

// 클래스 이름으로 생성
UClass* LoadedClass = LoadClass<AActor>(nullptr, TEXT("/Game/Blueprints/BP_MyActor.BP_MyActor_C"));
if (LoadedClass)
{
    AActor* DynamicActor = GetWorld()->SpawnActor<AActor>(LoadedClass);
}
```

---

## 요약

| 기능 | 핵심 사항 |
|------|----------|
| **Lambda** | 캡처 모드 주의, 생명주기 관리 |
| **스마트 포인터** | TSharedPtr(공유), TUniquePtr(독점), TWeakPtr(순환방지) |
| **델리게이트** | 이벤트 기반 통신, Blueprint 연동 |
| **네이밍** | 접두사 규칙 준수 (U, A, F, T, E, I) |
| **리플렉션** | 런타임 타입 정보, 동적 접근 |

---

## 다음 문서

[04. 컨테이너 및 수학 라이브러리](04-containers-math.md)에서 UE의 핵심 자료구조와 수학 타입을 살펴봅니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../02-rendering-overview/" style="text-decoration: none;">← 이전: 02. 렌더링 체계 개요</a>
  <a href="../04-containers-math/" style="text-decoration: none;">다음: 04. 컨테이너 및 수학 라이브러리 →</a>
</div>
