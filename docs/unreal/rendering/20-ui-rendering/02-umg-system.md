# UMG 시스템

Unreal Motion Graphics (UMG)의 아키텍처와 Widget Blueprint 시스템을 분석합니다.

---

## UMG 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                      UMG Overview                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UMG = Slate 위에 구축된 고수준 UI 프레임워크                    │
│                                                                 │
│  특징:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Widget Blueprint 지원 (비주얼 스크립팅)               │   │
│  │ • Widget Designer (WYSIWYG 편집)                        │   │
│  │ • 애니메이션 시스템                                      │   │
│  │ • 데이터 바인딩                                          │   │
│  │ • 이벤트 시스템                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  아키텍처:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │      Widget Blueprint                                    │   │
│  │            │                                             │   │
│  │            ▼                                             │   │
│  │      UUserWidget (C++)                                   │   │
│  │            │                                             │   │
│  │            ▼                                             │   │
│  │      UWidget → SWidget                                   │   │
│  │            │                                             │   │
│  │            ▼                                             │   │
│  │      Slate Renderer                                      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## UWidget 클래스 계층

```
┌─────────────────────────────────────────────────────────────────┐
│                  UWidget Class Hierarchy                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                         UWidget                                 │
│                            │                                    │
│        ┌───────────────────┼───────────────────┐               │
│        │                   │                   │               │
│        ▼                   ▼                   ▼               │
│   UPanelWidget        UUserWidget        UContentWidget         │
│        │                   │                                    │
│   ┌────┴────┐         (Blueprint)                              │
│   │         │                                                   │
│   ▼         ▼                                                   │
│ UCanvasPanel UOverlay                                           │
│              │                                                   │
│        ┌─────┴─────┐                                            │
│        │           │                                            │
│        ▼           ▼                                            │
│  UHorizontalBox UVerticalBox                                    │
│                                                                 │
│  Visual 위젯:                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ UTextBlock   │  │ UImage       │  │ UButton      │          │
│  │ UEditableText│  │ UProgressBar │  │ UCheckBox    │          │
│  │ URichTextBlock│ │ UBorder      │  │ USlider      │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UWidget과 SWidget 관계

```cpp
// UWidget은 SWidget을 래핑
class UWidget : public UVisual
{
protected:
    // 내부 Slate 위젯
    TSharedPtr<SWidget> MyWidget;

    // Slate 위젯 재구성
    virtual void RebuildWidget()
    {
        MyWidget = SNew(SMySlateWidget)
            .Property(Property);
    }

    // 동기화
    virtual void SynchronizeProperties()
    {
        // UWidget 속성 → SWidget으로 전달
        if (MyWidget.IsValid())
        {
            StaticCastSharedPtr<SMySlateWidget>(MyWidget)
                ->SetProperty(Property);
        }
    }

public:
    // Slate 위젯 접근
    TSharedPtr<SWidget> GetCachedWidget() const
    {
        return MyWidget;
    }
};
```

---

## Widget Blueprint

```
┌─────────────────────────────────────────────────────────────────┐
│                    Widget Blueprint                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Widget Blueprint = UUserWidget을 상속한 Blueprint 클래스        │
│                                                                 │
│  구성:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌───────────────┐  ┌───────────────┐                   │   │
│  │  │  Designer     │  │  Graph        │                   │   │
│  │  │  (시각적 편집) │  │  (로직 편집)  │                   │   │
│  │  ├───────────────┤  ├───────────────┤                   │   │
│  │  │ Widget Tree   │  │ Event Graph   │                   │   │
│  │  │ ├─ Canvas     │  │ ├─ Construct  │                   │   │
│  │  │ │  ├─ Button  │  │ │  └─ Init    │                   │   │
│  │  │ │  └─ Text    │  │ ├─ Tick      │                   │   │
│  │  │ └─ Overlay    │  │ └─ Events    │                   │   │
│  │  └───────────────┘  └───────────────┘                   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UUserWidget 생명주기

