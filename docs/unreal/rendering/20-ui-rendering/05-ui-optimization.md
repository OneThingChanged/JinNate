# UI 최적화

UI 렌더링 성능 최적화 기법과 프로파일링 방법을 분석합니다.

---

## UI 성능 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                   UI Performance Overview                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UI 성능 병목:                                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  CPU 병목:                                               │   │
│  │  ├── Widget Tick (매 프레임 업데이트)                   │   │
│  │  ├── Layout Calculation (크기/위치 계산)                │   │
│  │  ├── Paint Pass (드로우 엘리먼트 생성)                  │   │
│  │  └── Garbage Collection (위젯 생성/삭제)                │   │
│  │                                                          │   │
│  │  GPU 병목:                                               │   │
│  │  ├── Draw Calls (배치 미병합)                           │   │
│  │  ├── Overdraw (중첩 투명 레이어)                        │   │
│  │  ├── Texture Sampling (고해상도 텍스처)                 │   │
│  │  └── Shader Complexity (복잡한 머티리얼)                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  목표:                                                          │
│  • 드로우콜 최소화                                              │
│  • 불필요한 업데이트 제거                                       │
│  • 캐싱 활용                                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Invalidation Box

```
┌─────────────────────────────────────────────────────────────────┐
│                     Invalidation Box                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Invalidation Box = 변경 시에만 자식 위젯 리페인트              │
│                                                                 │
│  동작 원리:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Without Invalidation Box:                               │   │
│  │  ┌────────────────────────────────────────────┐         │   │
│  │  │  Every Frame:                               │         │   │
│  │  │  Paint → Paint → Paint → Paint → ...       │         │   │
│  │  │  (변경 없어도 매번 다시 그림)               │         │   │
│  │  └────────────────────────────────────────────┘         │   │
│  │                                                          │   │
│  │  With Invalidation Box:                                  │   │
│  │  ┌────────────────────────────────────────────┐         │   │
│  │  │  Only When Changed:                         │         │   │
│  │  │  Paint → Cache → Cache → Paint → Cache     │         │   │
│  │  │  (변경 시에만 다시 그림)                    │         │   │
│  │  └────────────────────────────────────────────┘         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  사용 사례:                                                     │
│  • 정적 UI (배경, 프레임)                                       │
│  • 가끔 변경되는 UI (스코어보드, 인벤토리)                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Invalidation Box 사용

```cpp
// Widget Blueprint에서 Invalidation Box 설정
// 또는 C++에서:

UCLASS()
class UOptimizedHUD : public UUserWidget
{
    GENERATED_BODY()

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        // Invalidation Box 설정
        if (StaticContentBox)
        {
            // 캐시 활성화
            StaticContentBox->SetCanCache(true);

            // Volatility 설정 (변경 빈도)
            // - Static: 절대 변경 안 됨
            // - Prepass: Prepass에서만 업데이트
            // - NotPrepass: 일반 업데이트
        }
    }

    // 변경 시 명시적 무효화
    void UpdateScore(int32 NewScore)
    {
        ScoreText->SetText(FText::AsNumber(NewScore));

        // Invalidation Box에게 다시 그려야 함을 알림
        if (StaticContentBox)
        {
            StaticContentBox->InvalidateChildContent();
        }
    }

private:
    UPROPERTY(meta = (BindWidget))
    UInvalidationBox* StaticContentBox;

    UPROPERTY(meta = (BindWidget))
    UTextBlock* ScoreText;
};
```

---

## Retainer Box

```
┌─────────────────────────────────────────────────────────────────┐
│                       Retainer Box                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Retainer Box = 렌더 타겟에 위젯 캐싱                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Phase 설정:                                             │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │  RenderOnPhase: N                                 │   │   │
│  │  │  RenderOnInvalidation: true/false                 │   │   │
│  │  │                                                   │   │   │
│  │  │  예: Phase = 3                                    │   │   │
│  │  │  Frame 0: Render                                  │   │   │
│  │  │  Frame 1: Cache                                   │   │   │
│  │  │  Frame 2: Cache                                   │   │   │
│  │  │  Frame 3: Render                                  │   │   │
│  │  │  Frame 4: Cache                                   │   │   │
│  │  │  ...                                              │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  • N 프레임마다 한 번만 렌더링                                  │
│  • 이펙트 머티리얼 적용 가능                                    │
│                                                                 │
│  단점:                                                          │
│  • 추가 메모리 사용 (렌더 타겟)                                 │
│  • 업데이트 지연 발생                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Retainer Box 설정

