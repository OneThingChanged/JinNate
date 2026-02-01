# 모바일 셰이더

모바일 플랫폼에 최적화된 셰이더 작성 기법과 ES3.1 제한사항을 분석합니다.

---

## ES3.1 셰이더 제한

### 리소스 제한

```
┌─────────────────────────────────────────────────────────────────┐
│                  OpenGL ES 3.1 리소스 제한                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  텍스처 유닛:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Vertex Shader:      16 texture units                    │   │
│  │ Fragment Shader:    16 texture units                    │   │
│  │ Combined:           최소 48 (디바이스별 다름)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  유니폼 제한:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Vertex Shader:      1024 vec4 components               │   │
│  │ Fragment Shader:    1024 vec4 components               │   │
│  │ UBO 크기:           최소 16KB                           │   │
│  │ UBO 바인딩:         최소 12                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Varying 제한:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Varying Components: 최소 64 (16 vec4)                   │   │
│  │                                                          │   │
│  │ 예시:                                                    │   │
│  │ • UV (vec2) = 2                                         │   │
│  │ • Normal (vec3) = 3                                     │   │
│  │ • Tangent (vec3) = 3                                    │   │
│  │ • Color (vec4) = 4                                      │   │
│  │ • WorldPos (vec3) = 3                                   │   │
│  │ • ShadowCoord (vec4) = 4                                │   │
│  │ 합계: 19 components (여유 있음)                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 정밀도 한정자

```hlsl
// 정밀도 타입 (GLSL/HLSL 매핑)
// highp   = 32-bit float (FP32)
// mediump = 16-bit float (FP16)
// lowp    = 10-bit float (거의 사용 안 함)

// UE HLSL에서 half 사용
// 모바일에서 실제 FP16으로 컴파일

// 정밀도 선택 가이드
struct MobilePrecisionGuide
{
    // highp (float) 필수:
    // - World Position
    // - Depth 계산
    // - 그림자 좌표
    // - 정밀한 UV 계산

    // mediump (half) 권장:
    // - 색상 값
    // - 노말 벡터 (정규화된)
    // - 라이팅 계산
    // - 텍스처 샘플링 결과

    // lowp 피하기:
    // - 대부분의 GPU에서 mediump과 동일
    // - 정밀도 이슈 발생 가능
};

// 예시: 최적화된 라이팅 계산
half3 MobileDirectionalLight(
    half3 N,           // mediump 노말
    half3 L,           // mediump 라이트 방향
    half3 V,           // mediump 뷰 방향
    half3 LightColor,  // mediump 라이트 색상
    half Roughness)    // mediump 러프니스
{
    half NdotL = saturate(dot(N, L));
    half3 H = normalize(L + V);
    half NdotH = saturate(dot(N, H));

    // 간소화된 스페큘러
    half SpecPower = exp2(10 * (1 - Roughness));
    half Spec = pow(NdotH, SpecPower);

    return LightColor * (NdotL + Spec);
}
```

---

## 모바일 셰이더 최적화

### ALU 최적화

```hlsl
// 나쁜 예: 불필요한 연산
float3 BadNormalize(float3 v)
{
    float len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return float3(v.x / len, v.y / len, v.z / len);
}

// 좋은 예: 내장 함수 사용
half3 GoodNormalize(half3 v)
{
    return normalize(v);  // 하드웨어 최적화
}

// 나쁜 예: 분기문
half3 BadBranch(half3 color, half threshold)
{
    if (color.r > threshold)
        return color * 2.0;
    else
        return color * 0.5;
}

// 좋은 예: 조건부 선택
half3 GoodBranch(half3 color, half threshold)
{
    half factor = color.r > threshold ? 2.0 : 0.5;
    return color * factor;
    // 또는
    // return lerp(color * 0.5, color * 2.0, step(threshold, color.r));
}

// 수학 최적화
half OptimizedMath()
{
    // 나쁜 예
    // half a = pow(x, 2.0);    // pow는 비쌈
    // half b = 1.0 / sqrt(x);  // rsqrt 사용

    // 좋은 예
    half a = x * x;           // 직접 곱셈
    half b = rsqrt(x);        // 역제곱근 내장함수

    // 나쁜 예
    // half c = log(x) / log(2.0);

    // 좋은 예
    half c = log2(x);         // log2 직접 사용

    return a + b + c;
}
```

### 텍스처 샘플링 최적화

```hlsl
// 텍스처 Fetch 최소화
struct OptimizedSampling
{
    // 나쁜 예: 중복 샘플링
    half4 bad = tex.Sample(samp, uv);
    half3 color = bad.rgb;
    half alpha = tex.Sample(samp, uv).a;  // 중복!

