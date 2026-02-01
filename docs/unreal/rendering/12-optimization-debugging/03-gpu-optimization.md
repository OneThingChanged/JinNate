# GPU 최적화

GPU 병목 해결을 위한 셰이더, 대역폭, Fillrate, 오버드로우 최적화 기법을 다룹니다.

---

## 개요

GPU 병목은 셰이더 복잡도, 메모리 대역폭, Fillrate 제한에서 발생합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                      GPU 파이프라인 병목                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐        │
│  │ Vertex  │──▶│Rasterize│──▶│ Pixel   │──▶│ Output  │        │
│  │ Shader  │   │         │   │ Shader  │   │ Merger  │        │
│  └────┬────┘   └────┬────┘   └────┬────┘   └────┬────┘        │
│       │             │             │             │               │
│       ▼             ▼             ▼             ▼               │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐        │
│  │ 버텍스  │   │ 삼각형  │   │ Fillrate│   │대역폭   │        │
│  │ 처리량  │   │ 처리량  │   │ 제한    │   │ 제한    │        │
│  └─────────┘   └─────────┘   └─────────┘   └─────────┘        │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                      병목 식별 방법                              │
│                                                                 │
│  해상도 낮춤 → FPS 상승?  → Fillrate/Pixel Shader 병목         │
│  메시 복잡도 ↓ → FPS 상승? → Vertex 처리 병목                   │
│  텍스처 크기 ↓ → FPS 상승? → 대역폭 병목                        │
│  셰이더 단순화 → FPS 상승? → ALU 병목                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 셰이더 최적화

### 인스트럭션 수 줄이기

```hlsl
// BAD: 불필요한 계산
float3 Normal = normalize(WorldNormal);
float3 ViewDir = normalize(CameraPos - WorldPos);
float NdotV = saturate(dot(Normal, ViewDir));
float Fresnel = pow(1.0 - NdotV, 5.0);  // pow는 비용이 큼

// GOOD: 근사 사용
float3 Normal = normalize(WorldNormal);
float3 ViewDir = normalize(CameraPos - WorldPos);
float NdotV = saturate(dot(Normal, ViewDir));
// Schlick 근사: pow(x,5) ≈ x^2 * x^2 * x
float x = 1.0 - NdotV;
float x2 = x * x;
float Fresnel = x2 * x2 * x;
```

### 분기 최적화

```hlsl
// BAD: 동적 분기
if (MaterialType == 1)
    Color = SampleMetal(UV);
else if (MaterialType == 2)
    Color = SampleWood(UV);
else
    Color = SamplePlastic(UV);

// GOOD: 정적 분기 (컴파일 타임)
#if MATERIAL_METAL
    Color = SampleMetal(UV);
#elif MATERIAL_WOOD
    Color = SampleWood(UV);
#else
    Color = SamplePlastic(UV);
#endif

// GOOD: lerp으로 분기 제거 (값이 작을 때)
Color = lerp(PlasticColor, MetalColor, IsMetal);
```

### 텍스처 샘플링 최적화

```hlsl
// BAD: 종속 텍스처 읽기
float2 DistortedUV = UV + Texture2DSample(DistortMap, UV).rg;
float4 Color = Texture2DSample(MainTex, DistortedUV);  // 종속!

// BETTER: 가능하면 독립적으로
// 또는 낮은 MIP에서 샘플링
float2 DistortedUV = UV + Texture2DSampleLevel(DistortMap, UV, 2.0).rg;
float4 Color = Texture2DSample(MainTex, DistortedUV);

// LOD 강제로 대역폭 절약
float4 Color = Texture2DSampleLevel(Tex, UV, MipLevel);
float4 Color = Texture2DSampleBias(Tex, UV, BiasValue);
```

### 정밀도 최적화

```hlsl
// 모바일에서 half 사용
// 데스크탑에서도 일부 GPU에서 이점

// BAD: 불필요한 고정밀도
float4 Color = Texture2DSample(Tex, UV);
float Luminance = dot(Color.rgb, float3(0.299, 0.587, 0.114));

// GOOD: 적절한 정밀도
half4 Color = Texture2DSample(Tex, UV);
half Luminance = dot(Color.rgb, half3(0.299, 0.587, 0.114));

// 정밀도 가이드라인:
// - UV 좌표: float 유지 (정밀도 필요)
// - 색상: half로 충분
// - 노멀: half로 충분
// - 깊이/위치: float 필요
```

