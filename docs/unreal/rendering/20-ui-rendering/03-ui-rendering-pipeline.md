# UI 렌더링 파이프라인

Slate의 렌더링 파이프라인과 Element Batching 시스템을 분석합니다.

---

## 렌더링 파이프라인 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                UI Rendering Pipeline Overview                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game Thread:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Tick       Layout      Paint       Element              │   │
│  │  Widgets →  Pass    →   Pass    →   Collection           │   │
│  │                                                          │   │
│  │  위젯 상태   크기/위치   드로우      FSlateDrawElement    │   │
│  │  업데이트   계산        명령 생성   리스트 생성           │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  Render Thread:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Element     Batch       RHI         GPU                 │   │
│  │  Sort    →   Merge   →   Submit  →   Render              │   │
│  │                                                          │   │
│  │  레이어      동일 상태    드로우콜   실제                 │   │
│  │  정렬        배치 병합   제출       렌더링               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Paint Pass

```
┌─────────────────────────────────────────────────────────────────┐
│                        Paint Pass                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  OnPaint() 호출 순서 (Top-Down):                                │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Root Widget                                              │  │
│  │  ├─► OnPaint() ─► Draw Background                        │  │
│  │  │                                                        │  │
│  │  ├─► Child A                                              │  │
│  │  │   └─► OnPaint() ─► Draw Content                       │  │
│  │  │                                                        │  │
│  │  └─► Child B                                              │  │
│  │      ├─► OnPaint() ─► Draw Background                    │  │
│  │      │                                                    │  │
│  │      └─► Child B.1                                        │  │
│  │          └─► OnPaint() ─► Draw Content                   │  │
│  │                                                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  결과: FSlateDrawElement 리스트 (페인터 알고리즘 순서)          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### OnPaint 구현

```cpp
// SWidget::OnPaint - 위젯 페인팅
int32 SMyWidget::OnPaint(
    const FPaintArgs& Args,
    const FGeometry& AllottedGeometry,
    const FSlateRect& MyCullingRect,
    FSlateWindowElementList& OutDrawElements,
    int32 LayerId,
    const FWidgetStyle& InWidgetStyle,
    bool bParentEnabled) const
{
    // 배경 그리기
    FSlateDrawElement::MakeBox(
        OutDrawElements,
        LayerId,
        AllottedGeometry.ToPaintGeometry(),
        BackgroundBrush,
        ESlateDrawEffect::None,
        BackgroundBrush->GetTint(InWidgetStyle)
    );

    // 레이어 증가
    LayerId++;

    // 텍스트 그리기
    FSlateDrawElement::MakeText(
        OutDrawElements,
        LayerId,
        AllottedGeometry.ToPaintGeometry(TextOffset, TextSize),
        DisplayText,
        Font,
        ESlateDrawEffect::None,
        TextColor
    );

    // 자식 위젯 페인팅
    LayerId = SCompoundWidget::OnPaint(
        Args,
        AllottedGeometry,
        MyCullingRect,
        OutDrawElements,
        LayerId,
        InWidgetStyle,
        bParentEnabled && IsEnabled()
    );

    return LayerId;
}
```

---

## FSlateDrawElement

```
┌─────────────────────────────────────────────────────────────────┐
│                    FSlateDrawElement Types                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Draw Element = 렌더링할 단일 프리미티브                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Element Type      Description                           │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  Box               사각형 (Brush 기반)                   │   │
│  │  Text              텍스트 렌더링                         │   │
│  │  Line              라인 드로잉                           │   │
│  │  Spline            스플라인 커브                         │   │
│  │  Gradient          그라디언트 박스                       │   │
│  │  Viewport          렌더 타겟/뷰포트                      │   │
│  │  Custom            커스텀 렌더러                         │   │
│  │  CachedBuffer      캐시된 버퍼                           │   │
│  │  Layer             레이어 분리                           │   │
│  │  PostProcess       포스트 프로세스 효과                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  공통 속성:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  • LayerId         정렬 순서                             │   │
│  │  • RenderTransform 변환 행렬                             │   │
│  │  • Tint            색조                                  │   │
│  │  • DrawEffects     효과 플래그                           │   │
│  │  • ClippingState   클리핑 상태                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Draw Element 생성

