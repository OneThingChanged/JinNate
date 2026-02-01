# 고품질 렌더링

시네마틱 품질을 위한 세부 렌더링 설정을 분석합니다.

---

## 포스트 프로세스 품질

### DOF (Depth of Field)

```
┌─────────────────────────────────────────────────────────────────┐
│                  Cinematic DOF 설정                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DOF 방식:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Gaussian (빠름)         Circle DOF         Cinematic   │   │
│  │  ┌─────────────┐        ┌─────────────┐    ┌──────────┐│   │
│  │  │ ░░░████░░░  │        │ ○○○████○○○  │    │ ⬡⬡████⬡⬡ ││   │
│  │  │   blur     │        │   bokeh    │    │  bokeh   ││   │
│  │  └─────────────┘        └─────────────┘    └──────────┘│   │
│  │  • 저비용               • 원형 보케        • 물리적 정확 │   │
│  │  • 게임용               • 중간 품질        • 시네마틱용 │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Cinematic DOF 설정:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  카메라 설정 (시뮬레이션):                                │   │
│  │  • Focal Length: 50mm (렌즈 초점 거리)                   │   │
│  │  • Aperture (F-stop): f/1.4 ~ f/22                      │   │
│  │  • Focus Distance: 미터 단위                             │   │
│  │                                                          │   │
│  │  F-Stop 효과:                                            │   │
│  │  f/1.4 ──────────────────────────────────────▶ f/22     │   │
│  │  얕은 DOF                                     깊은 DOF   │   │
│  │  강한 배경 블러                               거의 블러 없음│   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### DOF 설정

```cpp
// 시네마틱 카메라 DOF
UPROPERTY(EditAnywhere, Category = "Depth of Field")
struct FCinematicDOFSettings
{
    // 물리 기반 카메라
    bool bOverride_DepthOfFieldFocalDistance = true;
    float DepthOfFieldFocalDistance = 500.0f;  // cm

    // 조리개
    bool bOverride_DepthOfFieldFstop = true;
    float DepthOfFieldFstop = 2.8f;

    // 센서 크기 (풀프레임 35mm)
    bool bOverride_DepthOfFieldSensorWidth = true;
    float DepthOfFieldSensorWidth = 36.0f;  // mm

    // 블레이드
    bool bOverride_DepthOfFieldBladeCount = true;
    int32 DepthOfFieldBladeCount = 7;  // 7각형 보케
};

// 콘솔 품질 설정
r.DOF.Gather.AccumulatorQuality=1      // 누적 품질
r.DOF.Gather.RingCount=5               // 보케 링 수
r.DOF.Gather.EnableBokehSettings=1     // 보케 설정 활성화
r.DOF.Recombine.Quality=2              // 재결합 품질
```

---

## 모션 블러

### 시네마틱 모션 블러

```
┌─────────────────────────────────────────────────────────────────┐
│                  Motion Blur 설정                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  셔터 앵글 (Shutter Angle):                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  360° (완전 개방)     180° (표준 영화)     90° (짧은 노출)│   │
│  │  ████████████████     ████████░░░░░░░░     ████░░░░░░░░░░│   │
│  │  최대 블러            자연스러운 블러       최소 블러     │   │
│  │                                                          │   │
│  │  영화 표준: 180° (1/48초 @ 24fps)                        │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Per-Pixel vs Per-Object:                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Per-Object (게임)          Per-Pixel (시네마틱)         │   │
│  │  ┌─────────────────┐       ┌─────────────────┐          │   │
│  │  │    ──▶ ██       │       │    ═══════▶     │          │   │
│  │  │   오브젝트 단위  │       │   픽셀 단위     │          │   │
│  │  │   빠름          │       │   정확함        │          │   │
│  │  └─────────────────┘       └─────────────────┘          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 모션 블러 설정

```cpp
// 모션 블러 품질 설정
UPROPERTY(EditAnywhere, Category = "Motion Blur")
struct FMotionBlurSettings
{
    // 활성화
    bool bOverride_MotionBlurAmount = true;
    float MotionBlurAmount = 1.0f;  // 0-1

    // 최대 블러
    bool bOverride_MotionBlurMax = true;
    float MotionBlurMax = 10.0f;  // 픽셀

    // 셔터 앵글 (MRQ에서 설정)
    // MotionBlur_ShutterAnglePercentage = 0.5  // 180도
};

// MRQ 모션 블러 설정
UPROPERTY(EditAnywhere)
struct FMoviePipelineMotionBlur
{
    // 시간 샘플 (서브프레임)
    int32 TemporalSampleCount = 8;

    // 셔터 타이밍
    EMoviePipelineShutterTiming ShutterTiming = EMoviePipelineShutterTiming::FrameCenter;

    // 셔터 앵글 (0-360)
    float ShutterAngle = 180.0f;
};

// 콘솔 설정
r.MotionBlurQuality=4                  // 품질 레벨
r.MotionBlurSeparable=1                // 분리 필터
```

---

## 라이팅 품질

### 그림자 품질

