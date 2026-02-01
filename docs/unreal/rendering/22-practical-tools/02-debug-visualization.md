# 디버그 시각화

ViewMode, ShowFlag, Draw Debug 등 시각적 디버깅 도구를 분석합니다.

---

## ViewMode

```
┌─────────────────────────────────────────────────────────────────┐
│                       ViewModes                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기본 뷰모드:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Lit                  기본 라이팅 렌더링                 │   │
│  │  Unlit                라이팅 없음                        │   │
│  │  Wireframe            와이어프레임                       │   │
│  │  DetailLighting       디테일 라이팅                      │   │
│  │  LightingOnly         라이팅만                           │   │
│  │  LightComplexity      라이트 복잡도                      │   │
│  │  ReflectionOverride   반사 오버라이드                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화 뷰모드:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ShaderComplexity     셰이더 복잡도 (녹→빨)             │   │
│  │  QuadOverdraw         쿼드 오버드로                      │   │
│  │  ShaderComplexityContainedQuadOverdraw 복합             │   │
│  │  LightmapDensity      라이트맵 밀도                      │   │
│  │  StationaryLightOverlap 스테이셔너리 라이트 오버랩      │   │
│  │  LODColoration        LOD 레벨 색상화                    │   │
│  │  HLODColoration       HLOD 색상화                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  버퍼 시각화:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Buffer Overview      버퍼 오버뷰                        │   │
│  │  BaseColor            베이스 컬러                        │   │
│  │  Metallic             메탈릭                             │   │
│  │  Roughness            러프니스                           │   │
│  │  WorldNormal          월드 노멀                          │   │
│  │  AmbientOcclusion     앰비언트 오클루전                  │   │
│  │  SceneDepth           씬 뎁스                            │   │
│  │  Velocity             벨로시티                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### ViewMode 사용법

```cpp
// 콘솔에서 뷰모드 변경
ViewMode Lit
ViewMode Wireframe
ViewMode ShaderComplexity
ViewMode LightmapDensity

// 버퍼 시각화
ViewMode VisualizeBuffer BaseColor
ViewMode VisualizeBuffer WorldNormal
ViewMode VisualizeBuffer Roughness

// 코드에서 뷰모드 변경
void SetViewMode(EViewModeIndex ViewModeIndex)
{
    if (GEditor && GEditor->GetActiveViewport())
    {
        FEditorViewportClient* ViewportClient =
            static_cast<FEditorViewportClient*>(
                GEditor->GetActiveViewport()->GetClient()
            );

        if (ViewportClient)
        {
            ViewportClient->SetViewMode(ViewModeIndex);
        }
    }
}

// 게임에서 뷰모드 변경
void SetGameViewMode(APlayerController* PC, EViewModeIndex ViewMode)
{
    if (PC && PC->GetLocalPlayer())
    {
        UGameViewportClient* Viewport = PC->GetLocalPlayer()->ViewportClient;
        if (Viewport)
        {
            // ApplyViewMode 호출
            ApplyViewMode(ViewMode, true, Viewport->EngineShowFlags);
        }
    }
}
```

---

## 셰이더 복잡도 분석

```
┌─────────────────────────────────────────────────────────────────┐
│                  Shader Complexity Analysis                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ViewMode ShaderComplexity 색상 스케일:                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  초록 ─────► 노랑 ─────► 빨강 ─────► 흰색              │   │
│  │  좋음        보통        나쁨        매우나쁨            │   │
│  │                                                          │   │
│  │  Instruction Count:                                      │   │
│  │  0-50      50-100    100-200   200-400   400+           │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ViewMode QuadOverdraw:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  검정 ─────► 파랑 ─────► 빨강 ─────► 흰색              │   │
│  │  1x          2x          4x          8x+                │   │
│  │                                                          │   │
│  │  같은 픽셀이 몇 번 그려지는지 시각화                    │   │
│  │  투명 오브젝트, 파티클에서 주로 문제                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Draw Debug

```
┌─────────────────────────────────────────────────────────────────┐
│                    Draw Debug Functions                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기본 도형:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  DrawDebugLine()           라인                          │   │
│  │  DrawDebugPoint()          점                            │   │
│  │  DrawDebugBox()            박스                          │   │
│  │  DrawDebugSphere()         구                            │   │
│  │  DrawDebugCapsule()        캡슐                          │   │
│  │  DrawDebugCylinder()       실린더                        │   │
│  │  DrawDebugCone()           콘                            │   │
│  │  DrawDebugCircle()         원                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  고급 기능:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  DrawDebugString()         3D 텍스트                     │   │
│  │  DrawDebugArrow()          화살표                        │   │
│  │  DrawDebugDirectionalArrow() 방향 화살표                │   │
│  │  DrawDebugCoordinateSystem() 좌표계                     │   │
│  │  DrawDebugFrustum()        프러스텀                      │   │
│  │  DrawDebugCamera()         카메라                        │   │
│  │  DrawDebugMesh()           메시                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Draw Debug 사용법

```cpp
#include "DrawDebugHelpers.h"