```cpp
// 다양한 Draw Element 생성 예시
void DrawUI(FSlateWindowElementList& OutDrawElements, int32 LayerId,
    const FGeometry& Geometry)
{
    // Box Element - 이미지/색상 박스
    FSlateDrawElement::MakeBox(
        OutDrawElements,
        LayerId,
        Geometry.ToPaintGeometry(),
        &ButtonBrush,                    // FSlateBrush
        ESlateDrawEffect::None,
        FLinearColor::White
    );

    // Text Element
    FSlateDrawElement::MakeText(
        OutDrawElements,
        LayerId + 1,
        Geometry.ToPaintGeometry(),
        FText::FromString(TEXT("Hello")),
        FCoreStyle::GetDefaultFontStyle("Regular", 14),
        ESlateDrawEffect::None,
        FLinearColor::Black
    );

    // Line Element
    TArray<FVector2D> Points;
    Points.Add(FVector2D(0, 0));
    Points.Add(FVector2D(100, 100));
    Points.Add(FVector2D(200, 50));

    FSlateDrawElement::MakeLines(
        OutDrawElements,
        LayerId + 2,
        Geometry.ToPaintGeometry(),
        Points,
        ESlateDrawEffect::None,
        FLinearColor::Red,
        true,           // bAntialias
        2.0f            // Thickness
    );

    // Gradient Element
    TArray<FSlateGradientStop> GradientStops;
    GradientStops.Add(FSlateGradientStop(FVector2D(0, 0), FLinearColor::Red));
    GradientStops.Add(FSlateGradientStop(FVector2D(1, 0), FLinearColor::Blue));

    FSlateDrawElement::MakeGradient(
        OutDrawElements,
        LayerId + 3,
        Geometry.ToPaintGeometry(),
        GradientStops,
        EOrientation::Orient_Horizontal,
        ESlateDrawEffect::None
    );

    // Spline Element
    FSlateDrawElement::MakeSpline(
        OutDrawElements,
        LayerId + 4,
        Geometry.ToPaintGeometry(),
        StartPoint, StartDir,
        EndPoint, EndDir,
        2.0f,           // Thickness
        ESlateDrawEffect::None,
        FLinearColor::Green
    );
}
```

---

## Element Batching

```
┌─────────────────────────────────────────────────────────────────┐
│                      Element Batching                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  목표: 드로우콜 최소화를 위한 엘리먼트 병합                      │
│                                                                 │
│  배칭 조건 (동일해야 병합 가능):                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Texture/Material                                       │   │
│  │ • Draw Effect                                            │   │
│  │ • Clipping State                                         │   │
│  │ • Layer ID (연속)                                        │   │
│  │ • Render Transform                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  배칭 전:                          배칭 후:                     │
│  ┌────────┐                       ┌────────────────────────┐   │
│  │ Box A  │ ─ Texture1           │                        │   │
│  ├────────┤                       │  Batch 1 (Texture1)    │   │
│  │ Box B  │ ─ Texture1    ──►    │  [Box A + Box B]       │   │
│  ├────────┤                       ├────────────────────────┤   │
│  │ Box C  │ ─ Texture2           │  Batch 2 (Texture2)    │   │
│  ├────────┤                       │  [Box C]               │   │
│  │ Text   │ ─ Font Atlas  ──►    ├────────────────────────┤   │
│  └────────┘                       │  Batch 3 (Font)        │   │
│                                   │  [Text]                │   │
│  4 Draw Calls                     └────────────────────────┘   │
│                                   3 Draw Calls                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Batch 구조

```cpp
// FSlateRenderBatch 구조
struct FSlateRenderBatch
{
    // 렌더링 리소스
    const FSlateShaderResource* ShaderResource;  // 텍스처
    const FSlateShaderResource* SecondaryResource;

    // 머티리얼
    const UMaterialInterface* Material;

    // 셰이더 타입
    ESlateShader ShaderType;

    // 드로우 효과
    ESlateDrawEffect DrawEffects;

    // 인스턴스 데이터
    TArray<FSlateVertex> Vertices;
    TArray<SlateIndex> Indices;

    // 클리핑
    int32 ClippingIndex;

    // 레이어 정보
    int32 LayerId;