    // 좋은 예: 한 번만 샘플링
    half4 good = tex.Sample(samp, uv);
    half3 color = good.rgb;
    half alpha = good.a;
};

// Dependent Texture Read 피하기
// 나쁜 예: 의존적 읽기
half4 BadDependentRead(float2 uv)
{
    float2 offset = OffsetTex.Sample(samp, uv).rg;  // 첫 번째 읽기
    return MainTex.Sample(samp, uv + offset);       // 의존적 읽기 (스톨)
}

// 좋은 예: 버텍스에서 계산
// Vertex Shader
void VS(out float2 MainUV, out float2 OffsetUV)
{
    MainUV = ComputeMainUV();
    OffsetUV = ComputeOffsetUV();  // 미리 계산
}

// Mipmap 레벨 명시
half4 ExplicitLOD(float2 uv, float lod)
{
    // SampleLevel은 의존적 읽기를 피함
    return tex.SampleLevel(samp, uv, lod);
}
```

---

## 모바일 머티리얼 노드

### 비용이 높은 노드

```
┌─────────────────────────────────────────────────────────────────┐
│                  머티리얼 노드 비용                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  높은 비용 (피하기):                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Noise                    (복잡한 수학)               │   │
│  │ • Scene Color/Depth        (추가 텍스처 페치)          │   │
│  │ • Refraction               (Screen UV 재계산)          │   │
│  │ • Pixel Depth Offset       (Early-Z 무효화)            │   │
│  │ • World Position Offset    (추가 연산, VS에서)         │   │
│  │ • Tessellation             (미지원/비쌈)               │   │
│  │ • Custom UV (복잡한)       (Varying 증가)              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  중간 비용:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Fresnel                  (dot, pow)                  │   │
│  │ • Bump Offset              (추가 샘플링)                │   │
│  │ • Parallax                 (반복 샘플링)                │   │
│  │ • Normal Map               (언팩 연산)                  │   │
│  │ • Blend 노드들             (추가 연산)                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  낮은 비용 (권장):                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Texture Sample           (기본)                      │   │
│  │ • Constant                 (무료)                      │   │
│  │ • Add/Multiply/Lerp        (기본 ALU)                  │   │
│  │ • VertexColor              (무료 Varying)              │   │
│  │ • Mask (채널 선택)         (Swizzle, 무료)             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Fully Rough 최적화

```cpp
// Fully Rough 셰이딩 모델
// 스페큘러 계산 완전 제거

// 머티리얼 설정
UPROPERTY(EditAnywhere, Category = "Mobile")
bool bFullyRough = true;  // Roughness = 1.0 고정

// 셰이더 분기
#if MATERIAL_FULLY_ROUGH
    // 스페큘러 없음 - 디퓨즈만
    half3 Lighting = DiffuseColor * NoL * LightColor;
#else
    // 전체 BRDF 계산
    half3 Lighting = DefaultLitBRDF(DiffuseColor, SpecularColor,
                                    Roughness, NoL, NoV, NoH);
#endif

// 저장되는 연산:
// - 스페큘러 계산 전체
// - 환경 반사
// - Fresnel
// → 모바일에서 상당한 성능 향상
```

---

## 라이팅 모델

### Mobile Lit

```hlsl
// 모바일 최적화 라이팅
half3 MobileLit(
    half3 BaseColor,
    half3 Normal,
    half Roughness,
    half Metallic,
    half3 LightDir,
    half3 LightColor,
    half3 ViewDir)
{
    // 디퓨즈/스페큘러 분리
    half3 DiffuseColor = BaseColor * (1 - Metallic);
    half3 SpecularColor = lerp(0.04, BaseColor, Metallic);

    // Lambert 디퓨즈
    half NoL = saturate(dot(Normal, LightDir));
    half3 Diffuse = DiffuseColor * NoL;

    // 간소화된 스페큘러 (GGX 근사)
    half3 H = normalize(LightDir + ViewDir);
    half NoH = saturate(dot(Normal, H));

    // Roughness를 스페큘러 파워로 변환
    half SpecPower = exp2(10 * (1 - Roughness) + 1);
    half Spec = pow(NoH, SpecPower) * (SpecPower + 2) / 8;

    half3 Specular = SpecularColor * Spec * NoL;

    return (Diffuse + Specular) * LightColor;
}
```

### Unlit (최저 비용)

```hlsl
// Unlit 셰이더 - 최소 연산
half4 MobileUnlit(
    half4 BaseColor,
    half4 EmissiveColor)
{
    // 라이팅 계산 없음
    // 텍스처 + 이미시브만
    return BaseColor + EmissiveColor;
}

// 사용 사례:
// - UI 요소
// - 파티클
// - 스카이박스
// - 이미시브 오브젝트
// - 모바일에서 먼 배경
```

