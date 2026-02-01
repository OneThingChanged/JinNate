# 플랫폼별 최적화

PC, 콘솔, 모바일 각 플랫폼의 최적화 전략을 분석합니다.

---

## 플랫폼별 특성

```
┌─────────────────────────────────────────────────────────────────┐
│                  Platform Characteristics                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  PC                                                      │   │
│  │  ├── 다양한 하드웨어 스펙                               │   │
│  │  ├── Scalability 설정 필수                              │   │
│  │  ├── 높은 메모리 가용량                                 │   │
│  │  └── DX11, DX12, Vulkan 지원                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Console (PS5, Xbox Series X)                            │   │
│  │  ├── 고정 하드웨어 스펙                                 │   │
│  │  ├── 높은 GPU 성능                                       │   │
│  │  ├── 제한된 메모리 (16GB 공유)                          │   │
│  │  └── 프로파일링 도구 풍부                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Mobile (iOS, Android)                                   │   │
│  │  ├── 타일 기반 렌더링 (TBDR)                            │   │
│  │  ├── 발열/배터리 제약                                   │   │
│  │  ├── 매우 제한된 메모리                                 │   │
│  │  └── OpenGL ES, Vulkan, Metal                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Scalability 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                   Scalability System                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  품질 레벨: Low → Medium → High → Epic → Cinematic              │
│                                                                 │
│  스케일러빌리티 그룹:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  sg.ResolutionQuality   ─ 렌더링 해상도                  │   │
│  │  sg.ViewDistanceQuality ─ 뷰 거리                        │   │
│  │  sg.AntiAliasingQuality ─ AA 품질                        │   │
│  │  sg.ShadowQuality       ─ 그림자 품질                    │   │
│  │  sg.PostProcessQuality  ─ 포스트 프로세스                │   │
│  │  sg.TextureQuality      ─ 텍스처 품질                    │   │
│  │  sg.EffectsQuality      ─ 이펙트 품질                    │   │
│  │  sg.FoliageQuality      ─ 폴리지 품질                    │   │
│  │  sg.ShadingQuality      ─ 셰이딩 품질                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  설정 위치:                                                     │
│  Engine/Config/BaseScalability.ini                              │
│  [Project]/Config/DefaultScalability.ini                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Scalability 설정

```ini
; DefaultScalability.ini 예시

[ScalabilitySettings]
; 퍼포먼스 힌트 (0=Low, 1=Medium, 2=High, 3=Epic)
PerfIndexThresholds_ResolutionQuality="18 42 70"

[ShadowQuality@0]
; Low 설정
r.ShadowQuality=0
r.Shadow.CSM.MaxCascades=1
r.Shadow.MaxResolution=512
r.Shadow.RadiusThreshold=0.06

[ShadowQuality@3]
; Epic 설정
r.ShadowQuality=5
r.Shadow.CSM.MaxCascades=4
r.Shadow.MaxResolution=2048
r.Shadow.RadiusThreshold=0.01

[TextureQuality@0]
r.Streaming.MipBias=2
r.MaxAnisotropy=0

[TextureQuality@3]
r.Streaming.MipBias=0
r.MaxAnisotropy=8
```

### 런타임 스케일러빌리티

```cpp
// 스케일러빌리티 레벨 변경
void SetScalabilityLevel(int32 Level)
{
    // 전체 스케일러빌리티 설정
    Scalability::SetQualityLevels(Level);

    // 또는 개별 설정
    Scalability::SetQualityLevel(Scalability::EQualityLevels::Shadows, Level);
    Scalability::SetQualityLevel(Scalability::EQualityLevels::PostProcess, Level);
}

// 동적 해상도 스케일링
void EnableDynamicResolution()
{
    // 콘솔 변수
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.DynamicRes.OperationMode"))->Set(1);
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.DynamicRes.MinScreenPercentage"))->Set(50.0f);
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.DynamicRes.MaxScreenPercentage"))->Set(100.0f);

    // 타겟 프레임레이트
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.DynamicRes.TargetedGPUHeadRoomPercentage"))->Set(10.0f);
}