---

## Fillrate 최적화

### 오버드로우 감소

```
┌─────────────────────────────────────────────────────────────────┐
│                      오버드로우 문제                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  오버드로우 = 동일 픽셀을 여러 번 렌더링                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │         ┌─────────┐                                     │    │
│  │         │ Object1 │ (Draw 1)                            │    │
│  │    ┌────┼─────────┼────┐                                │    │
│  │    │    │  ▓▓▓▓▓  │    │ ← 겹치는 영역                  │    │
│  │    │    └─────────┘    │   = 2x 오버드로우              │    │
│  │    │      Object2      │ (Draw 2)                       │    │
│  │    └───────────────────┘                                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  해결책:                                                        │
│  1. Front-to-Back 정렬 (불투명)                                │
│  2. Early-Z 활용                                               │
│  3. PrePass (Depth Prepass)                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Early-Z 활용

```cpp
// Early-Z 깨지는 경우:
// 1. clip()/discard 사용
// 2. 깊이 쓰기 수정
// 3. 알파 테스트

// Early-Z 유지를 위한 PrePass
r.EarlyZPass 2  // 전체 PrePass
r.EarlyZPassMovable 1  // 동적 오브젝트도 포함
```

```hlsl
// BAD: clip이 Early-Z 깨뜨림
void MainPS(...)
{
    float Alpha = Texture2DSample(AlphaTex, UV).a;
    clip(Alpha - 0.5);  // Early-Z 비활성화
    // ...
}

// BETTER: Masked 머티리얼은 PrePass 사용
// 또는 Alpha to Coverage 사용
```

### 해상도 스케일링

```cpp
// 동적 해상도
r.DynamicRes.OperationMode 2
r.DynamicRes.MinScreenPercentage 50
r.DynamicRes.MaxScreenPercentage 100

// 수동 해상도 조절
r.ScreenPercentage 75  // 75% 해상도

// 개별 패스 해상도
r.SSR.HalfResSceneColor 1  // SSR 절반 해상도
r.AmbientOcclusion.Method 2  // GTAO (더 효율적)
```

### 복잡한 셰이더 영역 제한

```cpp
// 스텐실로 복잡한 셰이더 영역 제한
// 1. 먼저 싼 패스로 영역 마킹
// 2. 스텐실 테스트로 비싼 셰이더 제한

// Decal 최적화
r.Decal.StencilSizeThreshold 0.05  // 작은 데칼 스텐실 스킵
```

---

## 대역폭 최적화

### 텍스처 포맷 선택

```
┌─────────────────────────────────────────────────────────────────┐
│                    텍스처 포맷별 대역폭                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  포맷             │ BPP │ 1K 텍스처  │ 용도                     │
│  ─────────────────┼─────┼───────────┼────────────────────────  │
│  R8G8B8A8         │ 32  │   4 MB    │ 비압축 컬러              │
│  BC1 (DXT1)       │  4  │ 0.5 MB    │ 컬러 (알파 없음)         │
│  BC3 (DXT5)       │  8  │   1 MB    │ 컬러 + 알파              │
│  BC5              │  8  │   1 MB    │ 노멀맵                   │
│  BC7              │  8  │   1 MB    │ 고품질 컬러              │
│  ASTC 4x4         │  8  │   1 MB    │ 모바일 고품질            │
│  ASTC 8x8         │  2  │ 0.25 MB   │ 모바일 저품질            │
│                                                                 │
│  ※ 압축 포맷 사용으로 대역폭 4-8배 절약                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### MIP 맵 활용

```cpp
// MIP 맵 강제 생성
TextureSettings.MipGenSettings = TextureMipGenSettings::TMGS_FromTextureGroup;

// MIP 바이어스로 대역폭 절약
r.MipMapLODBias 0.5  // 한 단계 낮은 MIP 사용

// 스트리밍 풀 크기
r.Streaming.PoolSize 1000  // MB 단위
```