```cpp
// UUserWidget 생명주기
class UUserWidget : public UWidget
{
public:
    // 위젯 생성 시 호출
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        // 초기화 로직
        InitializeWidget();
    }

    // 매 프레임 호출
    virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override
    {
        Super::NativeTick(MyGeometry, InDeltaTime);

        // 프레임 업데이트 로직
        UpdateWidget(InDeltaTime);
    }

    // 위젯 제거 시 호출
    virtual void NativeDestruct() override
    {
        // 정리 로직
        CleanupWidget();

        Super::NativeDestruct();
    }

    // 가시성 변경 시
    virtual void OnVisibilityChanged(ESlateVisibility InVisibility)
    {
        if (InVisibility == ESlateVisibility::Visible)
        {
            OnBecomeVisible();
        }
        else
        {
            OnBecomeHidden();
        }
    }

protected:
    // Blueprint에서 오버라이드 가능
    UFUNCTION(BlueprintImplementableEvent)
    void InitializeWidget();

    UFUNCTION(BlueprintImplementableEvent)
    void UpdateWidget(float DeltaTime);
};
```

---

## 데이터 바인딩

```
┌─────────────────────────────────────────────────────────────────┐
│                     Data Binding                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  바인딩 방식:                                                    │
│                                                                 │
│  1. Property Binding (속성 바인딩)                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  TextBlock.Text  ────bind────►  GetPlayerHealth()       │   │
│  │                                                          │   │
│  │  매 프레임 함수를 호출하여 값 업데이트                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  2. Event-Driven (이벤트 기반)                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  HealthChanged  ────event────►  UpdateHealthDisplay()   │   │
│  │                                                          │   │
│  │  데이터 변경 시에만 UI 업데이트                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  3. ViewModel Pattern                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Model ◄──► ViewModel ◄──► View (Widget)                │   │
│  │                                                          │   │
│  │  MVVM 패턴으로 데이터와 UI 분리                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 속성 바인딩

```cpp
// Property Binding 예시
UCLASS()
class UMyHUD : public UUserWidget
{
    GENERATED_BODY()

public:
    // Text 바인딩 함수
    UFUNCTION()
    FText GetHealthText() const
    {
        if (AMyCharacter* Character = GetOwningPlayer()->GetPawn<AMyCharacter>())
        {
            return FText::AsNumber(Character->GetHealth());
        }
        return FText::FromString(TEXT("--"));
    }

    // Progress 바인딩 함수
    UFUNCTION()
    float GetHealthPercent() const
    {
        if (AMyCharacter* Character = GetOwningPlayer()->GetPawn<AMyCharacter>())
        {
            return Character->GetHealth() / Character->GetMaxHealth();
        }
        return 0.0f;
    }

    // Visibility 바인딩 함수
    UFUNCTION()
    ESlateVisibility GetDamageIndicatorVisibility() const
    {
        if (bShowDamageIndicator)
        {
            return ESlateVisibility::Visible;
        }
        return ESlateVisibility::Collapsed;
    }

protected:
    UPROPERTY(meta = (BindWidget))
    UTextBlock* HealthText;

    UPROPERTY(meta = (BindWidget))
    UProgressBar* HealthBar;
};
```

### 이벤트 기반 업데이트

```cpp
// Event-Driven 업데이트
UCLASS()
class UInventoryWidget : public UUserWidget
{
    GENERATED_BODY()

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        // 인벤토리 변경 이벤트 구독
        if (UInventoryComponent* Inventory = GetInventoryComponent())
        {
            Inventory->OnInventoryChanged.AddDynamic(
                this, &UInventoryWidget::OnInventoryChanged
            );
        }
    }

    virtual void NativeDestruct() override
    {
        // 이벤트 구독 해제
        if (UInventoryComponent* Inventory = GetInventoryComponent())
        {
            Inventory->OnInventoryChanged.RemoveDynamic(
                this, &UInventoryWidget::OnInventoryChanged
            );
        }

        Super::NativeDestruct();
    }

    UFUNCTION()
    void OnInventoryChanged(const TArray<FInventoryItem>& Items)
    {
        // 인벤토리 UI 업데이트
        RefreshInventoryDisplay(Items);
    }