    // 배칭 가능 여부 확인
    bool CanBatch(const FSlateRenderBatch& Other) const
    {
        return ShaderResource == Other.ShaderResource
            && Material == Other.Material
            && ShaderType == Other.ShaderType
            && DrawEffects == Other.DrawEffects
            && ClippingIndex == Other.ClippingIndex;
    }
};
```

---

## FSlateRenderer

```
┌─────────────────────────────────────────────────────────────────┐
│                      FSlateRenderer                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  렌더러 계층:                                                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FSlateRenderer (Abstract Interface)                     │   │
│  │       │                                                  │   │
│  │       ├── FSlateRHIRenderer (RHI 기반)                  │   │
│  │       │   └── 실제 GPU 렌더링                           │   │
│  │       │                                                  │   │
│  │       └── FSlateNullRenderer (Null 렌더러)              │   │
│  │           └── 서버 빌드용                               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  FSlateRHIRenderer 파이프라인:                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  DrawWindow()                                            │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  UpdateBuffers()  ─► 버텍스/인덱스 버퍼 업데이트         │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  RenderBatches()  ─► 배치별 드로우콜                     │   │
│  │       │                                                  │   │
│  │       ▼                                                  │   │
│  │  Present()        ─► 화면 출력                           │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### RHI 렌더링

```cpp
// FSlateRHIRenderer - 배치 렌더링
void FSlateRHIRenderer::DrawWindow_RenderThread(
    FRHICommandListImmediate& RHICmdList,
    FSlateBackBuffer& BackBuffer,
    FSlateWindowElementList& WindowElementList,
    bool bLockToVsync)
{
    // 렌더 타겟 설정
    FRHIRenderPassInfo RPInfo(
        BackBuffer.GetRenderTargetTexture(),
        ERenderTargetActions::Load_Store
    );
    RHICmdList.BeginRenderPass(RPInfo, TEXT("SlateUI"));

    // 뷰포트 설정
    RHICmdList.SetViewport(0, 0, 0.0f,
        BackBuffer.GetSizeX(), BackBuffer.GetSizeY(), 1.0f);

    // 배치 렌더링
    for (const FSlateRenderBatch& Batch : Batches)
    {
        RenderBatch(RHICmdList, Batch);
    }

    RHICmdList.EndRenderPass();
}

void FSlateRHIRenderer::RenderBatch(
    FRHICommandListImmediate& RHICmdList,
    const FSlateRenderBatch& Batch)
{
    // PSO 설정
    FGraphicsPipelineStateInitializer PSOInit;
    PSOInit.BoundShaderState.VertexDeclarationRHI = GSlateVertexDeclaration.VertexDeclarationRHI;
    PSOInit.BoundShaderState.VertexShaderRHI = VertexShader.GetVertexShader();
    PSOInit.BoundShaderState.PixelShaderRHI = GetPixelShader(Batch.ShaderType);
    PSOInit.BlendState = GetBlendState(Batch.DrawEffects);
    PSOInit.DepthStencilState = TStaticDepthStencilState<false, CF_Always>::GetRHI();

    SetGraphicsPipelineState(RHICmdList, PSOInit);

    // 텍스처 바인딩
    if (Batch.ShaderResource)
    {
        SetTextureParameter(RHICmdList, Batch.ShaderResource->TextureRHI);
    }

    // 드로우 호출
    RHICmdList.SetStreamSource(0, VertexBuffer, 0);
    RHICmdList.DrawIndexedPrimitive(
        IndexBuffer,
        Batch.VertexOffset,
        0,
        Batch.NumVertices,
        Batch.IndexOffset,
        Batch.NumIndices / 3,
        1
    );
}
```

---

## 클리핑 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                     Clipping System                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  클리핑 = 위젯 영역 외부 픽셀 제거                               │
│                                                                 │
│  클리핑 방식:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. Scissor Clipping (하드웨어)                         │   │
│  │     ┌──────────────┐                                    │   │
│  │     │  ┌────────┐  │  Scissor Rect로 축-정렬 사각형     │   │
│  │     │  │ Visible │  │  클리핑 (GPU 하드웨어 가속)       │   │
│  │     │  │  Area   │  │                                    │   │
│  │     │  └────────┘  │                                    │   │
│  │     └──────────────┘                                    │   │
│  │                                                          │   │
│  │  2. Stencil Clipping (복잡한 형태)                      │   │
│  │     ┌──────────────┐                                    │   │
│  │     │   ╭────╮     │  회전된 사각형이나 복잡한          │   │
│  │     │  ╱      ╲    │  형태의 클리핑 마스크              │   │
│  │     │ ╲        ╱   │                                    │   │
│  │     │   ╰────╯     │                                    │   │
│  │     └──────────────┘                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  클리핑 스택:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Window Clip  ─► Panel Clip  ─► ScrollBox Clip          │   │
│  │      │              │               │                    │   │
│  │      ▼              ▼               ▼                    │   │
│  │  교차 영역 = 최종 클리핑 영역                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 클리핑 구현

