# 플랫폼별 최적화

PC, 콘솔, 모바일, VR 등 각 플랫폼에 특화된 렌더링 최적화 기법을 다룹니다.

---

## 개요

각 플랫폼은 고유한 하드웨어 특성과 제약을 가지며, 이에 맞는 최적화가 필요합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   플랫폼별 특성 비교                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  특성        │ PC        │ Console   │ Mobile    │ VR         │
│  ────────────┼───────────┼───────────┼───────────┼────────────│
│  GPU 성능    │ 가변      │ 고정      │ 제한적    │ 중상       │
│  메모리      │ 8-32GB    │ 16GB      │ 2-8GB     │ 8-24GB     │
│  대역폭      │ 높음      │ 높음      │ 제한적    │ 높음       │
│  해상도      │ 1080-4K+  │ 1080-4K   │ 720-1440  │ 2K×2 (양안)│
│  목표 FPS    │ 60-144    │ 30-60     │ 30-60     │ 72-120     │
│  열 관리     │ 여유      │ 고정      │ 중요      │ 중요       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## PC 최적화

### 스케일러블 품질 시스템

```cpp
// Scalability 그룹 설정
// Engine/Config/BaseScalability.ini

[ScalabilitySettings]
; 품질 레벨: 0=Low, 1=Medium, 2=High, 3=Epic, 4=Cinematic

[ShadowQuality@0]
r.Shadow.MaxResolution=512
r.Shadow.CSM.MaxCascades=1
r.Shadow.RadiusThreshold=0.06

[ShadowQuality@3]
r.Shadow.MaxResolution=2048
r.Shadow.CSM.MaxCascades=4
r.Shadow.RadiusThreshold=0.01
```

### 동적 해상도

```cpp
// 동적 해상도 스케일링
r.DynamicRes.OperationMode 2  // 자동 조절

// 범위 설정
r.DynamicRes.MinScreenPercentage 50
r.DynamicRes.MaxScreenPercentage 100

// 목표 프레임 시간 (ms)
r.DynamicRes.TargetedGPUHeadroom 3.0
```

### DLSS/FSR 통합

```cpp
// NVIDIA DLSS
r.NGX.DLSS.Enable 1
r.NGX.DLSS.Quality 1  // 0=Performance, 1=Balanced, 2=Quality, 3=Ultra Quality

// AMD FSR 2.0
r.FidelityFX.FSR2.Enabled 1
r.FidelityFX.FSR2.QualityMode 1  // 0=Performance, 1=Balanced, 2=Quality

// Intel XeSS
r.XeSS.Enabled 1
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    업스케일링 기술 비교                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기술      │ 내부 해상도  │ 출력 해상도 │ 성능 향상  │ 요구사항 │
│  ──────────┼──────────────┼─────────────┼────────────┼─────────│
│  Native    │ 4K           │ 4K          │ 0%         │ -       │
│  DLSS Qual │ 1440p        │ 4K          │ 40-60%     │ RTX GPU │
│  DLSS Perf │ 1080p        │ 4K          │ 80-100%    │ RTX GPU │
│  FSR2 Qual │ 1440p        │ 4K          │ 30-50%     │ Any GPU │
│  FSR2 Perf │ 1080p        │ 4K          │ 60-80%     │ Any GPU │
│  TSR       │ Variable     │ 4K          │ 20-40%     │ UE5     │
│                                                                 │
│  ※ 성능 향상은 GPU 병목 상황에서의 대략적인 수치               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 멀티 GPU 지원

```cpp
// SLI/CrossFire 지원 (레거시)
r.AllowMultiGPUInEditor 1

// Explicit Multi-GPU (D3D12)
// 각 GPU에 프레임 분배
r.D3D12.ExplicitMultiGPU 1
```

---

## 콘솔 최적화 (PS5/Xbox Series X)

### 고정 하드웨어 타겟팅

```cpp
// 플랫폼별 설정
// Config/PS5/PS5Engine.ini
// Config/XboxSeriesX/XboxSeriesXEngine.ini

[/Script/Engine.RendererSettings]
r.DefaultFeature.AntiAliasing=2
r.DefaultFeature.MotionBlur=True

// 콘솔 전용 최적화
r.GPUBusyWait=1  // GPU 동기화 최적화
```

### 메모리 관리

```cpp
// 콘솔 메모리 예산 (16GB 공유)
// 게임 로직: ~4-5GB
// 렌더링: ~6-8GB
// 시스템/OS: ~2-3GB

// 텍스처 스트리밍 풀
r.Streaming.PoolSize 1500  // 콘솔 권장값