void AMyActor::DebugDraw()
{
    UWorld* World = GetWorld();
    if (!World) return;

    FVector Location = GetActorLocation();
    FColor Color = FColor::Green;
    float Duration = 5.0f;  // 0 = 한 프레임만

    // 구 그리기
    DrawDebugSphere(
        World,
        Location,
        100.0f,           // 반경
        16,               // 세그먼트
        Color,
        false,            // Persistent
        Duration,
        0,                // Depth Priority
        2.0f              // 두께
    );

    // 박스 그리기
    FVector BoxExtent(50, 50, 50);
    DrawDebugBox(
        World,
        Location,
        BoxExtent,
        FQuat::Identity,
        FColor::Red,
        false,
        Duration
    );

    // 라인 그리기
    FVector Start = Location;
    FVector End = Location + GetActorForwardVector() * 200;
    DrawDebugLine(
        World,
        Start,
        End,
        FColor::Blue,
        false,
        Duration,
        0,
        3.0f
    );

    // 화살표 그리기
    DrawDebugDirectionalArrow(
        World,
        Start,
        End,
        50.0f,            // Arrow size
        FColor::Yellow,
        false,
        Duration
    );

    // 3D 텍스트
    DrawDebugString(
        World,
        Location + FVector(0, 0, 100),
        TEXT("Debug Text"),
        nullptr,
        FColor::White,
        Duration,
        true              // Shadow
    );

    // 좌표계 (X=빨강, Y=녹색, Z=파랑)
    DrawDebugCoordinateSystem(
        World,
        Location,
        GetActorRotation(),
        100.0f,           // Scale
        false,
        Duration
    );
}

// 복잡한 형태 그리기
void DrawDebugPath(const TArray<FVector>& PathPoints)
{
    UWorld* World = GetWorld();
    if (!World || PathPoints.Num() < 2) return;

    for (int32 i = 0; i < PathPoints.Num() - 1; ++i)
    {
        DrawDebugLine(
            World,
            PathPoints[i],
            PathPoints[i + 1],
            FColor::Cyan,
            false,
            5.0f,
            0,
            2.0f
        );

        // 각 포인트에 구
        DrawDebugSphere(
            World,
            PathPoints[i],
            20.0f,
            8,
            FColor::Cyan,
            false,
            5.0f
        );
    }
}
```

---

## 시각화 컴포넌트

```
┌─────────────────────────────────────────────────────────────────┐
│                 Visualization Components                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  에디터 전용 컴포넌트:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UArrowComponent        방향 표시 화살표                 │   │
│  │  UBillboardComponent    빌보드 스프라이트               │   │
│  │  USphereComponent       구 시각화                        │   │
│  │  UBoxComponent          박스 시각화                      │   │
│  │  UCapsuleComponent      캡슐 시각화                      │   │
│  │  UTextRenderComponent   3D 텍스트                        │   │
│  │  ULineBatchComponent    배치 라인                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  디버그 시각화:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UDrawFrustumComponent   프러스텀 시각화                │   │
│  │  UDebugSkelMeshComponent 스켈레탈 메시 디버그           │   │
│  │  UPhysicsConstraintComponent 물리 컨스트레인트          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 시각화 컴포넌트 사용

```cpp
UCLASS()
class ADebugActor : public AActor
{
    GENERATED_BODY()

public:
    ADebugActor()
    {
        // 루트 컴포넌트
        RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));

        // 방향 화살표 (에디터에서만 보임)
        ArrowComponent = CreateDefaultSubobject<UArrowComponent>(TEXT("Arrow"));
        ArrowComponent->SetupAttachment(RootComponent);
        ArrowComponent->SetArrowColor(FColor::Red);
        ArrowComponent->ArrowSize = 2.0f;

        // 빌보드 아이콘
        BillboardComponent = CreateDefaultSubobject<UBillboardComponent>(TEXT("Billboard"));
        BillboardComponent->SetupAttachment(RootComponent);

        // 범위 표시 구
        SphereComponent = CreateDefaultSubobject<USphereComponent>(TEXT("Sphere"));
        SphereComponent->SetupAttachment(RootComponent);
        SphereComponent->SetSphereRadius(200.0f);
        SphereComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        SphereComponent->SetHiddenInGame(true);  // 게임에서 숨김
    }

#if WITH_EDITOR
    virtual void PostEditChangeProperty(FPropertyChangedEvent& Event) override
    {
        Super::PostEditChangeProperty(Event);

        // 에디터에서 속성 변경 시 시각화 업데이트
        UpdateVisualization();
    }
#endif

private:
    UPROPERTY(VisibleAnywhere)
    UArrowComponent* ArrowComponent;

    UPROPERTY(VisibleAnywhere)
    UBillboardComponent* BillboardComponent;

    UPROPERTY(VisibleAnywhere)
    USphereComponent* SphereComponent;
};
```

---

## 커스텀 시각화 셰이더