// 현재 품질 레벨 확인
int32 GetCurrentQualityLevel()
{
    return Scalability::GetQualityLevels().GetSingleQualityLevel();
}
```

---

## PC 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                    PC Optimization                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  주요 과제:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • 광범위한 하드웨어 지원 (최소/권장/고사양)             │   │
│  │ • 다양한 해상도 (1080p ~ 4K+)                           │   │
│  │ • 가변 프레임레이트 (30/60/120/무제한)                  │   │
│  │ • 드라이버/OS 버전 차이                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화 전략:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Tier 1 (Min Spec)      Tier 2 (Recommended)           │   │
│  │  ┌────────────────┐     ┌────────────────┐             │   │
│  │  │ 1080p @ 30fps  │     │ 1080p @ 60fps  │             │   │
│  │  │ Low Settings   │     │ High Settings  │             │   │
│  │  │ DX11           │     │ DX12           │             │   │
│  │  └────────────────┘     └────────────────┘             │   │
│  │                                                          │   │
│  │  Tier 3 (High End)                                       │   │
│  │  ┌────────────────┐                                     │   │
│  │  │ 4K @ 60fps     │                                     │   │
│  │  │ Epic Settings  │                                     │   │
│  │  │ RT Features    │                                     │   │
│  │  └────────────────┘                                     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### PC 설정 자동 감지

```cpp
// 하드웨어 벤치마크 기반 자동 설정
void AutoDetectSettings()
{
    // 합성 벤치마크 실행
    Scalability::FQualityLevels Levels = Scalability::BenchmarkQualityLevels();

    // 결과 적용
    Scalability::SetQualityLevels(Levels);

    // 또는 GPU 정보 기반
    FString RHIName = GDynamicRHI->GetName();
    if (RHIName.Contains(TEXT("D3D12")))
    {
        // DX12 전용 최적화
        EnableDX12Features();
    }
}

// GPU 정보 확인
void LogGPUInfo()
{
    UE_LOG(LogTemp, Log, TEXT("GPU: %s"), *GRHIAdapterName);
    UE_LOG(LogTemp, Log, TEXT("VRAM: %d MB"), GRHIDeviceInfo.DedicatedVideoMemory / (1024 * 1024));
    UE_LOG(LogTemp, Log, TEXT("RHI: %s"), *GDynamicRHI->GetName());

    // 레이트레이싱 지원 확인
    if (GRHISupportsRayTracing)
    {
        UE_LOG(LogTemp, Log, TEXT("Ray Tracing: Supported"));
    }
}
```

---

## 콘솔 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                   Console Optimization                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PS5 / Xbox Series X 타겟:                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Performance Mode      Quality Mode      RT Mode         │   │
│  │  ┌────────────────┐   ┌────────────────┐ ┌────────────┐ │   │
│  │  │ 4K @ 60fps     │   │ 4K @ 30fps     │ │ 4K @ 30fps │ │   │
│  │  │ Dynamic Res    │   │ Native Res     │ │ RT Shadows │ │   │
│  │  │ Reduced FX     │   │ Full FX        │ │ RT GI      │ │   │
│  │  └────────────────┘   └────────────────┘ └────────────┘ │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  메모리 관리 (16GB 공유):                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Textures    │██████████████████│     6 GB              │   │
│  │  Meshes      │████████████│          4 GB              │   │
│  │  Audio       │███│                    1 GB              │   │
│  │  Code/Engine │█████│                  2 GB              │   │
│  │  Reserve     │███│                    1 GB              │   │
│  │  OS/System   │████│                   2 GB              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 콘솔별 설정

```cpp
// 플랫폼별 설정 (Config/[Platform]/[Platform]Engine.ini)

// PS5 설정
#if PLATFORM_PS5
void ApplyPS5Optimizations()
{
    // 압축 I/O 활용
    // PS5의 Kraken 압축 자동 사용

    // 고속 SSD 활용
    // 스트리밍 거리 줄이기 가능
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.Streaming.PoolSize"))->Set(800);

    // 레이트레이싱 설정
    if (bRTMode)
    {
        IConsoleManager::Get().FindConsoleVariable(TEXT("r.RayTracing"))->Set(1);
        IConsoleManager::Get().FindConsoleVariable(TEXT("r.RayTracing.GlobalIllumination"))->Set(1);
    }
}
#endif

// Xbox Series X 설정
#if PLATFORM_XSX
void ApplyXboxOptimizations()
{
    // Velocity Architecture 활용
    // SFS (Sampler Feedback Streaming)

    // Variable Rate Shading
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.VRS.Enable"))->Set(1);
}
#endif

// 공통 콘솔 최적화
void ApplyConsoleOptimizations()
{
    // 고정 프레임레이트
    GEngine->SetMaxFPS(60.0f);

    // 동적 해상도
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.DynamicRes.OperationMode"))->Set(2);

    // 메모리 최적화
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.Streaming.FullyLoadUsedTextures"))->Set(0);
}
```

---

## 모바일 최적화

```
┌─────────────────────────────────────────────────────────────────┐
│                   Mobile Optimization                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  모바일 렌더링 특성:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Tile-Based Deferred Rendering (TBDR):                   │   │
│  │  ┌───┬───┬───┬───┐                                      │   │
│  │  │T1 │T2 │T3 │T4 │  화면을 타일로 분할                  │   │
│  │  ├───┼───┼───┼───┤  타일별로 on-chip 메모리에서 처리    │   │
│  │  │T5 │T6 │T7 │T8 │  대역폭 절약                         │   │
│  │  └───┴───┴───┴───┘                                      │   │
│  │                                                          │   │
│  │  최적화 포인트:                                          │   │
│  │  • 알파 블렌딩 최소화 (오버드로 방지)                   │   │
│  │  • 포스트 프로세스 최소화                               │   │
│  │  • 텍스처 대역폭 감소                                   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  타겟 디바이스 분류:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  High:  iPhone 12+, Galaxy S21+     → 60fps 타겟        │   │
│  │  Mid:   iPhone XS, Galaxy S10       → 30fps 타겟        │   │
│  │  Low:   iPhone 8, Galaxy S8         → 30fps (제한적)    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 모바일 설정