---

## 셰이더 배리언트

### 배리언트 최소화

```
┌─────────────────────────────────────────────────────────────────┐
│                  셰이더 배리언트 관리                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  문제: 배리언트 폭발                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  기본 셰이더 × 라이트 수 × 그림자 × 포그 × ...         │   │
│  │       1      ×    4     ×   2    ×  2   = 16 배리언트   │   │
│  │                                                          │   │
│  │  각 배리언트 = 컴파일 시간 + 메모리 + 로딩 시간         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  해결책:                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. 정적 스위치 최소화                                   │   │
│  │     • 불필요한 피처 비활성화                             │   │
│  │     • 플랫폼별 설정                                      │   │
│  │                                                          │   │
│  │  2. Project Settings → Shader Permutation Reduction     │   │
│  │     • r.Mobile.UseHQShadowMap=0                         │   │
│  │     • 사용하지 않는 라이트 타입 비활성화                  │   │
│  │                                                          │   │
│  │  3. 런타임 분기 (성능 트레이드오프)                      │   │
│  │     • 유니폼 기반 조건                                   │   │
│  │     • 컴파일 타임 vs 런타임 결정                         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 설정 예시

```cpp
// Project Settings → Rendering → Mobile Shader Permutation Reduction

// DefaultEngine.ini
[/Script/Engine.RendererSettings]
; 사용하지 않는 라이트 타입 비활성화
r.Mobile.EnableStaticAndCSMShadowReceivers=False
r.Mobile.EnableMovableLightCSMShaderCulling=False
r.Mobile.AllowDistanceFieldShadows=False
r.Mobile.AllowMovableDirectionalLights=False

; 포그 설정
r.Mobile.DisableVertexFog=True

; 반사 설정
r.Mobile.DisablePlanarReflection=True
```

---

## Compute Shader

### 모바일 Compute

```cpp
// ES 3.1 Compute Shader 제한
// - Work Group 크기: 최소 128 invocations
// - Shared Memory: 최소 16KB
// - 이미지 접근: 제한적

// 간단한 모바일 Compute Shader
[numthreads(8, 8, 1)]
void MobileComputeCS(
    uint3 GroupId : SV_GroupID,
    uint3 DispatchThreadId : SV_DispatchThreadID,
    uint3 GroupThreadId : SV_GroupThreadID)
{
    // 텍스처 읽기
    float4 Color = InputTexture[DispatchThreadId.xy];

    // 간단한 처리
    Color = ProcessColor(Color);

    // 결과 쓰기
    OutputTexture[DispatchThreadId.xy] = Color;
}

// 주의사항
// - 메모리 배리어 비용 높음
// - Atomic 연산 느림
// - 가능하면 Fragment Shader 선호
```

---

## 셰이더 디버깅

### 모바일 셰이더 프로파일링

```cpp
// 셰이더 복잡도 시각화
ShowFlag.ShaderComplexity 1

// GPU 인스트럭션 카운트
// Mali Offline Compiler
mali-asm-0.10.0 shader.frag -c Mali-G78

// Adreno 프로파일러
// Snapdragon Profiler에서 셰이더 분석

// 콘솔 명령어
r.Shaders.Optimize=1           // 셰이더 최적화 활성화
r.Shaders.KeepDebugInfo=0      // 디버그 정보 제거 (릴리즈)
r.ShaderPipelineCache.Enabled=1 // 파이프라인 캐시
```

### 일반적인 문제

```
┌─────────────────────────────────────────────────────────────────┐
│                  모바일 셰이더 문제 해결                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 정밀도 문제                                                  │
│     증상: 깜빡임, 밴딩, Z-fighting                              │
│     해결: Position, Depth는 반드시 float 사용                   │
│                                                                 │
│  2. 레지스터 스필                                                │
│     증상: 급격한 성능 저하                                      │
│     해결: 변수 수 줄이기, half 사용, 복잡도 감소               │
│                                                                 │
│  3. 텍스처 캐시 미스                                             │
│     증상: 느린 텍스처 샘플링                                    │
│     해결: 밉맵 사용, 의존적 읽기 제거, LOD 명시                 │
│                                                                 │
│  4. 분기 발산                                                    │
│     증상: SIMD 효율 저하                                        │
│     해결: 조건부 선택 사용, 분기 최소화                         │
│                                                                 │
│  5. 배리어 스톨                                                  │
│     증상: Compute Shader 병목                                   │
│     해결: 배리어 최소화, 작업 그룹 크기 조정                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 다음 단계

- [모바일 라이팅](03-mobile-lighting.md)에서 Forward 라이팅과 그림자를 학습합니다.
