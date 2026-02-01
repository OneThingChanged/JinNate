# Slate 프레임워크

언리얼 엔진의 저수준 UI 프레임워크인 Slate의 아키텍처를 분석합니다.

---

## Slate 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                    Slate Framework Overview                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Slate = 언리얼 엔진의 플랫폼 독립적 UI 프레임워크               │
│                                                                 │
│  특징:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 완전한 C++ 구현 (Blueprint 없음)                       │   │
│  │ • 선언적 구문 (Declarative Syntax)                       │   │
│  │ • 반응형 레이아웃 (Responsive Layout)                    │   │
│  │ • 스타일 시스템 (Styling System)                         │   │
│  │ • 입력 이벤트 처리 (Input Handling)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  사용처:                                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Unreal       │  │ Blueprint    │  │ Custom       │         │
│  │ Editor       │  │ Editor       │  │ Tools        │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## SWidget 계층 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    SWidget Class Hierarchy                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                        SWidget                                  │
│                           │                                     │
│           ┌───────────────┼───────────────┐                     │
│           │               │               │                     │
│           ▼               ▼               ▼                     │
│     SLeafWidget    SCompoundWidget    SPanel                    │
│           │               │               │                     │
│     ┌─────┴─────┐   ┌─────┴─────┐   ┌─────┴─────┐              │
│     │           │   │           │   │           │              │
│     ▼           ▼   ▼           ▼   ▼           ▼              │
│  STextBlock  SImage SButton  SBorder SOverlay  SCanvas          │
│                         │                 │                     │
│                    SCheckBox          SHorizontalBox            │
│                                            │                    │
│                                       SVerticalBox              │
│                                            │                    │
│                                       SScrollBox                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 위젯 카테고리

```cpp
// Leaf Widget - 자식 없음
class SLeafWidget : public SWidget
{
    // 단순 표시용 위젯
    // STextBlock, SImage, SSpacer
};

// Compound Widget - 단일 자식
class SCompoundWidget : public SWidget
{
protected:
    // ChildSlot으로 단일 자식 관리
    FSimpleSlot ChildSlot;
};

// Panel Widget - 다중 자식
class SPanel : public SWidget
{
protected:
    // Children 배열로 다중 자식 관리
    TPanelChildren<FSlot> Children;
};
```

---

## 선언적 구문