```cpp
// 모바일 렌더링 설정
void ApplyMobileOptimizations()
{
    // 렌더링 패스
    // Forward Shading (모바일 기본)
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.Mobile.Forward.EnableClusteredReflections"))->Set(0);

    // 그림자 설정
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.Shadow.CSM.MaxMobileCascades"))->Set(1);
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.ShadowQuality"))->Set(1);

    // 안티앨리어싱
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.Mobile.MSAA"))->Set(2);  // 2x MSAA

    // 텍스처 압축
    // ASTC 사용 (Android), PVRTC/ASTC (iOS)

    // 반사
    IConsoleManager::Get().FindConsoleVariable(TEXT("r.ReflectionEnvironment"))->Set(0);

    // 발열 관리
    GEngine->SetMaxFPS(30.0f);  // 안정적인 30fps
}

// 디바이스 티어 감지
EMobileDeviceTier GetMobileDeviceTier()
{
    // 플랫폼별 디바이스 정보로 판단
    FString DeviceModel = FPlatformMisc::GetDeviceMakeAndModel();

    // GPU 벤치마크 기반
    int32 GPUBenchmark = FPlatformMisc::GetGPUBenchmarkResults();

    if (GPUBenchmark > 100)
        return EMobileDeviceTier::High;
    else if (GPUBenchmark > 50)
        return EMobileDeviceTier::Medium;
    else
        return EMobileDeviceTier::Low;
}
```

### 모바일 셰이더 최적화

```hlsl
// 모바일 셰이더 팁

// Precision 지정 (모바일에서 중요)
half3 Color = BaseColor.rgb;  // half 사용
float3 Position = WorldPos;    // 위치는 float 필요

// 텍스처 샘플러 제한
// 모바일: 최대 8개 권장

// 복잡한 연산 피하기
// pow, sin, cos → LUT 텍스처로 대체

// 분기 최소화
// if문 대신 lerp 사용
half3 Result = lerp(ColorA, ColorB, Mask);

// 노멀맵 DXT5nm 디코딩 (모바일)
half3 DecodeNormal(half4 PackedNormal)
{
    half3 Normal;
    Normal.xy = PackedNormal.ag * 2.0 - 1.0;
    Normal.z = sqrt(1.0 - saturate(dot(Normal.xy, Normal.xy)));
    return Normal;
}
```

---

## 크로스 플랫폼 전략

```
┌─────────────────────────────────────────────────────────────────┐
│                Cross-Platform Strategy                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  계층적 품질 설정:                                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Base Content (모든 플랫폼 공통)                         │   │
│  │  ├── Core Gameplay                                       │   │
│  │  ├── Base Meshes (LOD 0-2)                              │   │
│  │  └── Core Textures (1K base)                            │   │
│  │                                                          │   │
│  │  + PC/Console Enhancement                                │   │
│  │    ├── High-res Textures (4K)                           │   │
│  │    ├── Additional LODs                                   │   │
│  │    └── Advanced Effects                                  │   │
│  │                                                          │   │
│  │  + High-End Enhancement                                  │   │
│  │    ├── Ray Tracing                                       │   │
│  │    ├── Ultra Textures (8K)                              │   │
│  │    └── Cinematic Quality                                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Device Profile 설정

```ini
; Config/DefaultDeviceProfiles.ini

[Windows DeviceProfile]
DeviceType=Windows
BaseProfileName=

+CVars=r.MaxAnisotropy=8
+CVars=r.ShadowQuality=4

[Android_High DeviceProfile]
DeviceType=Android
BaseProfileName=

+CVars=r.MobileContentScaleFactor=1.0
+CVars=r.Mobile.MSAA=2
+CVars=r.ShadowQuality=2

[Android_Low DeviceProfile]
DeviceType=Android
BaseProfileName=

+CVars=r.MobileContentScaleFactor=0.75
+CVars=r.Mobile.MSAA=0
+CVars=r.ShadowQuality=0
```

---

## 주요 설정 요약

| 플랫폼 | 주요 설정 | 권장값 |
|--------|----------|--------|
| PC | Scalability | 자동 감지 |
| PC | Dynamic Resolution | 50-100% |
| Console | Frame Rate | 60fps |
| Console | Memory Pool | 800MB |
| Mobile | MSAA | 2x |
| Mobile | Shadow Cascades | 1 |
| Mobile | Max FPS | 30 |

---

## 참고 자료

- [Scalability Reference](https://docs.unrealengine.com/scalability/)
- [Platform Optimization](https://docs.unrealengine.com/platform-development/)
- [Mobile Optimization](https://docs.unrealengine.com/mobile-performance/)
