# AR/MR 렌더링

증강현실(AR)과 혼합현실(MR) 렌더링의 특수 기법을 분석합니다.

---

## AR 렌더링 개요

### 패스스루 렌더링

```
┌─────────────────────────────────────────────────────────────────┐
│                    Passthrough Rendering                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Video See-Through (VST):                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  카메라        처리          합성          디스플레이    │   │
│  │  ┌───┐       ┌───┐        ┌───┐         ┌───┐          │   │
│  │  │ ◎ │ ───▶ │ ≡ │ ───▶  │ ⊕ │ ───▶   │ ▣ │          │   │
│  │  └───┘       └───┘        └───┘         └───┘          │   │
│  │   실제        왜곡         가상           최종           │   │
│  │   환경        보정        오브젝트        출력           │   │
│  │                                                          │   │
│  │  장점: 완전한 디지털 제어, 깊이 오클루전 가능            │   │
│  │  단점: 지연, 해상도 제한                                 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Optical See-Through (OST):                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  실제 환경      반투명 디스플레이     눈                 │   │
│  │    ▓▓▓▓▓   ──▶  ┌─────────────┐  ──▶  ◉               │   │
│  │                 │ + 가상 오브젝트│                       │   │
│  │                 └─────────────┘                         │   │
│  │                                                          │   │
│  │  장점: 지연 없음, 자연스러움                             │   │
│  │  단점: 밝기 제한, 오클루전 어려움                        │   │
│  │                                                          │   │
│  │  예: HoloLens, Magic Leap                               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Quest 패스스루

```cpp
// Quest Passthrough 설정
void EnablePassthrough()
{
    // OpenXR Passthrough 확장 활성화
    XrPassthroughFB Passthrough = XR_NULL_HANDLE;
    XrPassthroughLayerFB PassthroughLayer = XR_NULL_HANDLE;

    // Passthrough 생성
    XrPassthroughCreateInfoFB CreateInfo = {};
    CreateInfo.type = XR_TYPE_PASSTHROUGH_CREATE_INFO_FB;
    CreateInfo.flags = 0;

    xrCreatePassthroughFB(Session, &CreateInfo, &Passthrough);

    // Passthrough 시작
    xrPassthroughStartFB(Passthrough);

    // 레이어 생성
    XrPassthroughLayerCreateInfoFB LayerInfo = {};
    LayerInfo.type = XR_TYPE_PASSTHROUGH_LAYER_CREATE_INFO_FB;
    LayerInfo.passthrough = Passthrough;
    LayerInfo.purpose = XR_PASSTHROUGH_LAYER_PURPOSE_RECONSTRUCTION_FB;

    xrCreatePassthroughLayerFB(Session, &LayerInfo, &PassthroughLayer);
}

// UE 설정
// Project Settings → Plugins → OculusXR
// Enable Passthrough = True
// Passthrough Layering = Underlay
```

---

## 공간 이해

### Scene Understanding

```
┌─────────────────────────────────────────────────────────────────┐
│                    Scene Understanding                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  공간 분석 결과:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │     ┌─────────────────────────────────────┐              │   │
│  │     │ ░░░░░░░░░ Ceiling ░░░░░░░░░░░      │              │   │
│  │     │                                     │              │   │
│  │     │   Wall      ╔════════╗     Wall    │              │   │
│  │     │   ████      ║ Window ║     ████    │              │   │
│  │     │   ████      ╚════════╝     ████    │              │   │
│  │     │   ████                     ████    │              │   │
│  │     │   ████    ┌────────┐      ████    │              │   │
│  │     │   ████    │  Desk  │      ████    │              │   │
│  │     │           └────────┘               │              │   │
│  │     │ ▓▓▓▓▓▓▓▓▓▓ Floor ▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │              │   │
│  │     └─────────────────────────────────────┘              │   │
│  │                                                          │   │
│  │  탐지 요소:                                               │   │
│  │  • Floor (바닥)                                          │   │
│  │  • Ceiling (천장)                                        │   │
│  │  • Wall (벽)                                             │   │
│  │  • Window/Door Opening                                   │   │
│  │  • Furniture (가구)                                      │   │
│  │  • Mesh (상세 지오메트리)                                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE Scene Capture