```
┌─────────────────────────────────────────────────────────────────┐
│                    Declarative Syntax                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Slate는 연산자 오버로딩을 통한 선언적 UI 정의 지원              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  SNew()       - 새 위젯 생성                            │   │
│  │  SAssignNew() - 생성 + 변수 할당                        │   │
│  │  + operator   - 자식 위젯 추가                          │   │
│  │  . operator   - 속성 설정                               │   │
│  │  [] operator  - 슬롯 속성 설정                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 구문 예시

```cpp
// 기본 위젯 생성
TSharedRef<SWidget> CreateUI()
{
    return SNew(SVerticalBox)

        // 첫 번째 슬롯
        + SVerticalBox::Slot()
        .AutoHeight()
        .Padding(10.0f)
        [
            SNew(STextBlock)
            .Text(LOCTEXT("Title", "제목"))
            .Font(FCoreStyle::GetDefaultFontStyle("Bold", 24))
        ]

        // 두 번째 슬롯
        + SVerticalBox::Slot()
        .FillHeight(1.0f)
        .Padding(10.0f)
        [
            SNew(SBorder)
            .BorderImage(FEditorStyle::GetBrush("ToolPanel.GroupBorder"))
            [
                SNew(SScrollBox)
                + SScrollBox::Slot()
                [
                    CreateContentWidget()
                ]
            ]
        ]

        // 버튼 슬롯
        + SVerticalBox::Slot()
        .AutoHeight()
        .HAlign(HAlign_Right)
        .Padding(10.0f)
        [
            SNew(SButton)
            .Text(LOCTEXT("OK", "확인"))
            .OnClicked(this, &SMyWidget::OnOKClicked)
        ];
}
```

---

## 레이아웃 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                      Layout System                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Two-Pass Layout Algorithm:                                     │
│                                                                 │
│  Pass 1: Measure (Bottom-Up)                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Leaf         Parent         Root                        │   │
│  │  Widgets  →   Widgets   →   Widget                       │   │
│  │                                                          │   │
│  │  "나는 이만큼   "자식들이      "전체 크기               │   │
│  │   필요해"       이만큼 필요"    결정됨"                  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Pass 2: Arrange (Top-Down)                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Root          Parent         Leaf                       │   │
│  │  Widget   →    Widgets   →   Widgets                     │   │
│  │                                                          │   │
│  │  "전체 영역     "각 자식에게    "최종 위치               │   │
│  │   할당"         할당"           확정"                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Desired Size 계산

```cpp
// SWidget::ComputeDesiredSize - 위젯이 원하는 크기 계산
FVector2D SMyWidget::ComputeDesiredSize(float LayoutScaleMultiplier) const
{
    // 자식 위젯들의 desired size 합산
    FVector2D TotalSize(0, 0);

    for (int32 i = 0; i < Children.Num(); ++i)
    {
        FVector2D ChildSize = Children[i].GetWidget()->GetDesiredSize();
        TotalSize.X = FMath::Max(TotalSize.X, ChildSize.X);
        TotalSize.Y += ChildSize.Y;
    }

    // 패딩 추가
    TotalSize += Padding.GetDesiredSize();

    return TotalSize;
}
```

### 레이아웃 배치

```cpp
// SWidget::ArrangeChildren - 자식 위젯 배치
void SVerticalBox::OnArrangeChildren(
    const FGeometry& AllottedGeometry,
    FArrangedChildren& ArrangedChildren) const
{
    float CurrentY = 0;

    for (int32 i = 0; i < Children.Num(); ++i)
    {
        const FSlot& Slot = Children[i];
        TSharedRef<SWidget> Widget = Slot.GetWidget();

        // 슬롯 크기 계산
        float SlotHeight = 0;
        if (Slot.SizeParam.SizeRule == FSizeParam::SizeRule_Auto)
        {
            SlotHeight = Widget->GetDesiredSize().Y;
        }
        else // Fill
        {
            SlotHeight = RemainingSpace * Slot.SizeParam.Value;
        }

        // 자식 배치
        FVector2D ChildOffset(0, CurrentY);
        FVector2D ChildSize(AllottedGeometry.GetLocalSize().X, SlotHeight);

        ArrangedChildren.AddWidget(
            AllottedGeometry.MakeChild(Widget, ChildOffset, ChildSize)
        );

        CurrentY += SlotHeight;
    }
}
```

---

## 슬롯 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                       Slot System                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  슬롯 = 자식 위젯 + 레이아웃 속성                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FSlot                                                   │   │
│  │  ├── TSharedRef<SWidget> Widget                         │   │
│  │  ├── FSizeParam SizeParam                               │   │
│  │  │   ├── Auto     - 자식 크기에 맞춤                    │   │
│  │  │   ├── Fill     - 남은 공간 채움                      │   │
│  │  │   └── Stretch  - 비율에 따라 확장                    │   │
│  │  ├── FMargin Padding                                    │   │
│  │  ├── EHorizontalAlignment HAlign                        │   │
│  │  └── EVerticalAlignment VAlign                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  정렬 옵션:                                                     │
│  ┌──────────────┐  ┌──────────────┐                            │
│  │ Horizontal   │  │ Vertical     │                            │
│  ├──────────────┤  ├──────────────┤                            │
│  │ HAlign_Fill  │  │ VAlign_Fill  │                            │
│  │ HAlign_Left  │  │ VAlign_Top   │                            │
│  │ HAlign_Center│  │ VAlign_Center│                            │
│  │ HAlign_Right │  │ VAlign_Bottom│                            │
│  └──────────────┘  └──────────────┘                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 슬롯 사용 예시

```cpp
SNew(SHorizontalBox)

// Auto 크기 - 아이콘
+ SHorizontalBox::Slot()
.AutoWidth()
.VAlign(VAlign_Center)
.Padding(4, 0)
[
    SNew(SImage)
    .Image(FEditorStyle::GetBrush("ContentBrowser.AssetIcon"))
]

// Fill 크기 - 텍스트 (남은 공간 모두 사용)
+ SHorizontalBox::Slot()
.FillWidth(1.0f)
.VAlign(VAlign_Center)
[
    SNew(STextBlock)
    .Text(AssetName)
]