```cpp
// 클리핑 설정
int32 SScrollBox::OnPaint(
    const FPaintArgs& Args,
    const FGeometry& AllottedGeometry,
    const FSlateRect& MyCullingRect,
    FSlateWindowElementList& OutDrawElements,
    int32 LayerId,
    const FWidgetStyle& InWidgetStyle,
    bool bParentEnabled) const
{
    // 스크롤 영역에 클리핑 적용
    const bool bClippingNeeded = true;

    if (bClippingNeeded)
    {
        // 클리핑 영역 푸시
        OutDrawElements.PushClip(
            FSlateClippingZone(AllottedGeometry)
        );
    }

    // 콘텐츠 렌더링 (클리핑 적용됨)
    LayerId = SCompoundWidget::OnPaint(
        Args,
        AllottedGeometry,
        MyCullingRect,
        OutDrawElements,
        LayerId,
        InWidgetStyle,
        bParentEnabled
    );

    if (bClippingNeeded)
    {
        // 클리핑 영역 팝
        OutDrawElements.PopClip();
    }

    return LayerId;
}

// 클리핑 존 정의
struct FSlateClippingZone
{
    // 축-정렬 클리핑 (Scissor)
    bool IsAxisAligned() const
    {
        return bIsAxisAligned;
    }

    // 클리핑 영역
    FSlateRect GetBoundingBox() const
    {
        return BoundingBox;
    }

    // 스텐실 클리핑용 버텍스
    const TArray<FVector2D>& GetStencilVertices() const
    {
        return StencilVertices;
    }

private:
    bool bIsAxisAligned;
    FSlateRect BoundingBox;
    TArray<FVector2D> StencilVertices;
};
```

---

## 레이어 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                       Layer System                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Layer ID = 렌더링 순서 결정                                    │
│                                                                 │
│  레이어 순서:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Layer 0  ─── Background                                 │   │
│  │     ▲                                                    │   │
│  │     │                                                    │   │
│  │  Layer 1  ─── Content                                    │   │
│  │     ▲                                                    │   │
│  │     │                                                    │   │
│  │  Layer 2  ─── Overlay                                    │   │
│  │     ▲                                                    │   │
│  │     │                                                    │   │
│  │  Layer 3  ─── Tooltip                                    │   │
│  │     ▲                                                    │   │
│  │     │                                                    │   │
│  │  Layer 4  ─── Drag & Drop                                │   │
│  │                                                          │   │
│  │  높은 Layer = 앞에 렌더링                                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 레이어 사용

```cpp
int32 SMyWidget::OnPaint(...) const
{
    int32 CurrentLayer = LayerId;

    // 배경 레이어
    FSlateDrawElement::MakeBox(
        OutDrawElements,
        CurrentLayer,
        AllottedGeometry.ToPaintGeometry(),
        BackgroundBrush
    );

    // 콘텐츠 레이어 (배경 위)
    CurrentLayer++;
    FSlateDrawElement::MakeText(
        OutDrawElements,
        CurrentLayer,
        AllottedGeometry.ToPaintGeometry(),
        ContentText,
        ContentFont
    );

    // 오버레이 레이어 (콘텐츠 위)
    CurrentLayer++;
    if (bShowOverlay)
    {
        FSlateDrawElement::MakeBox(
            OutDrawElements,
            CurrentLayer,
            AllottedGeometry.ToPaintGeometry(),
            OverlayBrush
        );
    }

    // 자식 위젯 페인팅
    return PaintArrangedChildren(Args, AllottedGeometry, MyCullingRect,
        OutDrawElements, CurrentLayer + 1, InWidgetStyle, bParentEnabled);
}
```

---

## 주요 클래스 요약

| 클래스 | 역할 |
|--------|------|
| `FSlateDrawElement` | 단일 드로우 프리미티브 |
| `FSlateWindowElementList` | 윈도우의 엘리먼트 리스트 |
| `FSlateRenderBatch` | 배치된 렌더링 데이터 |
| `FSlateRenderer` | 렌더링 인터페이스 |
| `FSlateRHIRenderer` | RHI 기반 렌더러 |
| `FSlateClippingZone` | 클리핑 영역 정의 |
| `FSlateVertex` | UI 버텍스 데이터 |
| `FSlateBrush` | 브러시 (이미지/색상) |

---

## 참고 자료

- [Slate Rendering](https://docs.unrealengine.com/slate-rendering/)
- [UI Performance](https://docs.unrealengine.com/ui-performance/)
- [Slate Clipping](https://docs.unrealengine.com/slate-clipping/)
