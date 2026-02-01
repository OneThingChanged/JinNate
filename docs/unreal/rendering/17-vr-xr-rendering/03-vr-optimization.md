# VR 최적화

VR 특화 최적화 기법과 성능 향상 전략을 분석합니다.

---

## Fixed Foveated Rendering (FFR)

### 중심와 렌더링 원리

```
┌─────────────────────────────────────────────────────────────────┐
│                  Fixed Foveated Rendering                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  인간 시각 특성:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  시야 중심 (Fovea): 고해상도, 색 인식                    │   │
│  │  주변부 (Peripheral): 저해상도, 움직임 감지              │   │
│  │                                                          │   │
│  │              ┌───────────────────┐                       │   │
│  │              │     주변부        │                       │   │
│  │              │   ┌───────────┐   │                       │   │
│  │              │   │   중간    │   │                       │   │
│  │              │   │ ┌─────┐   │   │                       │   │
│  │              │   │ │중심 │   │   │                       │   │
│  │              │   │ │     │   │   │                       │   │
│  │              │   │ └─────┘   │   │                       │   │
│  │              │   └───────────┘   │                       │   │
│  │              └───────────────────┘                       │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  해상도 분포:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  영역          해상도        픽셀 비율                   │   │
│  │  ─────────────────────────────────────────────────────   │   │
│  │  중심          100%          ~25%                        │   │
│  │  중간           75%          ~35%                        │   │
│  │  주변부         50%          ~40%                        │   │
│  │                                                          │   │
│  │  총 픽셀 절감: ~40%                                      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### FFR 설정

```cpp
// Quest FFR 설정
// OpenXR 또는 Oculus API 통해 설정

// FFR 레벨
enum class EFoveatedRenderingLevel
{
    Off,      // FFR 비활성화
    Low,      // 약간의 주변부 감소
    Medium,   // 중간
    High,     // 강한 주변부 감소
    HighTop   // 최대 (상단 더 많이 감소)
};

// UE 설정
void SetFoveatedRenderingLevel(EFoveatedRenderingLevel Level)
{
    // OpenXR 확장 사용
    XrFoveationLevelFB FoveationLevel;

    switch (Level)
    {
        case EFoveatedRenderingLevel::Low:
            FoveationLevel = XR_FOVEATION_LEVEL_LOW_FB;
            break;
        case EFoveatedRenderingLevel::Medium:
            FoveationLevel = XR_FOVEATION_LEVEL_MEDIUM_FB;
            break;
        case EFoveatedRenderingLevel::High:
            FoveationLevel = XR_FOVEATION_LEVEL_HIGH_FB;
            break;
    }

    // 프레임당 설정 가능 (동적 조절)
    xrSetFoveationLevelFB(Session, FoveationLevel);
}

// 콘솔 명령어 (Quest)
vr.FFR.Level=3  // 0=Off, 1=Low, 2=Medium, 3=High
vr.FFR.Dynamic=1  // 동적 FFR (프레임 타임 기반)
```

---

## Application SpaceWarp (ASW)

### 프레임 보간

```
┌─────────────────────────────────────────────────────────────────┐
│                  Application SpaceWarp                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  문제: 90 FPS 유지 불가 시                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  VSync:  ┃     ┃     ┃     ┃     ┃     ┃               │   │
│  │          ┃     ┃     ┃     ┃     ┃     ┃               │   │
│  │  렌더:   ████████████     ████████████                  │   │
│  │          F1         F2         F3                       │   │
│  │          ▲         ▲                                    │   │
│  │          │    VSync 놓침 (Judder)                       │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ASW 해결책:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  VSync:  ┃     ┃     ┃     ┃     ┃     ┃               │   │
│  │          ┃     ┃     ┃     ┃     ┃     ┃               │   │
│  │  렌더:   ██████████████████                             │   │
│  │          F1   (45 FPS로 렌더링)                         │   │
│  │               │                                          │   │
│  │               ▼                                          │   │
│  │  보간:        █  ← ASW가 F1.5 생성 (모션 벡터 기반)     │   │
│  │                                                          │   │
│  │  출력:   F1   F1.5   F2   F2.5   (90 FPS 가상)          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  필요 데이터:                                                    │
│  • 컬러 버퍼                                                    │
│  • 깊이 버퍼                                                    │
│  • 모션 벡터 (Motion Vectors)                                  │
│  • HMD 포즈 변화                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 모션 벡터 생성