```
┌─────────────────────────────────────────────────────────────────┐
│                      MIP 맵 대역폭 이점                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  거리에 따른 MIP 레벨:                                          │
│                                                                 │
│  ┌────────────────────┐  ┌────────┐  ┌────┐  ┌──┐  ┌┐          │
│  │                    │  │        │  │    │  │  │  ││          │
│  │      1024x1024     │  │ 512x512│  │256 │  │128│  │64        │
│  │       MIP 0        │  │ MIP 1  │  │MIP2│  │ 3 │  │4         │
│  │                    │  │        │  │    │  │  │  ││          │
│  └────────────────────┘  └────────┘  └────┘  └──┘  └┘          │
│                                                                 │
│  가까움 ◀──────────────────────────────────────────▶ 멀리     │
│                                                                 │
│  → 먼 오브젝트는 낮은 MIP으로 대역폭 절약                       │
│  → 캐시 효율 증가                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### G-Buffer 최적화

```cpp
// G-Buffer 대역폭 줄이기
r.GBufferFormat 0  // 기본 (가장 효율적)
r.GBufferFormat 1  // 고정밀도 (HDR)

// Velocity Buffer 조건부
r.BasePassOutputsVelocity 0  // 필요시만 활성화

// 모바일 대역폭 절감
r.Mobile.UseHWsRGBEncoding 1
```

### Render Target 최적화

```cpp
// 렌더 타겟 포맷 선택
// PF_FloatRGBA (64bpp) vs PF_A2B10G10R10 (32bpp)
// 정밀도가 충분하면 작은 포맷 사용

// 임시 렌더 타겟 재사용
FPooledRenderTargetDesc Desc;
Desc.Extent = FIntPoint(Width, Height);
Desc.Format = PF_R8G8B8A8;
Desc.Flags = TexCreate_RenderTargetable | TexCreate_ShaderResource;

// 풀에서 할당 (재사용)
TRefCountPtr<IPooledRenderTarget> RT;
GRenderTargetPool.FindFreeElement(GraphBuilder.RHICmdList, Desc, RT, TEXT("TempRT"));
```

---

## 지오메트리 최적화

### LOD 설정

```cpp
// 자동 LOD 생성
StaticMesh->LODGroup = TEXT("LargeWorld");

// LOD 거리 설정
StaticMesh->SourceModels[0].ScreenSize = 1.0f;   // LOD0
StaticMesh->SourceModels[1].ScreenSize = 0.5f;   // LOD1
StaticMesh->SourceModels[2].ScreenSize = 0.25f;  // LOD2

// LOD 전환 부드럽게
StaticMeshComponent->bOverrideMinLOD = true;
StaticMeshComponent->MinLOD = 0;
```

```
┌─────────────────────────────────────────────────────────────────┐
│                        LOD 전략                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  거리        0m      50m     100m    200m    500m+             │
│              │       │       │       │       │                  │
│  LOD         0       1       2       3       Cull               │
│              │       │       │       │       │                  │
│  삼각형   10,000   5,000   2,000    500      0                  │
│              │       │       │       │       │                  │
│  ┌──────────┼───────┼───────┼───────┼───────┤                  │
│  │██████████│▓▓▓▓▓▓▓│░░░░░░░│•••••••│       │                  │
│  └──────────┴───────┴───────┴───────┴───────┘                  │
│                                                                 │
│  LOD 전환 품질:                                                 │
│  - Dithered: 부드러운 전환 (추가 비용)                         │
│  - Instant: 즉시 전환 (팝핑 발생 가능)                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Nanite 활용 (UE5)

```cpp
// Nanite 활성화 (자동 LOD)
StaticMesh->NaniteSettings.bEnabled = true;

// Nanite 장점:
// - 자동 LOD (수백만 폴리곤 처리)
// - GPU 기반 컬링
// - 오버드로우 최소화

// Nanite 제한:
// - Skeletal Mesh 미지원
// - 투명/Masked 제한
// - 일부 머티리얼 기능 미지원
```

### 작은 삼각형 문제

```cpp
// 작은 삼각형은 GPU 효율 저하
// 픽셀보다 작은 삼각형 = 쿼드 오버헤드

// 해결책:
// 1. LOD로 먼 거리에서 폴리곤 감소
// 2. Nanite 사용 (자동 처리)
// 3. 메시 단순화

r.MeshDrawCommands.UseCachedCommands 1  // Draw Command 캐싱
```

---

## 라이팅 최적화

### 라이트 수 제한