```cpp
UCLASS()
class UMiniMapWidget : public UUserWidget
{
    GENERATED_BODY()

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        if (MiniMapRetainer)
        {
            // 3프레임마다 업데이트
            MiniMapRetainer->SetRenderingPhase(3, 0);

            // 또는 특정 조건에서만 업데이트
            MiniMapRetainer->SetRetainRendering(true);
        }
    }

    // 수동 업데이트 요청
    void RequestMiniMapUpdate()
    {
        if (MiniMapRetainer)
        {
            MiniMapRetainer->RequestRender();
        }
    }

private:
    UPROPERTY(meta = (BindWidget))
    URetainerBox* MiniMapRetainer;
};
```

---

## 배칭 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                    Batching Optimization                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  배칭 깨지는 원인:                                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. 텍스처 변경                                          │   │
│  │     ┌───────┐  ┌───────┐  ┌───────┐                     │   │
│  │     │ Tex A │  │ Tex B │  │ Tex A │  ← 3 Draw Calls     │   │
│  │     └───────┘  └───────┘  └───────┘                     │   │
│  │                                                          │   │
│  │  2. 머티리얼 변경                                        │   │
│  │     ┌───────┐  ┌───────┐  ┌───────┐                     │   │
│  │     │ Mat A │  │ Mat B │  │ Mat A │  ← 3 Draw Calls     │   │
│  │     └───────┘  └───────┘  └───────┘                     │   │
│  │                                                          │   │
│  │  3. 클리핑 변경                                          │   │
│  │     ┌───────────────────────────────┐                   │   │
│  │     │ Clip Zone A │ Clip Zone B     │  ← 배치 분리      │   │
│  │     └───────────────────────────────┘                   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화 방법:                                                   │
│  • 텍스처 아틀라스 사용                                         │
│  • 동일 머티리얼 그룹화                                         │
│  • 불필요한 클리핑 제거                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 텍스처 아틀라스

```cpp
// 텍스처 아틀라스 사용
// 여러 작은 이미지를 하나의 큰 텍스처에 배치

// Paper2D 스프라이트 사용 (아틀라스 자동 생성)
UPROPERTY(EditDefaultsOnly)
UPaperSprite* IconSprite;  // 아틀라스 참조

// 또는 수동 UV 지정
FSlateBrush AtlasBrush;
AtlasBrush.SetResourceObject(AtlasTexture);
AtlasBrush.SetUVRegion(FBox2D(
    FVector2D(0.0f, 0.0f),    // UV 시작
    FVector2D(0.25f, 0.25f)   // UV 끝 (첫 번째 쿼드)
));
```

### 위젯 계층 구조 최적화

```cpp
// 나쁜 예: 불필요하게 깊은 계층
// Canvas → Overlay → Border → Overlay → Image

// 좋은 예: 평면적 구조
// Canvas → Image

// Widget Blueprint 최적화 팁
// 1. 빈 Container 위젯 제거
// 2. 단일 자식 Overlay 제거
// 3. 불필요한 Border 제거
```

---

## Widget Visibility

