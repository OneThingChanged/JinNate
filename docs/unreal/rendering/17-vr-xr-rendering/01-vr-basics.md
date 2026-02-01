# VR 렌더링 기초

VR 렌더링의 기본 원리와 HMD 특성을 분석합니다.

---

## VR 디스플레이 원리

### HMD 광학 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                    HMD 광학 구조                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │    Display        Lens           Eye                     │   │
│  │    ┌─────┐      ╱─────╲        ┌───┐                    │   │
│  │    │     │     │       │       │   │                    │   │
│  │    │  ≡  │ ──▶ │   ◯   │ ──▶  │ ◉ │                    │   │
│  │    │     │     │       │       │   │                    │   │
│  │    └─────┘      ╲─────╱        └───┘                    │   │
│  │                                                          │   │
│  │  디스플레이      Fresnel       눈                        │   │
│  │  패널           렌즈                                     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  렌즈 특성:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. 배럴 왜곡 (Barrel Distortion)                       │   │
│  │     원본 이미지    렌즈 통과 후                          │   │
│  │     ┌────────┐    ┌────────┐                            │   │
│  │     │ ┼──┼   │    │  )──(  │                            │   │
│  │     │ │  │   │ →  │  │  │  │  가장자리가 안으로 휨      │   │
│  │     │ ┼──┼   │    │  )──(  │                            │   │
│  │     └────────┘    └────────┘                            │   │
│  │                                                          │   │
│  │  2. 색수차 (Chromatic Aberration)                       │   │
│  │     RGB 채널이 다른 위치에 포커싱                        │   │
│  │     R ──→ ◯ ←── G ←── B                                 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 왜곡 보정

```cpp
// 렌더링 시 역왜곡(Pincushion) 적용
// 렌즈를 통과하면 원래 이미지로 보임

// UE에서의 처리
class FDistortionMesh
{
    // 왜곡 보정 메시 생성
    void GenerateDistortionMesh(
        int32 GridSizeX, int32 GridSizeY,
        const FVector2D& LensCenter,
        const FVector4& DistortionCoefficients,
        const FVector4& ChromaticAberration)
    {
        for (int32 y = 0; y < GridSizeY; y++)
        {
            for (int32 x = 0; x < GridSizeX; x++)
            {
                FVector2D UV = FVector2D(x, y) / FVector2D(GridSizeX - 1, GridSizeY - 1);

                // 역왜곡 좌표 계산
                FVector2D DistortedUV = CalculateDistortion(UV, LensCenter,
                                                            DistortionCoefficients);

                // 색수차 보정 (RGB 개별 UV)
                FVector2D RedUV = DistortedUV * ChromaticAberration.X;
                FVector2D GreenUV = DistortedUV * ChromaticAberration.Y;
                FVector2D BlueUV = DistortedUV * ChromaticAberration.Z;

                AddVertex(UV, RedUV, GreenUV, BlueUV);
            }
        }
    }
};
```

---

## 스테레오 비전

### IPD (Interpupillary Distance)

```
┌─────────────────────────────────────────────────────────────────┐
│                    IPD와 스테레오 렌더링                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  IPD (동공 간 거리):                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │         ◉ ←────── IPD (60-70mm) ──────→ ◉               │   │
│  │       Left Eye                        Right Eye          │   │
│  │                                                          │   │
│  │  • 평균 IPD: 63mm                                        │   │
│  │  • 범위: 54mm ~ 74mm                                     │   │
│  │  • HMD 설정에서 조절 가능                                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  카메라 설정:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │           Head Position                                  │   │
│  │               ◯                                          │   │
│  │              /│\                                         │   │
│  │             / │ \                                        │   │
│  │            /  │  \                                       │   │
│  │           /   │   \                                      │   │
│  │        ◎     │     ◎                                    │   │
│  │     Left    │    Right                                  │   │
│  │     Camera  │    Camera                                 │   │
│  │          ←─IPD/2─→                                      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 스테레오 뷰 매트릭스

```cpp
// 스테레오 뷰 매트릭스 계산
void CalculateStereoViewMatrices(
    const FTransform& HeadPose,
    float IPD,
    FMatrix& OutLeftView,
    FMatrix& OutRightView)
{
    float HalfIPD = IPD * 0.5f;

    // 왼쪽 눈
    FVector LeftEyeOffset = FVector(0, -HalfIPD, 0);  // 왼쪽으로 오프셋
    FTransform LeftEyePose = HeadPose;
    LeftEyePose.AddToTranslation(LeftEyePose.TransformVector(LeftEyeOffset));
    OutLeftView = LeftEyePose.ToInverseMatrixWithScale();

    // 오른쪽 눈
    FVector RightEyeOffset = FVector(0, HalfIPD, 0);  // 오른쪽으로 오프셋
    FTransform RightEyePose = HeadPose;
    RightEyePose.AddToTranslation(RightEyePose.TransformVector(RightEyeOffset));
    OutRightView = RightEyePose.ToInverseMatrixWithScale();
}

// 비대칭 프로젝션 (각 눈별로 다름)
FMatrix CalculateAsymmetricProjection(
    float Left, float Right, float Top, float Bottom,
    float NearPlane, float FarPlane)
{
    // 각 눈의 시야각이 다름
    // 코 방향은 좁고, 바깥쪽은 넓음
    FMatrix Projection;
    // ... 비대칭 프로젝션 매트릭스 생성
    return Projection;
}
```

---

## 프레임 타이밍

### VSync와 프레임 페이싱

```
┌─────────────────────────────────────────────────────────────────┐
│                    VR 프레임 타이밍                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  90 Hz 디스플레이 (11.11ms per frame):                          │
│                                                                 │
│  Time ─────────────────────────────────────────────────────────▶│
│        │           │           │           │           │       │
│        ▼           ▼           ▼           ▼           ▼       │
│  VSync ┼───────────┼───────────┼───────────┼───────────┼       │
│        0ms       11.11ms     22.22ms     33.33ms     44.44ms   │
│                                                                 │
│  이상적인 프레임:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ├─── Game ───┼─── Render ───┼── Submit ──┤             │   │
│  │  0ms         4ms            8ms         10ms    VSync   │   │
│  │                                              ↓           │   │
│  │  ████████████████████████████████████████░░░┃           │   │
│  │                                          여유              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  프레임 드롭 시:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  VSync 1        VSync 2        VSync 3                   │   │
│  │    ┃              ┃              ┃                       │   │
│  │  ██████████████████████████████████                      │   │
│  │    │              ↑                                      │   │
│  │    │         VSync 놓침                                  │   │
│  │    │         (Judder 발생)                               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Motion-to-Photon 지연

```
┌─────────────────────────────────────────────────────────────────┐
│                Motion-to-Photon Latency                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  사용자 움직임 → 화면 표시까지의 총 지연                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Head        Sensor      Game      Render    Display    │   │
│  │  Motion   → Sampling → Thread → Thread   → Output      │   │
│  │    │          │          │         │          │         │   │
│  │    │    1ms   │    3ms   │   5ms   │   2ms    │         │   │
│  │    ▼          ▼          ▼         ▼          ▼         │   │
│  │  ├────────────────────────────────────────────┤         │   │
│  │  0ms                                       11ms         │   │
│  │                                                          │   │
│  │  + Display Persistence: 2-5ms                           │   │
│  │                                                          │   │
│  │  총 Motion-to-Photon: ~13-16ms                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화 기법:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Late Latching: 마지막 순간 포즈 업데이트               │   │
│  │ • Async Time Warp: 이전 프레임 재투영                    │   │
│  │ • Pose Prediction: 미래 포즈 예측                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## FOV와 해상도

### Field of View

```cpp
// VR HMD FOV 특성
struct FHMDFieldOfView
{
    // 각 눈별 FOV (비대칭)
    float LeftEyeLeft;    // 예: -50도
    float LeftEyeRight;   // 예: +45도 (코 방향)
    float LeftEyeUp;      // 예: +55도
    float LeftEyeDown;    // 예: -55도

    float RightEyeLeft;   // 예: -45도 (코 방향)
    float RightEyeRight;  // 예: +50도
    float RightEyeUp;     // 예: +55도
    float RightEyeDown;   // 예: -55도

    // 총 수평 FOV: ~100-110도
    // 총 수직 FOV: ~100-110도
    // 오버랩 영역: ~80-90도
};

// 렌더 타겟 해상도 계산
FIntPoint CalculateRenderTargetSize(
    const FHMDFieldOfView& FOV,
    float PixelsPerDisplayPixel)
{
    // 디스플레이 해상도
    FIntPoint DisplayResolution = HMD->GetDisplayResolution();

    // 슈퍼샘플링 적용
    FIntPoint RenderResolution;
    RenderResolution.X = DisplayResolution.X * PixelsPerDisplayPixel;
    RenderResolution.Y = DisplayResolution.Y * PixelsPerDisplayPixel;

    return RenderResolution;
}
```

### 해상도 스케일링

```
┌─────────────────────────────────────────────────────────────────┐
│                    VR 해상도 스케일링                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  네이티브 vs 슈퍼샘플링:                                         │
│                                                                 │
│  네이티브 (1.0x)      슈퍼샘플링 (1.4x)                         │
│  ┌────────────┐       ┌──────────────────┐                     │
│  │            │       │                  │                     │
│  │  1832×1920 │       │    2565×2688     │                     │
│  │            │       │                  │                     │
│  └────────────┘       └──────────────────┘                     │
│        │                      │                                 │
│        │              렌더링 후 다운샘플링                       │
│        ▼                      ▼                                 │
│  ┌────────────┐       ┌────────────┐                           │
│  │  Display   │       │  Display   │                           │
│  │  1832×1920 │       │  1832×1920 │                           │
│  └────────────┘       └────────────┘                           │
│                                                                 │
│  효과:                                                          │
│  • 슈퍼샘플링: 앨리어싱 감소, 선명도 향상                        │
│  • 비용: 픽셀 수 제곱 비례 증가 (1.4x = 1.96배 픽셀)            │
│                                                                 │
│  설정:                                                          │
│  vr.PixelDensity=1.0        // 네이티브                         │
│  vr.PixelDensity=1.4        // 140% 슈퍼샘플링                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 렌더 타겟 관리

### Eye Buffer 구조

```cpp
// 스테레오 렌더 타겟
class FVRRenderTargetManager
{
    // 눈별 렌더 타겟
    FTexture2DRHIRef LeftEyeTarget;
    FTexture2DRHIRef RightEyeTarget;

    // 또는 배열 텍스처 (Multiview)
    FTexture2DArrayRHIRef StereoTarget;  // Layer 0 = Left, Layer 1 = Right

    // 깊이 버퍼
    FTexture2DRHIRef DepthTarget;

    void CreateRenderTargets(FIntPoint Size, EPixelFormat Format)
    {
        FRHIResourceCreateInfo CreateInfo;

        // 컬러 버퍼
        LeftEyeTarget = RHICreateTexture2D(
            Size.X, Size.Y,
            Format,
            1,  // Mip count
            1,  // Sample count
            TexCreate_RenderTargetable | TexCreate_ShaderResource,
            CreateInfo);

        // 멀티뷰용 배열 텍스처
        StereoTarget = RHICreateTexture2DArray(
            Size.X, Size.Y,
            2,  // Array size (Left + Right)
            Format,
            1, 1,
            TexCreate_RenderTargetable | TexCreate_ShaderResource,
            CreateInfo);
    }
};
```

---

## 디버깅

### VR 시각화 도구

```cpp
// 콘솔 명령어
vr.Debug.ShowStats 1         // VR 통계 표시
vr.Debug.ShowHMDTransform 1  // HMD 트랜스폼 표시
vr.Debug.ShowControllers 1   // 컨트롤러 위치 표시

// 성능 통계
stat vr                      // VR 전용 통계
stat gpu                     // GPU 타이밍
stat unit                    // 프레임 타이밍

// 미러 모드 (PC 모니터)
vr.MirrorMode 0              // 미러 없음
vr.MirrorMode 1              // 왼쪽 눈
vr.MirrorMode 2              // 양쪽 눈 (왜곡 보정)
vr.MirrorMode 3              // 양쪽 눈 (왜곡 없음)
```

---

## 다음 단계

- [스테레오 렌더링](02-stereo-rendering.md)에서 효율적인 스테레오 렌더링 기법을 학습합니다.