// Auto 크기 - 버튼
+ SHorizontalBox::Slot()
.AutoWidth()
.Padding(4, 0)
[
    SNew(SButton)
    .Text(LOCTEXT("Edit", "편집"))
]
```

---

## 입력 처리

```
┌─────────────────────────────────────────────────────────────────┐
│                    Input Event Flow                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  OS Input → FSlateApplication → Widget Tree → Target Widget     │
│                                                                 │
│  이벤트 라우팅:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. Hit Test (마우스 위치 → 대상 위젯 찾기)              │   │
│  │     ┌──────────┐                                         │   │
│  │     │  Root    │  Mouse Position: (150, 200)             │   │
│  │     │  ├─ A    │  ────────────────────────►              │   │
│  │     │  │  └─ B │  Hit: Widget B                          │   │
│  │     │  └─ C    │                                         │   │
│  │     └──────────┘                                         │   │
│  │                                                          │   │
│  │  2. Event Bubbling (대상에서 루트로 이벤트 전파)         │   │
│  │     Widget B → Widget A → Root                           │   │
│  │     (Handled가 되면 전파 중단)                           │   │
│  │                                                          │   │
│  │  3. Event Tunneling (루트에서 대상으로 미리 알림)        │   │
│  │     Root → Widget A → Widget B                           │   │
│  │     (Preview 이벤트)                                     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 이벤트 핸들러

```cpp
class SMyWidget : public SCompoundWidget
{
public:
    SLATE_BEGIN_ARGS(SMyWidget) {}
        SLATE_EVENT(FOnClicked, OnClicked)
    SLATE_END_ARGS()

    void Construct(const FArguments& InArgs)
    {
        OnClicked = InArgs._OnClicked;
    }

    // 마우스 버튼 다운
    virtual FReply OnMouseButtonDown(
        const FGeometry& MyGeometry,
        const FPointerEvent& MouseEvent) override
    {
        if (MouseEvent.GetEffectingButton() == EKeys::LeftMouseButton)
        {
            bIsPressed = true;
            return FReply::Handled().CaptureMouse(SharedThis(this));
        }
        return FReply::Unhandled();
    }

    // 마우스 버튼 업
    virtual FReply OnMouseButtonUp(
        const FGeometry& MyGeometry,
        const FPointerEvent& MouseEvent) override
    {
        if (MouseEvent.GetEffectingButton() == EKeys::LeftMouseButton)
        {
            bIsPressed = false;

            // 클릭 이벤트 발생
            if (OnClicked.IsBound())
            {
                return OnClicked.Execute();
            }

            return FReply::Handled().ReleaseMouseCapture();
        }
        return FReply::Unhandled();
    }

    // 키보드 입력
    virtual FReply OnKeyDown(
        const FGeometry& MyGeometry,
        const FKeyEvent& KeyEvent) override
    {
        if (KeyEvent.GetKey() == EKeys::Enter)
        {
            // Enter 키 처리
            return FReply::Handled();
        }
        return FReply::Unhandled();
    }

private:
    FOnClicked OnClicked;
    bool bIsPressed = false;
};
```

---

## 스타일 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                      Style System                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FSlateStyleSet:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  StyleSet                                                │   │
│  │  ├── Brushes (FSlateBrush)                              │   │
│  │  │   ├── "Button.Normal"                                │   │
│  │  │   ├── "Button.Hovered"                               │   │
│  │  │   └── "Button.Pressed"                               │   │
│  │  ├── Fonts (FSlateFontInfo)                             │   │
│  │  │   ├── "NormalText"                                   │   │
│  │  │   └── "HeaderText"                                   │   │
│  │  ├── Colors (FSlateColor)                               │   │
│  │  │   ├── "AccentColor"                                  │   │
│  │  │   └── "TextColor"                                    │   │
│  │  └── Margins (FMargin)                                  │   │
│  │      └── "ButtonPadding"                                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 스타일 정의