```cpp
// 모션 벡터 활성화 (ASW용)
// Project Settings → Rendering → VR

// DefaultEngine.ini
[/Script/Engine.RendererSettings]
r.VelocityOutputPass=1  // 속도 출력 활성화
r.BasePassOutputsVelocity=1  // Base Pass에서 속도 출력

// 모션 벡터 계산 (버텍스 셰이더)
float4 CalculateMotionVector(float4 CurrentPos, float4 PreviousPos)
{
    // 현재 위치 (NDC)
    float2 CurrentNDC = CurrentPos.xy / CurrentPos.w;

    // 이전 위치 (NDC)
    float2 PreviousNDC = PreviousPos.xy / PreviousPos.w;

    // 모션 벡터 (화면 공간 이동량)
    float2 Velocity = CurrentNDC - PreviousNDC;

    return float4(Velocity, 0, 0);
}

// ASW 품질 향상을 위한 팁
// 1. 스키닝 메시: 정확한 이전 프레임 위치 필요
// 2. 파티클: 개별 파티클 속도 제공
// 3. 알파 블렌딩: 모션 벡터 품질 저하 가능
```

---

## Eye Tracked Foveated Rendering

### 아이 트래킹 기반 FFR

```
┌─────────────────────────────────────────────────────────────────┐
│                  Eye Tracked Foveated Rendering                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Fixed FFR (고정)              Eye Tracked FFR (동적)           │
│  ┌─────────────────┐          ┌─────────────────┐              │
│  │ ┌─────────────┐ │          │ ┌─────────────┐ │              │
│  │ │ │ ┌─────┐ │ │ │          │ │         ◉   │ │ ← 시선 위치 │
│  │ │ │ │중심 │ │ │ │          │ │        ╱╲   │ │              │
│  │ │ │ │     │ │ │ │          │ │       ╱  ╲  │ │              │
│  │ │ │ └─────┘ │ │ │          │ │      ╱    ╲ │ │              │
│  │ │ └─────────┘ │ │          │ │     ╱ 고해상╲│ │              │
│  │ └─────────────┘ │          │ └─────────────┘ │              │
│  │  항상 중앙 고정  │          │  시선 따라 이동  │              │
│  └─────────────────┘          └─────────────────┘              │
│                                                                 │
│  지원 디바이스:                                                  │
│  • Quest Pro (Eye Tracking 포함)                               │
│  • PSVR 2 (Eye Tracking 포함)                                  │
│  • HP Reverb G2 Omnicept                                       │
│  • HTC Vive Pro Eye                                            │
│                                                                 │
│  절감 효과:                                                      │
│  • Fixed FFR: ~40% 픽셀 절감                                   │
│  • Eye Tracked FFR: ~60-70% 픽셀 절감                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 아이 트래킹 통합

```cpp
// 아이 트래킹 데이터 사용
void UpdateEyeTracking()
{
    IEyeTrackerModule* EyeTracker = GetEyeTrackerModule();

    if (EyeTracker && EyeTracker->IsEyeTrackerConnected())
    {
        FEyeTrackerGazeData GazeData;
        EyeTracker->GetEyeTrackerGazeData(GazeData);

        // 시선 방향
        FVector GazeDirection = GazeData.GazeDirection;

        // 시선 위치 (화면 좌표)
        FVector2D GazeScreenPosition = WorldToScreen(GazeDirection);

        // FFR 중심점 업데이트
        SetFoveationCenter(GazeScreenPosition);
    }
}

// 동적 FFR 영역 설정
void SetFoveationCenter(FVector2D Center)
{
    // OpenXR Eye Tracking 확장 사용
    XrFoveationCenterOffsetDescriptionFB FoveationCenter = {};
    FoveationCenter.left = Center.X;
    FoveationCenter.down = Center.Y;

    xrSetFoveationCenterFB(Session, &FoveationCenter);
}
```

---

## 지연 최적화

### Pose Prediction

```cpp
// 포즈 예측
// 현재 시점이 아닌 디스플레이 표시 시점의 포즈 예측

class FPosePredictor
{
    FTransform PredictPose(float PredictionTimeSeconds)
    {
        // 현재 센서 데이터
        FTransform CurrentPose;
        FVector AngularVelocity;
        FVector LinearVelocity;

        GetCurrentPoseAndVelocity(CurrentPose, AngularVelocity, LinearVelocity);

        // 선형 예측 (단순)
        FVector PredictedPosition = CurrentPose.GetLocation() +
                                    LinearVelocity * PredictionTimeSeconds;

        // 각속도 예측
        FQuat PredictedRotation = CurrentPose.GetRotation() *
            FQuat(AngularVelocity.GetSafeNormal(),
                  AngularVelocity.Size() * PredictionTimeSeconds);

        return FTransform(PredictedRotation, PredictedPosition);
    }