```cpp
// 고품질 그림자 설정
UPROPERTY(EditAnywhere, Category = "Shadows")
struct FCinematicShadowSettings
{
    // CSM 해상도
    int32 MaxCSMResolution = 4096;  // 기본 2048

    // CSM 캐스케이드 수
    int32 NumCascades = 4;

    // 소프트 섀도우
    float SoftShadowPenumbraSize = 1.0f;

    // 레이 트레이스 그림자
    bool bRayTracedShadows = true;
    int32 RayTracedShadowSamplesPerPixel = 4;
};

// 콘솔 설정
r.Shadow.MaxResolution=4096
r.Shadow.MaxCSMResolution=4096
r.Shadow.DistanceScale=2.0             // 그림자 거리
r.Shadow.CSM.MaxCascades=10            // 최대 캐스케이드
r.RayTracing.Shadow.EnableTwoSidedGeometry=1
```

### 글로벌 일루미네이션

```cpp
// Lumen 고품질 설정
r.Lumen.TraceMeshSDFs=1
r.Lumen.ScreenProbeGather.RadianceCache.NumProbesToTraceBudget=200
r.Lumen.ScreenProbeGather.TemporalReprojectionRadiusScale=1.0
r.Lumen.ReflectionQuality=2

// 레이 트레이싱 GI
r.RayTracing.GlobalIllumination=1
r.RayTracing.GlobalIllumination.MaxBounces=3
r.RayTracing.GlobalIllumination.SamplesPerPixel=4
```

---

## 반사 품질

### SSR vs Ray Traced

```
┌─────────────────────────────────────────────────────────────────┐
│                  반사 품질 설정                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  SSR (Screen Space):                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 화면 내 정보만 사용                                    │   │
│  │ • 화면 밖 반사 누락                                      │   │
│  │ • 빠름                                                   │   │
│  │ • 러프 표면에서 노이즈                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Ray Traced Reflections:                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 정확한 반사                                            │   │
│  │ • 화면 밖 반사 가능                                      │   │
│  │ • 멀티바운스 반사                                        │   │
│  │ • 느림 (하드웨어 RT 필요)                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  설정:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  // SSR 고품질                                           │   │
│  │  r.SSR.Quality=4                                         │   │
│  │  r.SSR.Temporal=1                                        │   │
│  │                                                          │   │
│  │  // Ray Traced                                           │   │
│  │  r.RayTracing.Reflections=1                              │   │
│  │  r.RayTracing.Reflections.MaxBounces=2                   │   │
│  │  r.RayTracing.Reflections.SamplesPerPixel=4              │   │
│  │  r.RayTracing.Reflections.MaxRoughness=0.6               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 머티리얼 품질

### 고품질 머티리얼 설정

```cpp
// 서브서피스 스캐터링
r.SSS.Quality=1                        // 고품질 SSS
r.SSS.Scale=1.0                        // 스케일

// 헤어 셰이딩
r.HairStrands.Enable=1
r.HairStrands.AAMSaaMode=1

// 클리어 코트
r.ClearCoatNormal=1

// 텍스처 품질
r.Streaming.PoolSize=4096              // 스트리밍 풀
r.Streaming.MipBias=0                  // 밉 바이어스
r.MaxAnisotropy=16                     // 이방성 필터링
```

### 셰이더 복잡도

```cpp
// 셰이더 품질 설정
r.MaterialQualityLevel=3               // 최고 품질 머티리얼
r.SimpleDynamicLighting=0              // 복잡한 라이팅

// 테셀레이션 (지원 시)
r.TessellationAdaptivePixelsPerTriangle=48

// Nanite 품질
r.Nanite.MaxPixelsPerEdge=1            // 높은 디테일
```

---

## 톤 매핑

### 필름 시뮬레이션

```cpp
// 필름 톤 매핑 설정
UPROPERTY(EditAnywhere, Category = "Tone Mapping")
struct FFilmToneMapperSettings
{
    // 필름 숄더/토
    float FilmSlope = 0.88f;
    float FilmToe = 0.55f;
    float FilmShoulder = 0.26f;
    float FilmBlackClip = 0.0f;
    float FilmWhiteClip = 0.04f;

    // ACES 톤 매핑
    EToneCurveType ToneCurve = EToneCurveType::ACES;

    // 색 보정
    FVector4 ColorSaturation = FVector4(1, 1, 1, 1);
    FVector4 ColorContrast = FVector4(1, 1, 1, 1);
    FVector4 ColorGamma = FVector4(1, 1, 1, 1);
    FVector4 ColorGain = FVector4(1, 1, 1, 1);
    FVector4 ColorOffset = FVector4(0, 0, 0, 0);
};

// OCIO (OpenColorIO) 통합
// 컬러 파이프라인 관리
r.OCIO.Enabled=1
r.OCIO.ConfigPath="/Game/OCIO/config.ocio"
```

---

## 성능과 품질 균형

### 품질 프리셋

```
┌─────────────────────────────────────────────────────────────────┐
│                  품질 프리셋 비교                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  설정           프리뷰      중간        고품질      최고        │
│  ─────────────────────────────────────────────────────────────  │
│  해상도         1080p       2K          4K          8K          │
│  AA 샘플        1           4           8           16          │
│  모션블러 샘플  1           4           8           16          │
│  그림자 해상도  1024        2048        4096        4096        │
│  SSR/RT        SSR         SSR HQ      RT          RT HQ       │
│  GI            Lumen       Lumen HQ    RT GI       Path Trace  │
│  DOF           Gaussian    Circle      Cinematic   Cinematic   │
│  렌더 시간     ~실시간     ~수초       ~수십초     ~수분       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

- [버추얼 프로덕션](04-virtual-production.md)에서 LED Wall 촬영 기술을 학습합니다.