private:
    void RefreshInventoryDisplay(const TArray<FInventoryItem>& Items)
    {
        ItemContainer->ClearChildren();

        for (const FInventoryItem& Item : Items)
        {
            UInventorySlot* Slot = CreateWidget<UInventorySlot>(this, SlotClass);
            Slot->SetItem(Item);
            ItemContainer->AddChild(Slot);
        }
    }

    UPROPERTY(meta = (BindWidget))
    UPanelWidget* ItemContainer;

    UPROPERTY(EditDefaultsOnly)
    TSubclassOf<UInventorySlot> SlotClass;
};
```

---

## 애니메이션 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                   UMG Animation System                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Widget Animation = 키프레임 기반 애니메이션                     │
│                                                                 │
│  지원 속성:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Transform (위치, 회전, 스케일)                        │   │
│  │ • Render Opacity (투명도)                                │   │
│  │ • Color and Opacity                                     │   │
│  │ • Visibility                                             │   │
│  │ • 커스텀 속성 (Blueprint 노출 속성)                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  타임라인:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │     0s        0.5s       1.0s       1.5s       2.0s     │   │
│  │     │          │          │          │          │       │   │
│  │  ◆──────────◆                                           │   │
│  │  Opacity: 0 → 1  (Fade In)                              │   │
│  │                                                          │   │
│  │           ◆─────────────────────────◆                   │   │
│  │           Scale: 1.0 ──────────► 1.2                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 애니메이션 재생

```cpp
UCLASS()
class UNotificationWidget : public UUserWidget
{
    GENERATED_BODY()

public:
    // 애니메이션 재생
    UFUNCTION(BlueprintCallable)
    void ShowNotification(const FText& Message)
    {
        NotificationText->SetText(Message);

        // 나타나기 애니메이션
        PlayAnimation(FadeInAnimation);

        // 일정 시간 후 사라지기
        GetWorld()->GetTimerManager().SetTimer(
            HideTimerHandle,
            this,
            &UNotificationWidget::HideNotification,
            DisplayDuration,
            false
        );
    }

    void HideNotification()
    {
        PlayAnimation(FadeOutAnimation, 0.0f, 1, EUMGSequencePlayMode::Forward,
            1.0f, false);

        // 애니메이션 완료 후 제거
        FTimerDelegate Delegate;
        Delegate.BindLambda([this]()
        {
            RemoveFromParent();
        });

        GetWorld()->GetTimerManager().SetTimer(
            RemoveTimerHandle,
            Delegate,
            FadeOutAnimation->GetEndTime(),
            false
        );
    }

protected:
    UPROPERTY(meta = (BindWidget))
    UTextBlock* NotificationText;

    UPROPERTY(Transient, meta = (BindWidgetAnim))
    UWidgetAnimation* FadeInAnimation;

    UPROPERTY(Transient, meta = (BindWidgetAnim))
    UWidgetAnimation* FadeOutAnimation;

    UPROPERTY(EditDefaultsOnly)
    float DisplayDuration = 3.0f;

private:
    FTimerHandle HideTimerHandle;
    FTimerHandle RemoveTimerHandle;
};
```

### 애니메이션 이벤트

```cpp
// 애니메이션 이벤트 처리
void UMyWidget::PlayCustomAnimation()
{
    // 애니메이션 재생 (이벤트 바인딩)
    PlayAnimation(MyAnimation);

    // 시작 이벤트
    BindToAnimationStarted(MyAnimation,
        FWidgetAnimationDynamicEvent::CreateLambda([this]()
    {
        UE_LOG(LogUI, Log, TEXT("Animation Started"));
    }));

    // 완료 이벤트
    BindToAnimationFinished(MyAnimation,
        FWidgetAnimationDynamicEvent::CreateLambda([this]()
    {
        UE_LOG(LogUI, Log, TEXT("Animation Finished"));
        OnAnimationComplete();
    }));
}