```
┌─────────────────────────────────────────────────────────────────┐
│                    Widget Visibility                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Visibility 옵션:                                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Visible         ─► 보이고, 입력 받음, 렌더링           │   │
│  │                                                          │   │
│  │  Collapsed       ─► 안 보임, 공간 차지 안 함            │   │
│  │                      레이아웃/페인트 스킵               │   │
│  │                      (가장 효율적)                      │   │
│  │                                                          │   │
│  │  Hidden          ─► 안 보임, 공간 차지함                │   │
│  │                      페인트만 스킵                       │   │
│  │                                                          │   │
│  │  HitTestInvisible ─► 보임, 입력 안 받음                 │   │
│  │                                                          │   │
│  │  SelfHitTestInvisible ─► 자신만 입력 안 받음            │   │
│  │                          (자식은 받음)                   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  성능 팁:                                                       │
│  • 안 쓰는 위젯은 Hidden 대신 Collapsed 사용                   │
│  • 입력 불필요한 위젯은 HitTestInvisible                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Visibility 최적화

```cpp
UCLASS()
class UDynamicHUD : public UUserWidget
{
    GENERATED_BODY()

public:
    void ShowDamageIndicator()
    {
        // Collapsed에서 Visible로 전환
        DamageIndicator->SetVisibility(ESlateVisibility::Visible);

        // 타이머로 다시 숨김
        GetWorld()->GetTimerManager().SetTimer(
            HideTimer,
            [this]()
            {
                // Hidden이 아닌 Collapsed 사용
                DamageIndicator->SetVisibility(ESlateVisibility::Collapsed);
            },
            2.0f, false
        );
    }

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        // 입력 불필요한 장식 위젯
        if (BackgroundDecoration)
        {
            BackgroundDecoration->SetVisibility(
                ESlateVisibility::HitTestInvisible
            );
        }
    }

private:
    UPROPERTY(meta = (BindWidget))
    UWidget* DamageIndicator;

    UPROPERTY(meta = (BindWidget))
    UWidget* BackgroundDecoration;

    FTimerHandle HideTimer;
};
```

---

## 바인딩 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                   Binding Optimization                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Property Binding 문제:                                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  매 프레임:                                              │   │
│  │  TextBlock.Text ◄─── GetPlayerHealth()                   │   │
│  │                                                          │   │
│  │  • 변경 없어도 매 프레임 함수 호출                       │   │
│  │  • FText 객체 생성/비교                                  │   │
│  │  • Blueprint 바인딩은 더 느림                            │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  권장: 이벤트 기반 업데이트                                     │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  HealthChanged Event                                     │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  UpdateHealthDisplay()  ─► TextBlock.SetText()           │   │
│  │                                                          │   │
│  │  • 변경 시에만 업데이트                                  │   │
│  │  • 불필요한 비교 없음                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 이벤트 기반 업데이트

```cpp
// 나쁜 예: Property Binding
// Blueprint에서 Text 속성에 GetHealth() 바인딩
// → 매 프레임 호출됨

// 좋은 예: 이벤트 기반
UCLASS()
class UHealthBar : public UUserWidget
{
    GENERATED_BODY()

protected:
    virtual void NativeConstruct() override
    {
        Super::NativeConstruct();

        // 초기값 설정
        UpdateHealthDisplay(Character->GetHealth(), Character->GetMaxHealth());

        // 이벤트 구독
        Character->OnHealthChanged.AddDynamic(
            this, &UHealthBar::OnHealthChanged
        );
    }

    virtual void NativeDestruct() override
    {
        // 이벤트 구독 해제
        if (Character)
        {
            Character->OnHealthChanged.RemoveDynamic(
                this, &UHealthBar::OnHealthChanged
            );
        }

        Super::NativeDestruct();
    }

private:
    UFUNCTION()
    void OnHealthChanged(float NewHealth, float MaxHealth)
    {
        UpdateHealthDisplay(NewHealth, MaxHealth);
    }

    void UpdateHealthDisplay(float Current, float Max)
    {
        float Percent = Current / Max;
        HealthBar->SetPercent(Percent);
        HealthText->SetText(FText::FromString(
            FString::Printf(TEXT("%.0f / %.0f"), Current, Max)
        ));
    }

    UPROPERTY(meta = (BindWidget))
    UProgressBar* HealthBar;