```
┌─────────────────────────────────────────────────────────────────┐
│                Custom Visualization Shaders                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Material Editor에서 시각화 셰이더 생성:                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 노멀 시각화                                          │   │
│  │     WorldNormal * 0.5 + 0.5 → Emissive Color            │   │
│  │                                                          │   │
│  │  2. UV 시각화                                            │   │
│  │     TexCoord → Emissive Color                           │   │
│  │                                                          │   │
│  │  3. 버텍스 컬러 시각화                                   │   │
│  │     VertexColor → Emissive Color                        │   │
│  │                                                          │   │
│  │  4. 깊이 시각화                                          │   │
│  │     SceneDepth / MaxDepth → Grayscale                   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 디버그 머티리얼

```hlsl
// 노멀 시각화 (Material Function)
float3 VisualizeNormal(float3 WorldNormal)
{
    return WorldNormal * 0.5 + 0.5;
}

// UV 체커보드
float DebugCheckerboard(float2 UV, float Scale)
{
    float2 CheckerUV = floor(UV * Scale);
    float Checker = fmod(CheckerUV.x + CheckerUV.y, 2.0);
    return Checker;
}

// 밉맵 레벨 시각화
float3 VisualizeMipLevel(float2 UV)
{
    float MipLevel = Texture2DSample(Tex, Sampler, UV).a;  // DDX/DDY 기반

    // 색상 매핑
    float3 Colors[8] = {
        float3(1, 0, 0),   // Mip 0 - Red
        float3(1, 0.5, 0), // Mip 1 - Orange
        float3(1, 1, 0),   // Mip 2 - Yellow
        float3(0, 1, 0),   // Mip 3 - Green
        float3(0, 1, 1),   // Mip 4 - Cyan
        float3(0, 0, 1),   // Mip 5 - Blue
        float3(1, 0, 1),   // Mip 6 - Magenta
        float3(1, 1, 1)    // Mip 7+ - White
    };

    int Level = clamp((int)MipLevel, 0, 7);
    return Colors[Level];
}

// 월드 그리드
float3 DrawWorldGrid(float3 WorldPos, float GridSize)
{
    float2 GridUV = WorldPos.xy / GridSize;
    float2 Grid = abs(frac(GridUV) - 0.5);
    float Line = min(Grid.x, Grid.y);
    float GridLine = 1.0 - smoothstep(0.0, 0.02, Line);
    return GridLine;
}
```

---

## 런타임 디버그 드로잉

```cpp
// UGameplayStatics 디버그 함수
void RuntimeDebugDraw()
{
    // 라인 트레이스 시각화
    FHitResult HitResult;
    FVector Start = GetActorLocation();
    FVector End = Start + GetActorForwardVector() * 1000;

    bool bHit = GetWorld()->LineTraceSingleByChannel(
        HitResult,
        Start,
        End,
        ECC_Visibility
    );

    // 트레이스 라인 그리기
    DrawDebugLine(
        GetWorld(),
        Start,
        bHit ? HitResult.ImpactPoint : End,
        bHit ? FColor::Red : FColor::Green,
        false,
        -1,
        0,
        2.0f
    );

    // 히트 포인트 표시
    if (bHit)
    {
        DrawDebugSphere(GetWorld(), HitResult.ImpactPoint, 10.0f, 8, FColor::Red);
        DrawDebugDirectionalArrow(
            GetWorld(),
            HitResult.ImpactPoint,
            HitResult.ImpactPoint + HitResult.ImpactNormal * 50,
            20.0f,
            FColor::Blue
        );
    }
}

// HUD에 디버그 정보 표시
void AHUD::DrawHUD()
{
    Super::DrawHUD();

    if (bShowDebugInfo)
    {
        // 텍스트 표시
        DrawText(TEXT("FPS: ") + FString::FromInt(FMath::RoundToInt(1.0f / GetWorld()->DeltaTimeSeconds)),
            FColor::Green, 10, 10);

        // 크로스헤어
        DrawRect(FLinearColor::White, Canvas->SizeX / 2 - 1, Canvas->SizeY / 2 - 10, 2, 20);
        DrawRect(FLinearColor::White, Canvas->SizeX / 2 - 10, Canvas->SizeY / 2 - 1, 20, 2);
    }
}
```

---

## 주요 클래스 요약

| 클래스/함수 | 역할 |
|-------------|------|
| `DrawDebugLine()` | 라인 그리기 |
| `DrawDebugSphere()` | 구 그리기 |
| `DrawDebugBox()` | 박스 그리기 |
| `UArrowComponent` | 방향 화살표 컴포넌트 |
| `UBillboardComponent` | 빌보드 스프라이트 |
| `FEngineShowFlags` | Show 플래그 관리 |
| `EViewModeIndex` | 뷰모드 열거형 |

---

## 참고 자료

- [Debug Drawing](https://docs.unrealengine.com/debug-drawing/)
- [View Modes](https://docs.unrealengine.com/view-modes/)
- [ShowFlags](https://docs.unrealengine.com/showflags/)