// 애니메이션 상태 확인
void UMyWidget::CheckAnimationState()
{
    if (IsAnimationPlaying(MyAnimation))
    {
        float CurrentTime = GetAnimationCurrentTime(MyAnimation);
        float TotalTime = MyAnimation->GetEndTime();
        float Progress = CurrentTime / TotalTime;
    }
}
```

---

## Widget 상호작용

```
┌─────────────────────────────────────────────────────────────────┐
│                    Widget Interaction                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  3D 공간에서의 UI 상호작용:                                      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │     Player                  World Space Widget           │   │
│  │     ┌───┐                   ┌─────────────┐             │   │
│  │     │ @ │ ─────ray────────► │ [Button]   │             │   │
│  │     └───┘                   │ [Slider]   │             │   │
│  │                             └─────────────┘             │   │
│  │                                                          │   │
│  │  Widget Interaction Component:                           │   │
│  │  • 레이캐스트 기반 상호작용                              │   │
│  │  • VR/AR 컨트롤러 지원                                   │   │
│  │  • 호버/클릭 이벤트 전달                                 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Widget Component

```cpp
// 월드 공간 위젯 설정
UCLASS()
class AInteractiveTerminal : public AActor
{
    GENERATED_BODY()

public:
    AInteractiveTerminal()
    {
        // Widget Component 생성
        WidgetComponent = CreateDefaultSubobject<UWidgetComponent>(
            TEXT("WidgetComponent")
        );
        WidgetComponent->SetupAttachment(RootComponent);
        WidgetComponent->SetWidgetSpace(EWidgetSpace::World);
        WidgetComponent->SetDrawSize(FVector2D(1024, 768));
        WidgetComponent->SetTwoSided(true);

        // 상호작용 설정
        WidgetComponent->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
    }

protected:
    virtual void BeginPlay() override
    {
        Super::BeginPlay();

        // 위젯 클래스 설정
        WidgetComponent->SetWidgetClass(TerminalWidgetClass);

        // 위젯 인스턴스 접근
        if (UTerminalWidget* Widget = Cast<UTerminalWidget>(
            WidgetComponent->GetUserWidgetObject()))
        {
            Widget->SetTerminalOwner(this);
        }
    }

private:
    UPROPERTY(VisibleAnywhere)
    UWidgetComponent* WidgetComponent;

    UPROPERTY(EditDefaultsOnly)
    TSubclassOf<UTerminalWidget> TerminalWidgetClass;
};

// Widget Interaction Component 설정
UCLASS()
class AMyPlayerController : public APlayerController
{
    GENERATED_BODY()

protected:
    virtual void SetupInputComponent() override
    {
        Super::SetupInputComponent();

        // Widget Interaction Component 생성
        WidgetInteraction = NewObject<UWidgetInteractionComponent>(this);
        WidgetInteraction->SetupAttachment(GetRootComponent());
        WidgetInteraction->RegisterComponent();

        // 입력 바인딩
        InputComponent->BindAction("Interact", IE_Pressed,
            this, &AMyPlayerController::OnInteractPressed);
        InputComponent->BindAction("Interact", IE_Released,
            this, &AMyPlayerController::OnInteractReleased);
    }

    void OnInteractPressed()
    {
        WidgetInteraction->PressPointerKey(EKeys::LeftMouseButton);
    }

    void OnInteractReleased()
    {
        WidgetInteraction->ReleasePointerKey(EKeys::LeftMouseButton);
    }

private:
    UPROPERTY()
    UWidgetInteractionComponent* WidgetInteraction;
};
```

---

## 주요 클래스 요약

| 클래스 | 역할 |
|--------|------|
| `UWidget` | UMG 위젯 기본 클래스 |
| `UUserWidget` | 사용자 정의 위젯 (Blueprint 확장) |
| `UPanelWidget` | 다중 자식 위젯 컨테이너 |
| `UCanvasPanel` | 자유 배치 캔버스 |
| `UWidgetComponent` | 월드 공간 위젯 렌더링 |
| `UWidgetInteractionComponent` | 3D 위젯 상호작용 |
| `UWidgetAnimation` | 위젯 애니메이션 |
| `UWidgetBlueprintGeneratedClass` | Widget Blueprint 클래스 |

---

## 참고 자료

- [UMG UI Designer](https://docs.unrealengine.com/umg-ui-designer/)
- [Widget Blueprints](https://docs.unrealengine.com/widget-blueprints/)
- [UMG Animations](https://docs.unrealengine.com/umg-animations/)