```cpp
// 동적 라이트 영향 범위 제한
Light->AttenuationRadius = 500.0f;
Light->bUseInverseSquaredFalloff = true;

// 라이트 채널로 영향 제한
Light->LightingChannels.bChannel0 = true;
Light->LightingChannels.bChannel1 = false;
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    라이트 최적화 전략                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  라이트 타입별 비용:                                            │
│                                                                 │
│  Directional Light:   ████████████████████  (전체 씬)          │
│  Spot Light:          ████████░░░░░░░░░░░░  (원뿔 영역)        │
│  Point Light:         ██████████░░░░░░░░░░  (구 영역)          │
│  Rect Light:          ████████████░░░░░░░░  (영역 광원)        │
│                                                                 │
│  최적화:                                                        │
│  - 필요한 곳만 동적 라이트 사용                                 │
│  - Stationary 라이트 활용 (섀도우 베이크)                      │
│  - 라이트 함수로 영역 제한                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 섀도우 최적화

```cpp
// 캐스케이드 섀도우 최적화
r.Shadow.CSM.MaxCascades 3       // 캐스케이드 수 줄이기
r.Shadow.MaxResolution 1024      // 해상도 제한
r.Shadow.RadiusThreshold 0.03    // 작은 오브젝트 제외

// 거리 기반 섀도우
DirectionalLight->DynamicShadowDistanceMovableLight = 5000.0f;
DirectionalLight->DynamicShadowCascades = 3;

// 오브젝트별 섀도우 설정
Component->CastShadow = false;  // 섀도우 비활성화
Component->bCastDynamicShadow = false;
Component->bCastStaticShadow = true;  // 정적만
```

### 반사 최적화

```cpp
// SSR 품질 조절
r.SSR.Quality 2  // 0-4 (낮을수록 빠름)
r.SSR.HalfResSceneColor 1  // 절반 해상도

// 반사 캡처 해상도
r.ReflectionCaptureResolution 256  // 기본 128

// Lumen 반사 (UE5)
r.Lumen.Reflections.ScreenSpaceTracing 1
r.Lumen.Reflections.MaxRoughnessToTrace 0.4
```

---

## 포스트 프로세스 최적화

### 효과별 비용

```
┌─────────────────────────────────────────────────────────────────┐
│                  포스트 프로세스 비용 순위                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  효과                    상대 비용    최적화 옵션               │
│  ─────────────────────  ──────────  ────────────────────────   │
│  TSR/TAA               ████████     r.TSR.Quality              │
│  DOF                   ████████     r.DOF.Quality              │
│  Motion Blur           ██████░░     r.MotionBlurQuality        │
│  Bloom                 ████░░░░     r.BloomQuality             │
│  SSAO                  ██████░░     r.AmbientOcclusion.Quality │
│  SSR                   ████████     r.SSR.Quality              │
│  Color Grading         ██░░░░░░     항상 적용                   │
│  Vignette             █░░░░░░░     무시 가능                   │
│                                                                 │
│  ※ 모바일에서는 대부분 비활성화 권장                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 품질 설정

```cpp
// 포스트 프로세스 품질 일괄 조절
r.PostProcessAAQuality 4  // TAA 품질
r.BloomQuality 4          // 블룸 품질
r.MotionBlurQuality 3     // 모션 블러 품질
r.AmbientOcclusionLevels 2  // SSAO 레벨

// 효과 비활성화
PostProcessSettings.bOverride_BloomIntensity = true;
PostProcessSettings.BloomIntensity = 0.0f;
```

---

## 콘솔 명령 요약

```cpp
// GPU 병목 분석
stat gpu
profilegpu

// 셰이더 복잡도
viewmode shadercomplexity
viewmode quadoverdraw
viewmode lightcomplexity

// 해상도 테스트
r.ScreenPercentage 50

// 개별 기능 테스트
r.Shadow.CSM.MaxCascades 1
r.SSR.Quality 0
r.BloomQuality 0

// GPU 메모리
stat rhi
r.Streaming.PoolSize
```

---

## 요약

| 병목 유형 | 진단 방법 | 해결책 |
|----------|----------|--------|
| Fillrate | 해상도 낮춤 → FPS↑ | 해상도 스케일링, 오버드로우 감소 |
| 셰이더 ALU | 셰이더 단순화 → FPS↑ | 인스트럭션 최적화, 정밀도 조정 |
| 대역폭 | 텍스처 크기↓ → FPS↑ | 압축 포맷, MIP 활용 |
| 지오메트리 | 폴리곤↓ → FPS↑ | LOD, Nanite |

---

## 참고 자료

- [GPU Performance Optimization](https://docs.unrealengine.com/gpu-profiling/)
- [Shader Optimization Guide](https://docs.unrealengine.com/shader-development/)
- [Mobile Rendering](https://docs.unrealengine.com/mobile-rendering/)