    // 예측 시간 계산
    float GetPredictionTime()
    {
        // 현재 시간 → 디스플레이 표시 시간
        // = 렌더링 시간 + 컴포지터 시간 + 디스플레이 지연

        float RenderTime = GetAverageGPUTime();
        float CompositorTime = 2.0f;  // ms
        float DisplayLatency = 4.0f;  // ms

        return (RenderTime + CompositorTime + DisplayLatency) / 1000.0f;
    }
};
```

### Async Time Warp

```
┌─────────────────────────────────────────────────────────────────┐
│                  Asynchronous Time Warp                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ATW 동작 원리:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. 앱 렌더링 (예측된 포즈 사용)                         │   │
│  │     ┌──────────────────────────────────────┐            │   │
│  │     │ 렌더링 시작 시점 포즈: Pose_Render   │            │   │
│  │     └──────────────────────────────────────┘            │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │  2. VSync 직전 (컴포지터)                               │   │
│  │     ┌──────────────────────────────────────┐            │   │
│  │     │ 최신 포즈: Pose_Display               │            │   │
│  │     │ 포즈 변화: Delta = Pose_Display -     │            │   │
│  │     │            Pose_Render                │            │   │
│  │     └──────────────────────────────────────┘            │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │  3. 이미지 Warp                                         │   │
│  │     ┌──────────────────────────────────────┐            │   │
│  │     │ 렌더된 이미지를 Delta만큼 회전/이동   │            │   │
│  │     │ (Homography 또는 Reprojection)        │            │   │
│  │     └──────────────────────────────────────┘            │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  제한사항:                                                       │
│  • 회전만 완벽, 이동은 근사                                     │
│  • Disocclusion 영역 처리 필요                                 │
│  • 동적 오브젝트 처리 한계                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 퍼포먼스 프로파일링

### VR 전용 통계

```cpp
// 콘솔 명령어
stat VR                      // VR 전용 통계
stat GPU                     // GPU 타이밍
stat unit                    // 프레임 타이밍
stat XRAPI                   // XR API 통계

// 중요 메트릭
/*
┌─────────────────────────────────────────────────────────────────┐
│  VR Performance Metrics                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame Time Budget (90 Hz):                                     │
│  • Target: 11.11ms per frame                                   │
│  • Safe: < 10ms (여유 확보)                                    │
│                                                                 │
│  Critical Metrics:                                              │
│  • GPU Frame Time: < 10ms                                      │
│  • CPU Game Time: < 8ms                                        │
│  • CPU Render Time: < 6ms                                      │
│  • Submit to Display: < 2ms                                    │
│                                                                 │
│  VR Specific:                                                   │
│  • Dropped Frames: 0 (이상적)                                  │
│  • ASW Activations: 모니터링                                   │
│  • Pose Prediction Error: < 2ms                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
*/
```

### 최적화 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                  VR 최적화 체크리스트                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  렌더링 설정                                                     │
│  □ Instanced Stereo / Multi-View 활성화                        │
│  □ FFR 적절한 레벨 설정                                        │
│  □ Hidden Area Mesh 활성화                                     │
│  □ Round Robin Occlusion 활성화                                │
│                                                                 │
│  해상도 관리                                                     │
│  □ 적절한 Pixel Density (1.0-1.2)                              │
│  □ 동적 해상도 검토                                             │
│  □ 렌더 타겟 크기 최적화                                        │
│                                                                 │
│  Draw Call 최적화                                               │
│  □ 배칭 및 인스턴싱 활용                                        │
│  □ 머티리얼 수 최소화                                           │
│  □ LOD 적극 활용                                               │
│  □ Occlusion Culling 최적화                                    │
│                                                                 │
│  셰이더 최적화                                                   │
│  □ Forward Shading 검토 (VR에 유리)                            │
│  □ 라이트 수 제한 (4개 이하)                                   │
│  □ 그림자 품질 조절                                             │
│  □ 포스트 프로세스 최소화                                       │
│                                                                 │
│  메모리 최적화                                                   │
│  □ 텍스처 스트리밍 설정                                        │
│  □ 메시 LOD 및 Streaming                                       │
│  □ 렌더 타겟 풀 관리                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

- [모션 컨트롤러](04-motion-controllers.md)에서 입력과 인터랙션 렌더링을 학습합니다.