// Unified Memory 활용
// GPU와 CPU가 메모리 공유 - 복사 최소화
```

### 콘솔 전용 기능

```cpp
// PS5 특화
// - 컴프레서 (Kraken) 활용
// - SSD 직접 로드

// Xbox Series X 특화
// - Sampler Feedback (텍스처 스트리밍 최적화)
// - Variable Rate Shading (VRS)
r.VRS.Enable 1
r.VRS.MaxRate 4  // 최대 4x4 셰이딩 비율
```

### 성능/품질 모드

```cpp
// 성능 모드 (60fps, 동적 1440p)
[PerformanceMode]
r.ScreenPercentage=75
r.DynamicRes.MinScreenPercentage=60
r.Shadow.CSM.MaxCascades=2

// 품질 모드 (30fps, 네이티브 4K)
[QualityMode]
r.ScreenPercentage=100
r.Shadow.CSM.MaxCascades=4
r.Lumen.Reflections.Allow=1
```

---

## 모바일 최적화

### 모바일 렌더러 특성

```
┌─────────────────────────────────────────────────────────────────┐
│                   모바일 렌더링 아키텍처                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Tile-Based Deferred Rendering (TBDR):                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │           화면을 타일로 분할하여 처리                     │    │
│  │  ┌────┬────┬────┬────┐                                  │    │
│  │  │Tile│Tile│Tile│Tile│  → 각 타일을 온칩 메모리에서     │    │
│  │  │ 1  │ 2  │ 3  │ 4  │    처리 (대역폭 절약)            │    │
│  │  ├────┼────┼────┼────┤                                  │    │
│  │  │Tile│Tile│Tile│Tile│  → 타일 완료 후 메모리에 쓰기    │    │
│  │  │ 5  │ 6  │ 7  │ 8  │                                  │    │
│  │  └────┴────┴────┴────┘                                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  TBDR 최적화 원칙:                                              │
│  - Render Target 스위칭 최소화 (타일 플러시 발생)              │
│  - 불필요한 Clear 피하기                                       │
│  - Discard 적극 활용                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 모바일 셰이딩 모델

```cpp
// Forward 렌더링 (모바일 기본)
r.Mobile.ForwardShading=1

// 모바일 셰이딩 모델 제한
// - Lit (기본)
// - Unlit
// - DefaultLit (단순화)

// 모바일 머티리얼 품질
r.MaterialQualityLevel 0  // Low
r.MaterialQualityLevel 1  // Medium (권장)
r.MaterialQualityLevel 2  // High
```

### 모바일 텍스처 압축

```cpp
// ASTC 압축 (iOS/Android)
// Project Settings > Platforms > iOS/Android

// 권장 설정
// Diffuse: ASTC 6x6 (2.67 bpp)
// Normal: ASTC 4x4 (4 bpp)
// UI: RGBA8 (32 bpp, 비압축)

// ETC2 (Android 폴백)
// 구형 기기 호환
```

### 모바일 라이팅 최적화

```cpp
// 동적 라이트 제한
// 권장: 방향 광원 1개 + 포인트/스팟 2-3개

// 섀도우 품질
r.Shadow.MaxResolution 512
r.Shadow.CSM.MaxCascades 1  // 모바일은 1 권장

// 라이트맵 활용
// 가능하면 정적 라이팅 사용
```

### 모바일 포스트 프로세스

```cpp
// 모바일 포스트 프로세스 제한
// 비용이 높은 효과 비활성화

// 권장 비활성화:
r.BloomQuality 0           // 또는 1 (저품질)
r.MotionBlurQuality 0
r.AmbientOcclusionLevels 0
r.DOF.GatherRing 0

// 활성화 가능:
r.Tonemapper.Quality 1
// 비네트 (저비용)
```

### 열 관리

```cpp
// 발열 방지를 위한 프레임 제한
t.MaxFPS 30  // 30fps 제한
t.MaxFPS 60  // 60fps 고성능 기기

// CPU/GPU 부하 분산
// 프레임마다 모든 작업 수행 대신
// 여러 프레임에 분산
```

---

## VR 최적화

### VR 렌더링 특성

```
┌─────────────────────────────────────────────────────────────────┐
│                      VR 렌더링 요구사항                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  해상도 (Quest 2 예시):                                         │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Left Eye: 1832 × 1920  │  Right Eye: 1832 × 1920     │    │
│  │                                                         │    │
│  │  총 픽셀: 약 700만 (1080p의 3배 이상)                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  목표 FPS:                                                      │
│  - Quest 2: 72Hz, 90Hz, 120Hz                                  │
│  - PCVR: 90Hz (11.1ms per frame)                               │
│  - Index: 120Hz, 144Hz                                         │
│                                                                 │
│  주요 과제:                                                     │
│  - 양안 렌더링 (2× 비용)                                       │
│  - 낮은 레이턴시 필수                                          │
│  - 멀미 방지를 위한 안정적 FPS                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Instanced Stereo Rendering

```cpp
// 양안 인스턴스드 렌더링 (필수)
vr.InstancedStereo 1

