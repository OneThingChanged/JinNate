# 패스 트레이싱

UE의 패스 트레이싱 렌더러와 물리 기반 글로벌 일루미네이션을 분석합니다.

---

## 패스 트레이싱 원리

### 레이 트레이싱 vs 패스 트레이싱

```
┌─────────────────────────────────────────────────────────────────┐
│                  렌더링 방식 비교                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Rasterization (래스터화):                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  삼각형 ──▶ 화면 투영 ──▶ 픽셀 셰이딩                   │   │
│  │                                                          │   │
│  │  • 빠름 (실시간)                                         │   │
│  │  • 근사적 라이팅 (Deferred, Forward)                    │   │
│  │  • GI는 베이크 또는 Lumen                               │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Ray Tracing (하이브리드):                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  래스터화 + 선택적 레이 (반사, 그림자, AO)               │   │
│  │                                                          │   │
│  │  • 준실시간 (30-60 FPS 가능)                            │   │
│  │  • 정확한 반사/그림자                                    │   │
│  │  • 제한된 바운스                                         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Path Tracing (풀 레이 트레이싱):                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  픽셀 ──▶ 레이 발사 ──▶ 씬 교차 ──▶ 다시 레이...        │   │
│  │                                                          │   │
│  │  Eye ──○──────────────────────▶ Light                   │   │
│  │           ╲                  ╱                          │   │
│  │            ╲   반사        ╱ 간접광                     │   │
│  │             ╲            ╱                              │   │
│  │              ●──────────●                               │   │
│  │            Surface    Surface                           │   │
│  │                                                          │   │
│  │  • 느림 (프레임당 수초-수분)                             │   │
│  │  • 물리적으로 정확                                       │   │
│  │  • 무한 바운스 가능                                      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 패스 트레이싱 알고리즘

```cpp
// 단순화된 패스 트레이싱 알고리즘
float3 PathTrace(Ray ray, int depth)
{
    if (depth > MaxBounces)
        return float3(0, 0, 0);

    HitResult hit = TraceRay(ray);

    if (!hit.Valid)
        return SampleEnvironment(ray.Direction);

    // 표면 정보
    Material mat = GetMaterial(hit);
    float3 normal = hit.Normal;
    float3 wo = -ray.Direction;  // 나가는 방향

    // 직접광
    float3 directLight = SampleDirectLight(hit.Position, normal, mat);

    // 간접광 (재귀)
    float3 wi;
    float pdf;
    float3 brdfValue = SampleBRDF(mat, wo, normal, wi, pdf);

    Ray bounceRay;
    bounceRay.Origin = hit.Position + normal * 0.001f;
    bounceRay.Direction = wi;

    float cosTheta = max(0, dot(normal, wi));
    float3 indirectLight = PathTrace(bounceRay, depth + 1);

    float3 indirect = brdfValue * indirectLight * cosTheta / pdf;

    return mat.Emission + directLight + indirect;
}

// 픽셀당 여러 샘플 (노이즈 감소)
float3 RenderPixel(int x, int y, int sampleCount)
{
    float3 color = float3(0, 0, 0);

    for (int s = 0; s < sampleCount; s++)
    {
        Ray ray = GenerateCameraRay(x, y, s);
        color += PathTrace(ray, 0);
    }

    return color / sampleCount;
}
```

---

## UE 패스 트레이싱 설정

### 활성화 방법

```cpp
// 프로젝트 설정
// Project Settings → Engine → Rendering → Ray Tracing

// DefaultEngine.ini
[/Script/Engine.RendererSettings]
r.RayTracing=True
r.RayTracing.EnablePathTracing=True

// 런타임 전환
// 뷰포트 → Lit → Path Tracing
// 또는 콘솔:
r.PathTracing.MaxBounces=32
r.PathTracing.SamplesPerPixel=1024
```

### 품질 설정

```
┌─────────────────────────────────────────────────────────────────┐
│                  Path Tracing 품질 설정                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  샘플 수 (Samples Per Pixel):                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1 SPP     16 SPP      64 SPP     256 SPP    1024 SPP   │   │
│  │  ░░░░░░    ▒▒▒▒▒▒      ▓▓▓▓▓▓     ████████   ████████   │   │
│  │  많은 노이즈  노이즈 있음  약간 노이즈  거의 깨끗  깨끗    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  바운스 수 (Max Bounces):                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  바운스   효과                                           │   │
│  │  ───────────────────────────────────────────────────    │   │
│  │    1      직접광만                                       │   │
│  │    2      1차 간접광                                     │   │
│  │    4      부드러운 GI                                    │   │
│  │    8+     완전한 GI (실내 씬)                            │   │
│  │   32      대부분 수렴                                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  권장 설정:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  용도              SPP       Bounces    렌더 시간        │   │
│  │  ─────────────────────────────────────────────────────  │   │
│  │  프리뷰            16-64     4-8        수초            │   │
│  │  중간 품질         256       16         수분            │   │
│  │  최종 렌더         1024+     32         수십분          │   │
│  │  건축 시각화       2048+     64         수시간          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 디노이징

### 노이즈 제거 기법