```cpp
// AR 환경 메시 접근
class UAREnvironmentProbe : public UARTrackedGeometry
{
    // 환경 메시
    UMRMeshComponent* EnvironmentMesh;

    void ProcessSceneUnderstanding()
    {
        // ARCore/ARKit 씬 메시
        TArray<UARTrackedGeometry*> Geometries;
        UARBlueprintLibrary::GetAllTrackedGeometries(Geometries);

        for (UARTrackedGeometry* Geometry : Geometries)
        {
            EARObjectClassification Classification =
                Geometry->GetObjectClassification();

            switch (Classification)
            {
                case EARObjectClassification::Floor:
                    ProcessFloor(Geometry);
                    break;
                case EARObjectClassification::Wall:
                    ProcessWall(Geometry);
                    break;
                case EARObjectClassification::Ceiling:
                    ProcessCeiling(Geometry);
                    break;
                case EARObjectClassification::Table:
                    ProcessFurniture(Geometry);
                    break;
            }
        }
    }
};

// 공간 앵커
class UARSpatialAnchor : public UObject
{
    // 앵커 생성
    UARPin* CreateSpatialAnchor(FTransform WorldTransform)
    {
        return UARBlueprintLibrary::PinComponent(
            nullptr,
            WorldTransform);
    }

    // 앵커 지속성 (세션 간 유지)
    void SaveAnchor(UARPin* Pin, FString AnchorId)
    {
        // 플랫폼별 앵커 저장
        // Quest: Spatial Anchor API
        // ARCore: Cloud Anchors
        // ARKit: ARWorldMap
    }
};
```

---

## 오클루전

### 환경 오클루전

```
┌─────────────────────────────────────────────────────────────────┐
│                    AR Occlusion                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  오클루전 없음 vs 오클루전 적용:                                 │
│                                                                 │
│  Without Occlusion:          With Occlusion:                    │
│  ┌─────────────────┐        ┌─────────────────┐                │
│  │                 │        │                 │                │
│  │   ┌─────────┐   │        │   ┌─────────┐   │                │
│  │   │ Virtual │   │        │   │ Virtual │   │                │
│  │   │  Cube   │   │        │   │   ██████│   │ ← 실제        │
│  │   │         │   │        │   │   █████ │   │   테이블이    │
│  │   └─────────┘   │        │   └────█████┘   │   가상 물체   │
│  │    ═══════════  │        │    ═══════════  │   가림        │
│  │    Real Table   │        │    Real Table   │                │
│  └─────────────────┘        └─────────────────┘                │
│                                                                 │
│  오클루전 기법:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. Depth-based Occlusion                               │   │
│  │     • 센서 깊이맵 사용 (LiDAR, ToF)                      │   │
│  │     • 깊이 비교로 오클루전 마스크 생성                    │   │
│  │                                                          │   │
│  │  2. Mesh-based Occlusion                                │   │
│  │     • Scene Understanding 메시 사용                     │   │
│  │     • 메시를 깊이만 렌더링                               │   │
│  │                                                          │   │
│  │  3. Edge-based Occlusion                                │   │
│  │     • 실시간 엣지 검출                                   │   │
│  │     • 근사적 오클루전                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 깊이 오클루전 구현

```cpp
// 깊이 기반 오클루전 셰이더
half4 ARDepthOcclusionPS(
    float2 UV : TEXCOORD0,
    float4 ScreenPos : SV_Position) : SV_Target
{
    // 가상 오브젝트 깊이
    float VirtualDepth = SceneDepthTexture.Sample(DepthSampler, UV).r;

    // 실제 환경 깊이 (센서)
    float RealDepth = ARDepthTexture.Sample(DepthSampler, UV).r;

    // 가상 오브젝트 색상
    half4 VirtualColor = VirtualSceneTexture.Sample(ColorSampler, UV);

    // 패스스루 색상
    half4 PassthroughColor = PassthroughTexture.Sample(ColorSampler, UV);

    // 깊이 비교로 오클루전
    if (RealDepth < VirtualDepth)
    {
        // 실제 환경이 앞에 있음 → 패스스루 표시
        return PassthroughColor;
    }
    else
    {
        // 가상 오브젝트가 앞에 있음 → 가상 오브젝트 표시
        return VirtualColor;
    }
}

// Soft Edge 오클루전
half4 SoftOcclusionPS(...)
{
    float VirtualDepth = ...;
    float RealDepth = ...;

    // 소프트 블렌딩
    float DepthDiff = VirtualDepth - RealDepth;
    float BlendFactor = saturate(DepthDiff / SoftEdgeWidth);

    return lerp(VirtualColor, PassthroughColor, BlendFactor);
}
```

---

## 라이팅 통합

### 환경 라이팅 추정

```
┌─────────────────────────────────────────────────────────────────┐
│                  Environment Lighting Estimation                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  실제 환경 라이팅 분석:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │     ☀️ 실제 광원                                         │   │
│  │      ╲                                                   │   │
│  │       ╲  ┌───────────────────────────────┐              │   │
│  │        ╲ │                               │              │   │
│  │         ╲│   ┌─────┐                     │              │   │
│  │          │   │가상 │ ← 실제 라이팅       │              │   │
│  │          │   │물체 │   적용 필요         │              │   │
│  │          │   └─────┘                     │              │   │
│  │          │    ▓▓▓▓▓ 그림자               │              │   │
│  │          └───────────────────────────────┘              │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  추정 데이터:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  • Ambient Light Intensity: 환경 밝기                   │   │
│  │  • Main Light Direction: 주 광원 방향                   │   │
│  │  • Main Light Color: 주 광원 색상                       │   │
│  │  • Environment Cubemap: 환경 반사맵                     │   │
│  │  • Spherical Harmonics: SH 라이팅                       │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 라이팅 적용