    UPROPERTY(meta = (BindWidget))
    UTextBlock* HealthText;
};
```

---

## 프로파일링

```
┌─────────────────────────────────────────────────────────────────┐
│                     UI Profiling                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  프로파일링 도구:                                               │
│                                                                 │
│  1. Slate Stats                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  콘솔 명령: Slate.Stats 1                                │   │
│  │                                                          │   │
│  │  표시 정보:                                              │   │
│  │  • Num Widgets: 위젯 수                                  │   │
│  │  • Num Batches: 배치 수                                  │   │
│  │  • Vertices: 버텍스 수                                   │   │
│  │  • Invalidation: 무효화 수                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  2. Widget Reflector                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Window → Developer Tools → Widget Reflector             │   │
│  │                                                          │   │
│  │  기능:                                                   │   │
│  │  • 위젯 계층 구조 시각화                                 │   │
│  │  • 클리핑/배칭 상태 확인                                 │   │
│  │  • 히트 테스트 시각화                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  3. Unreal Insights                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Slate 채널 활성화:                                      │   │
│  │  -trace=slate,default                                    │   │
│  │                                                          │   │
│  │  세부 타이밍 정보 확인 가능                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 프로파일링 명령어

```cpp
// 콘솔 명령어
// Slate 통계 표시
Slate.Stats 1

// 배칭 디버그
Slate.ShowBatching 1

// 클리핑 시각화
Slate.ShowClipping 1

// 오버드로 시각화
Slate.DebugRenderingEnabled 1

// Widget Reflector 열기
WidgetReflector

// 코드에서 프로파일링
DECLARE_CYCLE_STAT(TEXT("MyWidget Paint"), STAT_MyWidgetPaint, STATGROUP_Slate);

int32 SMyWidget::OnPaint(...) const
{
    SCOPE_CYCLE_COUNTER(STAT_MyWidgetPaint);

    // 페인팅 코드
    return LayerId;
}
```

---

## 최적화 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                 Optimization Checklist                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  레이아웃:                                                      │
│  □ 불필요한 중첩 위젯 제거                                      │
│  □ 빈 Container 위젯 제거                                       │
│  □ Canvas Panel 대신 적절한 레이아웃 사용                       │
│                                                                 │
│  렌더링:                                                        │
│  □ 정적 콘텐츠에 Invalidation Box 사용                          │
│  □ 낮은 업데이트 빈도에 Retainer Box 사용                       │
│  □ 텍스처 아틀라스 활용                                         │
│  □ 동일 머티리얼 위젯 그룹화                                    │
│                                                                 │
│  업데이트:                                                      │
│  □ Property Binding 대신 이벤트 기반 업데이트                   │
│  □ 불필요한 Tick 비활성화                                       │
│  □ 조건부 업데이트 구현                                         │
│                                                                 │
│  가시성:                                                        │
│  □ Hidden 대신 Collapsed 사용                                   │
│  □ 장식 위젯에 HitTestInvisible 설정                            │
│  □ 화면 밖 위젯 비활성화                                        │
│                                                                 │
│  메모리:                                                        │
│  □ 위젯 풀링 사용 (리스트 아이템)                               │
│  □ 불필요한 위젯 생성 최소화                                    │
│  □ 대형 텍스처 스트리밍 활용                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 주요 클래스 요약

| 클래스 | 역할 |
|--------|------|
| `UInvalidationBox` | 변경 시에만 리페인트 |
| `URetainerBox` | 렌더 타겟 캐싱 |
| `FSlateBatch` | 렌더링 배치 |
| `FSlateStats` | 통계 수집 |
| `SWidgetReflector` | 디버그 도구 |

---

## 참고 자료

- [UMG Best Practices](https://docs.unrealengine.com/umg-best-practices/)
- [Slate Performance](https://docs.unrealengine.com/slate-performance/)
- [UI Profiling](https://docs.unrealengine.com/ui-profiling/)