// 작동 방식:
// - 한 번의 Draw Call로 양안 렌더링
// - Geometry Shader로 좌우 분리
// - 50%+ Draw Call 감소
```

### Fixed Foveated Rendering

```cpp
// 주변부 해상도 낮추기
// (눈의 중심시야 외곽은 해상도 낮아도 인지 못함)

// Quest 2 FFR
vr.OculusQuest.FFRLevel 3  // 0-4 (높을수록 공격적)

// 해상도 분포:
// 중앙: 100%
// 중간: 75%
// 외곽: 50%
```

```
┌─────────────────────────────────────────────────────────────────┐
│                  Fixed Foveated Rendering                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │           ┌───────────────────┐                           │  │
│  │           │                   │                           │  │
│  │     ┌─────┤   중앙 (100%)     ├─────┐                     │  │
│  │     │     │   Full Res       │     │                     │  │
│  │     │     └───────────────────┘     │                     │  │
│  │     │           중간 (75%)          │                     │  │
│  │     │          Medium Res          │                     │  │
│  │     └───────────────────────────────┘                     │  │
│  │                외곽 (50%)                                 │  │
│  │               Low Res                                    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  → 렌더링 비용 30-50% 절감 (시각적 품질 손실 최소)             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### VR 최적화 설정

```cpp
// Forward Shading 권장 (VR)
r.ForwardShading 1

// 포스트 프로세스 제한
r.BloomQuality 3  // 낮춤
r.MotionBlur 0    // VR에서 멀미 유발

// 섀도우 최적화
r.Shadow.CSM.MaxCascades 2
r.Shadow.MaxResolution 1024

// MSAA (Forward 렌더링에서만)
r.MSAACount 4
```

### 레이턴시 최적화

```cpp
// Late Latching (위치 업데이트 지연 최소화)
vr.bEnableLateVelocityTrans 1

// ASW/SSW (프레임 보간)
// 드롭 프레임 시 이전 프레임 기반 보간

// Motion-to-Photon 최소화
// 목표: < 20ms
```

---

## 플랫폼 공통 최적화

### 프로파일 기반 최적화

```cpp
// 플랫폼별 프로파일
#if PLATFORM_DESKTOP
    // PC 전용 설정
    r.Shadow.MaxResolution = 2048;
#elif PLATFORM_CONSOLE
    // 콘솔 전용 설정
    r.Shadow.MaxResolution = 1024;
#elif PLATFORM_MOBILE
    // 모바일 전용 설정
    r.Shadow.MaxResolution = 512;
#endif
```

### Device Profile

```cpp
// DefaultDeviceProfiles.ini

[Android_High DeviceProfile]
DeviceType=Android
BaseProfileName=Android
+CVars=r.MobileContentScaleFactor=1.5
+CVars=r.Shadow.MaxResolution=1024
+CVars=r.MaterialQualityLevel=2

[Android_Low DeviceProfile]
DeviceType=Android
BaseProfileName=Android
+CVars=r.MobileContentScaleFactor=1.0
+CVars=r.Shadow.MaxResolution=256
+CVars=r.MaterialQualityLevel=0
```

---

## 콘솔 명령 요약

```cpp
// PC
r.ScreenPercentage 100
r.DynamicRes.OperationMode 2
r.NGX.DLSS.Enable 1

// 콘솔
r.GPUBusyWait 1
r.VRS.Enable 1
stat rhi

// 모바일
r.Mobile.ForwardShading 1
r.MaterialQualityLevel 1
stat engine

// VR
vr.InstancedStereo 1
r.ForwardShading 1
r.VR.PixelDensity 1.0
```

---

## 요약

| 플랫폼 | 핵심 최적화 | 목표 |
|--------|-------------|------|
| PC | 스케일러빌리티, DLSS/FSR | 가변 품질, 60-144fps |
| 콘솔 | 고정 예산, VRS | 30/60fps 안정 |
| 모바일 | TBDR 활용, Forward | 30fps, 발열 관리 |
| VR | Instanced Stereo, FFR | 90+fps, 저레이턴시 |

---

## 참고 자료

- [Console Development](https://docs.unrealengine.com/console-development/)
- [Mobile Rendering](https://docs.unrealengine.com/mobile-rendering/)
- [VR Performance](https://docs.unrealengine.com/vr-performance/)
- [DLSS Integration](https://developer.nvidia.com/dlss)