```cpp
// AR 라이팅 추정
class UARLightEstimation : public UObject
{
    // 라이팅 업데이트
    void UpdateLighting()
    {
        FARLightEstimate LightEstimate =
            UARBlueprintLibrary::GetCurrentLightEstimate();

        if (LightEstimate.bIsValid)
        {
            // 앰비언트
            float AmbientIntensity = LightEstimate.AmbientIntensityLumens;

            // 주 광원
            FVector MainLightDirection = LightEstimate.DirectionalLightRotation.Vector();
            FLinearColor MainLightColor = LightEstimate.DirectionalLightColor;

            // 씬 라이트 업데이트
            UpdateSceneLighting(
                AmbientIntensity,
                MainLightDirection,
                MainLightColor);
        }
    }

    void UpdateSceneLighting(
        float Ambient,
        FVector LightDir,
        FLinearColor LightColor)
    {
        // 스카이 라이트 업데이트
        if (SkyLight)
        {
            SkyLight->SetIntensity(Ambient);
        }

        // 디렉셔널 라이트 업데이트
        if (DirectionalLight)
        {
            DirectionalLight->SetWorldRotation(FRotationMatrix::MakeFromX(LightDir).Rotator());
            DirectionalLight->SetLightColor(LightColor);
        }
    }
};

// 그림자 매칭
void SetupARShadows()
{
    // 실제 환경 바닥에 그림자 투영
    // Shadow-only 머티리얼 사용

    UMaterialInstanceDynamic* ShadowMaterial =
        UMaterialInstanceDynamic::Create(ShadowOnlyMaterial, this);

    // 바닥 메시에 적용
    FloorMesh->SetMaterial(0, ShadowMaterial);

    // 그림자만 받고 렌더링되지 않음
    FloorMesh->bCastDynamicShadow = false;
    FloorMesh->bReceivesDecals = true;
}
```

---

## 성능 최적화

### AR/MR 렌더링 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                  AR/MR 최적화 체크리스트                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  패스스루 관련                                                   │
│  □ 패스스루 해상도 최적화                                       │
│  □ 깊이 오클루전 범위 제한                                      │
│  □ 패스스루 레이어 최소화                                       │
│                                                                 │
│  공간 인식 관련                                                  │
│  □ Scene Understanding 업데이트 빈도 제한                      │
│  □ 필요한 분류만 요청                                           │
│  □ 메시 복잡도 제한                                             │
│                                                                 │
│  오클루전 관련                                                   │
│  □ 깊이맵 해상도 최적화                                         │
│  □ 오클루전 필요한 영역만 처리                                  │
│  □ 소프트 엣지 비용 고려                                        │
│                                                                 │
│  라이팅 관련                                                     │
│  □ 라이팅 추정 업데이트 빈도 제한                               │
│  □ 환경맵 해상도 최적화                                         │
│  □ 단순화된 그림자                                              │
│                                                                 │
│  일반 최적화                                                     │
│  □ 모바일 최적화 적용                                           │
│  □ FFR 활용                                                    │
│  □ 가상 오브젝트 복잡도 제한                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 플랫폼별 특성

### 플랫폼 비교

| 기능 | Quest 3 | HoloLens 2 | Apple Vision Pro |
|------|---------|------------|------------------|
| **패스스루** | VST (컬러) | OST | VST (고품질) |
| **깊이 센서** | ToF | ToF | LiDAR |
| **해상도** | 2064×2208 | 2048×1080 | 3660×3200 |
| **FOV** | ~110° | ~52° | ~100° |
| **손 추적** | 지원 | 지원 | 지원 |
| **오클루전** | 깊이 기반 | 제한적 | 고품질 |

---

## 참고 자료

- [OpenXR MR Extensions](https://www.khronos.org/openxr/)
- [ARCore Documentation](https://developers.google.com/ar)
- [ARKit Documentation](https://developer.apple.com/arkit/)
- [Meta Presence Platform](https://developer.oculus.com/documentation/native/android/mobile-passthrough/)