```cpp
// 커스텀 스타일셋 정의
class FMySlateStyle
{
public:
    static void Initialize()
    {
        if (!StyleInstance.IsValid())
        {
            StyleInstance = MakeShareable(new FSlateStyleSet("MyStyle"));
            StyleInstance->SetContentRoot(
                FPaths::EngineContentDir() / TEXT("Slate/MyStyle")
            );

            // 브러시 등록
            StyleInstance->Set(
                "MyStyle.Button.Normal",
                new FSlateBoxBrush(
                    "Button_Normal",
                    FMargin(8.0f/32.0f),
                    FLinearColor(0.2f, 0.2f, 0.2f)
                )
            );

            // 폰트 등록
            StyleInstance->Set(
                "MyStyle.NormalText",
                FSlateFontInfo(
                    FPaths::EngineContentDir() / TEXT("Slate/Fonts/Roboto-Regular.ttf"),
                    12
                )
            );

            // 스타일 등록
            FSlateStyleRegistry::RegisterSlateStyle(*StyleInstance);
        }
    }

    static const ISlateStyle& Get()
    {
        return *StyleInstance;
    }

private:
    static TSharedPtr<FSlateStyleSet> StyleInstance;
};

// 스타일 사용
SNew(SButton)
.ButtonStyle(&FMySlateStyle::Get(), "MyStyle.Button")
.TextStyle(&FMySlateStyle::Get(), "MyStyle.NormalText")
.Text(LOCTEXT("MyButton", "클릭"))
```

---

## FSlateApplication

```
┌─────────────────────────────────────────────────────────────────┐
│                    FSlateApplication                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  역할:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 윈도우 관리                                            │   │
│  │ • 입력 이벤트 디스패치                                   │   │
│  │ • 위젯 트리 관리                                         │   │
│  │ • 틱 및 렌더링 조정                                      │   │
│  │ • 포커스 관리                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  주요 메서드:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ AddWindow()         - 새 윈도우 추가                     │   │
│  │ PushMenu()          - 메뉴 푸시                          │   │
│  │ SetKeyboardFocus()  - 키보드 포커스 설정                 │   │
│  │ SetAllUserFocus()   - 모든 사용자 포커스 설정            │   │
│  │ ProcessInput()      - 입력 처리                          │   │
│  │ Tick()              - 프레임 업데이트                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 윈도우 생성

```cpp
// 새 윈도우 생성 및 표시
void ShowMyWindow()
{
    TSharedRef<SWindow> Window = SNew(SWindow)
        .Title(LOCTEXT("MyWindow", "내 창"))
        .ClientSize(FVector2D(800, 600))
        .SupportsMinimize(true)
        .SupportsMaximize(true)
        [
            SNew(SMyWidget)
        ];

    // 윈도우 추가
    FSlateApplication::Get().AddWindow(Window);
}

// 모달 다이얼로그
void ShowModalDialog()
{
    TSharedRef<SWindow> Dialog = SNew(SWindow)
        .Title(LOCTEXT("Confirm", "확인"))
        .ClientSize(FVector2D(400, 200))
        .IsTopmostWindow(true)
        .SizingRule(ESizingRule::Autosized);

    Dialog->SetContent(
        SNew(SVerticalBox)
        + SVerticalBox::Slot()
        [
            SNew(STextBlock).Text(LOCTEXT("Message", "계속하시겠습니까?"))
        ]
        + SVerticalBox::Slot()
        .AutoHeight()
        [
            SNew(SHorizontalBox)
            + SHorizontalBox::Slot()
            [
                SNew(SButton)
                .Text(LOCTEXT("Yes", "예"))
                .OnClicked_Lambda([Dialog]()
                {
                    Dialog->RequestDestroyWindow();
                    return FReply::Handled();
                })
            ]
        ]
    );

    FSlateApplication::Get().AddModalWindow(Dialog, ParentWindow);
}
```

---

## 주요 클래스 요약

| 클래스 | 역할 |
|--------|------|
| `SWidget` | 모든 Slate 위젯의 기본 클래스 |
| `SCompoundWidget` | 단일 자식을 가지는 복합 위젯 |
| `SPanel` | 다중 자식을 가지는 패널 위젯 |
| `SLeafWidget` | 자식 없는 리프 위젯 |
| `FSlateApplication` | Slate 시스템 관리자 |
| `FSlateStyleSet` | 스타일 정의 컨테이너 |
| `FSlot` | 자식 위젯과 레이아웃 속성 |
| `FGeometry` | 위젯의 위치와 크기 정보 |

---

## 참고 자료

- [Slate Architecture](https://docs.unrealengine.com/slate-architecture/)
- [Creating Slate Widgets](https://docs.unrealengine.com/creating-slate-widgets/)
- [Slate Style Sets](https://docs.unrealengine.com/slate-styles/)
