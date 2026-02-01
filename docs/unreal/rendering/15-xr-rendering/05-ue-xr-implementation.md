# UE XR 구현

UE의 XR 지원과 최적화 방법을 설명합니다.

---

## UE XR 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    UE XR 아키텍처                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Application                           │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│  ┌───────────────────────┴─────────────────────────────────┐   │
│  │                    UE XR Framework                       │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │   │
│  │  │ IXRTracking │ │  IHeadMounted│ │ IXRCamera   │       │   │
│  │  │  System     │ │   Display    │ │             │       │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘       │   │
│  └───────────────────────┬─────────────────────────────────┘   │
│                          │                                      │
│  ┌───────────────────────┴─────────────────────────────────┐   │
│  │                    OpenXR / Native SDK                   │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │ Oculus  │ │ SteamVR │ │  WMR    │ │  PSVR   │       │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## OpenXR 통합

UE는 OpenXR을 통해 다양한 XR 디바이스를 지원합니다.

```cpp
// OpenXR 세션 생성
XrSessionCreateInfo sessionInfo = {};
sessionInfo.type = XR_TYPE_SESSION_CREATE_INFO;
sessionInfo.systemId = systemId;

xrCreateSession(instance, &sessionInfo, &session);

// 스왑체인 생성
XrSwapchainCreateInfo swapchainInfo = {};
swapchainInfo.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT;
swapchainInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
swapchainInfo.width = recommendedWidth;
swapchainInfo.height = recommendedHeight;

xrCreateSwapchain(session, &swapchainInfo, &swapchain);
```

---

## Multi-View 설정

```cpp
// Project Settings 또는 콘솔 변수
vr.MobileMultiView=1  // 모바일 Multi-View 활성화

// 셰이더에서 뷰 ID 사용
#if INSTANCED_STEREO
    uint EyeIndex = GetEyeIndex(Parameters.StereoPassIndex);
    float4x4 ViewMatrix = ResolvedView.TranslatedWorldToView[EyeIndex];
#else
    float4x4 ViewMatrix = ResolvedView.TranslatedWorldToView;
#endif
```

---

## Foveated Rendering 설정

```cpp
// Fixed Foveated Rendering 레벨
vr.VRS.HMDFixedFoveationLevel=2  // 0: 없음, 1: 낮음, 2: 중간, 3: 높음

// VRS (Variable Rate Shading) 활용
// 타일별 셰이딩 레이트 설정
// 1x1: 전체 해상도 (중심)
// 2x2: 1/4 해상도 (중간)
// 4x4: 1/16 해상도 (주변)
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    Foveation Level별 패턴                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Level 1 (Low):            Level 3 (High):                     │
│  ┌─────────────────┐       ┌─────────────────┐                 │
│  │ 2x2 │ 1x1 │ 2x2 │       │ 4x4 │ 2x2 │ 4x4 │                 │
│  │─────┼─────┼─────│       │─────┼─────┼─────│                 │
│  │ 1x1 │ 1x1 │ 1x1 │       │ 2x2 │ 1x1 │ 2x2 │                 │
│  │─────┼─────┼─────│       │─────┼─────┼─────│                 │
│  │ 2x2 │ 1x1 │ 2x2 │       │ 4x4 │ 2x2 │ 4x4 │                 │
│  └─────────────────┘       └─────────────────┘                 │
│                                                                 │
│  성능 향상: Level 3에서 최대 25% 픽셀 처리 감소               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quest 2 최적화

### 권장 설정

```cpp
// 프레임률 목표
r.VR.TargetFPS=72  // 72fps (또는 90fps)

// 렌더링 설정
r.MobileContentScaleFactor=1.0  // 해상도 스케일
vr.MobileMultiView=1            // Multi-View 활성화
vr.VRS.HMDFixedFoveationLevel=2 // Foveated Rendering

// 그림자 설정
r.Shadow.MaxResolution=512
r.Shadow.CSM.MaxCascades=1

// 포스트 프로세스
r.Mobile.PostProcessQuality=1
```

### 최적화 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                    Quest 2 최적화 체크리스트                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  렌더링:                                                        │
│  □ 72fps 이상 유지 (90fps 권장)                               │
│  □ Multi-View 활성화                                           │
│  □ Foveated Rendering 활성화                                   │
│  □ 동적 광원 1개 이하                                          │
│                                                                 │
│  콘텐츠:                                                        │
│  □ Draw Call 100개 이하                                        │
│  □ 삼각형 수 100K 이하                                         │
│  □ Baked Lighting 선호                                         │
│  □ 텍스처 ASTC 압축                                            │
│                                                                 │
│  머티리얼:                                                      │
│  □ Texture Sampler 4개 이하                                    │
│  □ 분기 최소화                                                 │
│  □ half precision 사용                                         │
│                                                                 │
│  UI:                                                            │
│  □ VR Compositor Layer 사용 (텍스트 선명도)                    │
│  □ 월드 스페이스 UI                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## AR 기능

### ARKit/ARCore 지원

```cpp
// AR 세션 구성
UARSessionConfig* SessionConfig = NewObject<UARSessionConfig>();
SessionConfig->SetSessionType(EARSessionType::World);
SessionConfig->SetPlaneDetectionMode(EARPlaneDetectionMode::HorizontalPlaneDetection);

// AR 세션 시작
UARBlueprintLibrary::StartARSession(SessionConfig);

// 평면 감지 결과 사용
TArray<UARPlaneGeometry*> Planes;
UARBlueprintLibrary::GetAllGeometriesByClass(Planes);
```

---

## 참고 자료

- [UE VR Development](https://docs.unrealengine.com/5.0/en-US/developing-for-virtual-reality-in-unreal-engine/)
- [OpenXR Specification](https://www.khronos.org/openxr/)
- [Oculus Developer Documentation](https://developer.oculus.com/)
- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/16357850.html)