```
┌─────────────────────────────────────────────────────────────────┐
│                    Denoising 기법                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Temporal Accumulation (시간 누적):                          │
│     ┌─────────────────────────────────────────────────────┐    │
│     │                                                      │    │
│     │  Frame 1    Frame 2    Frame 3    ...    Frame N    │    │
│     │    ░░░   +    ░░░   +    ░░░   +        =  ████     │    │
│     │                                                      │    │
│     │  • 정지 장면에 효과적                                │    │
│     │  • 카메라 이동 시 리셋                               │    │
│     │                                                      │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. Spatial Denoising (공간 필터링):                            │
│     ┌─────────────────────────────────────────────────────┐    │
│     │                                                      │    │
│     │  • Bilateral Filter                                  │    │
│     │  • NLM (Non-Local Means)                            │    │
│     │  • Edge-preserving 필터                              │    │
│     │                                                      │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. AI Denoising (딥러닝):                                      │
│     ┌─────────────────────────────────────────────────────┐    │
│     │                                                      │    │
│     │  • NVIDIA OptiX Denoiser                            │    │
│     │  • Intel Open Image Denoise                         │    │
│     │  • UE 내장 디노이저                                  │    │
│     │                                                      │    │
│     │  입력: 노이즈 이미지 + Albedo + Normal              │    │
│     │  출력: 깨끗한 이미지                                 │    │
│     │                                                      │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 디노이저 설정

```cpp
// 디노이저 설정
// Post Process Volume → Path Tracing

UPROPERTY(EditAnywhere, Category = "Path Tracing")
struct FPathTracingDenoiser
{
    // 디노이저 타입
    EPathTracingDenoiserType DenoiserType = EPathTracingDenoiserType::OIDN;

    // 디노이저 강도
    float DenoiserStrength = 1.0f;

    // 알베도/노말 가이드 사용
    bool bUseAlbedoGuide = true;
    bool bUseNormalGuide = true;
};

// 콘솔 설정
r.PathTracing.Denoiser=1              // 디노이저 활성화
r.PathTracing.DenoiserType=1          // 0=None, 1=OIDN, 2=OptiX
```

---

## 머티리얼 호환성

### Path Tracing 머티리얼

```cpp
// Path Tracing에서 지원하는 셰이딩 모델
// • Default Lit
// • Subsurface
// • Subsurface Profile
// • Clear Coat
// • Two Sided Foliage
// • Thin Translucent

// 주의사항:
// • World Position Offset: 지원됨 (but 성능 비용)
// • Pixel Depth Offset: 미지원
// • Custom Lighting: 미지원 (물리 기반만)
// • Decals: 제한적 지원

// Path Tracing 전용 노드
// 머티리얼 에디터에서 사용 가능:
// • PathTracingQualitySwitch
// • IsPathTracingEnabled

// 머티리얼 최적화
UPROPERTY(EditAnywhere, Category = "Path Tracing")
struct FPathTracingMaterialSettings
{
    // 반투명 처리
    ETranslucencyLightingMode TranslucencyMode;

    // IOR (굴절률)
    float IndexOfRefraction = 1.5f;

    // 분산 (Dispersion)
    float Dispersion = 0.0f;
};
```

---

## 라이팅 고려사항

### Area Lights

```
┌─────────────────────────────────────────────────────────────────┐
│                  Path Tracing 라이팅                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Point Light vs Area Light (Rect Light):                        │
│                                                                 │
│  Point Light:              Rect Light:                          │
│       ●                    ┌─────────────┐                     │
│      ╱│╲                   │             │                     │
│     ╱ │ ╲                  │   ■ ■ ■ ■   │                     │
│    ╱  │  ╲                 │   ■ ■ ■ ■   │                     │
│   ╱   │   ╲                │             │                     │
│  ▓▓▓▓▓▓▓▓▓▓▓               └─────────────┘                     │
│   Hard Shadow               ▓░░░░░░░░░░▓                       │
│                              Soft Shadow                        │
│                                                                 │
│  Path Tracing에서 Area Light 장점:                              │
│  • 자연스러운 소프트 섀도우                                     │
│  • 정확한 스페큘러 하이라이트                                   │
│  • 물리적으로 정확한 감쇠                                       │
│                                                                 │
│  HDRI 라이팅:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Sky Light (HDRI Cubemap)                               │   │
│  │  • 360도 환경 조명                                       │   │
│  │  • 실제 촬영 환경 재현                                   │   │
│  │  • Path Tracing에서 정확한 IBL                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 성능 최적화

### Path Tracing 최적화

```cpp
// 최적화 설정
r.PathTracing.MaxBounces=8            // 바운스 제한
r.PathTracing.EnableMaterials=1        // 머티리얼 활성화
r.PathTracing.EnableEmissive=1         // 이미시브 활성화
r.PathTracing.MaxPathIntensity=10      // 최대 강도 제한 (Firefly 방지)

// 적응형 샘플링
r.PathTracing.EnableAdaptiveSampling=1
r.PathTracing.AdaptiveSamplingMinSamples=16
r.PathTracing.AdaptiveSamplingVarianceThreshold=0.01

// 성능 팁:
// 1. 불필요한 바운스 제한
// 2. 머티리얼 복잡도 최소화
// 3. 대형 Area Light 크기 조절
// 4. 반투명 오브젝트 최소화
// 5. 적응형 샘플링 활용
```

---

## 다음 단계

- [Movie Render Queue](02-movie-render-queue.md)에서 오프라인 렌더링 도구를 학습합니다.
