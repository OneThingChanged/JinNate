# 스크린 스페이스 효과

SSAO, SSR, SSS 등 화면 공간 기반 포스트 이펙트를 분석합니다.

---

## 스크린 스페이스 기법 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                    스크린 스페이스 기법                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  장점:                                                          │
│  - 씬 복잡도와 무관한 일정한 비용                                │
│  - 동적 오브젝트에 자동 적용                                     │
│  - 구현이 비교적 간단                                           │
│                                                                 │
│  단점:                                                          │
│  - 화면 밖 정보 없음                                            │
│  - 깊이 불연속 문제                                             │
│  - 해상도 의존적                                                │
│                                                                 │
│  입력 데이터:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Scene Depth  │  Normal Buffer  │  Scene Color         │   │
│  │  (깊이 정보)   │  (노말 정보)     │  (컬러 정보)          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    스크린 스페이스 효과                   │   │
│  │                                                         │   │
│  │    SSAO        SSR         SSS         SSSSS           │   │
│  │  (앰비언트     (반사)     (산란)      (그림자)           │   │
│  │   오클루전)                                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## SSAO (Screen Space Ambient Occlusion)

### SSAO 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    Ambient Occlusion 개념                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  주변 환경에 의한 간접광 차폐:                                   │
│                                                                 │
│     ┌─────────────┐                                            │
│     │             │                                            │
│     │    ┌───┐    │  코너나 좁은 공간은                         │
│     │    │░░░│    │  간접광이 덜 도달                           │
│     │    └───┘    │                                            │
│     │      ▲      │                                            │
│     │   어두움    │                                             │
│     └─────────────┘                                            │
│                                                                 │
│  SSAO 샘플링:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │       반구 샘플링                                        │   │
│  │          ○ ○ ○                                          │   │
│  │         ○ ○ ○ ○                                         │   │
│  │        ●────────●  ← 표면                               │   │
│  │                                                         │   │
│  │  각 샘플이 지오메트리에 의해 가려지는지 테스트             │   │
│  │  가려진 비율 = 오클루전                                   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### SSAO 구현 (Crytek 방식)

```hlsl
// SSAO 셰이더 (기본)
float ComputeSSAO(float2 UV)
{
    // 현재 픽셀 정보
    float Depth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float3 Position = ReconstructPosition(UV, Depth);
    float3 Normal = NormalTexture.Sample(PointSampler, UV).rgb * 2.0 - 1.0;

    // 랜덤 회전 벡터 (노이즈 텍스처에서)
    float3 RandomVec = NoiseTexture.Sample(WrapSampler, UV * NoiseScale).rgb * 2.0 - 1.0;

    // 접선 공간 기저 생성
    float3 Tangent = normalize(RandomVec - Normal * dot(RandomVec, Normal));
    float3 Bitangent = cross(Normal, Tangent);
    float3x3 TBN = float3x3(Tangent, Bitangent, Normal);

    float Occlusion = 0;

    // 반구 샘플링
    for (int i = 0; i < NUM_SAMPLES; i++)
    {
        // 반구 내 샘플 방향
        float3 SampleDir = mul(HemisphereSamples[i], TBN);

        // 샘플 위치
        float3 SamplePos = Position + SampleDir * SampleRadius;

        // 스크린 공간으로 투영
        float4 ClipPos = mul(float4(SamplePos, 1), ViewProjection);
        float2 SampleUV = ClipPos.xy / ClipPos.w * 0.5 + 0.5;
        SampleUV.y = 1.0 - SampleUV.y;

        // 깊이 비교
        float SampleDepth = SceneDepthTexture.Sample(PointSampler, SampleUV).r;
        float SampleZ = LinearizeDepth(SampleDepth);
        float ExpectedZ = LinearizeDepth(ClipPos.z / ClipPos.w);

        // 오클루전 체크
        float RangeCheck = smoothstep(0, 1, SampleRadius / abs(SampleZ - ExpectedZ));
        Occlusion += (SampleZ < ExpectedZ - Bias) ? RangeCheck : 0.0;
    }

    Occlusion = 1.0 - (Occlusion / NUM_SAMPLES);
    return pow(Occlusion, Power);
}
```

### GTAO (Ground Truth Ambient Occlusion)

```hlsl
// GTAO - UE의 기본 SSAO 방식
float ComputeGTAO(float2 UV)
{
    float Depth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float3 Position = ReconstructPosition(UV, Depth);
    float3 ViewDir = normalize(-Position);
    float3 Normal = NormalTexture.Sample(PointSampler, UV).rgb * 2.0 - 1.0;

    float Visibility = 0;
    float TotalWeight = 0;

    // 여러 방향으로 슬라이스 샘플링
    for (int Slice = 0; Slice < NUM_SLICES; Slice++)
    {
        float SliceAngle = (float(Slice) / NUM_SLICES) * 3.14159;
        float2 SliceDir = float2(cos(SliceAngle), sin(SliceAngle));

        // 슬라이스 방향으로 레이마칭
        float MaxHorizonCos = -1.0;

        for (int Step = 1; Step <= NUM_STEPS; Step++)
        {
            float StepLength = float(Step) / NUM_STEPS * SampleRadius;
            float2 SampleUV = UV + SliceDir * StepLength * TexelSize;

            float SampleDepth = SceneDepthTexture.Sample(PointSampler, SampleUV).r;
            float3 SamplePos = ReconstructPosition(SampleUV, SampleDepth);

            // 호라이즌 각도 계산
            float3 HorizonVec = SamplePos - Position;
            float HorizonLength = length(HorizonVec);
            float3 HorizonDir = HorizonVec / HorizonLength;

            float HorizonCos = dot(HorizonDir, Normal);

            // 최대 호라이즌 업데이트
            MaxHorizonCos = max(MaxHorizonCos, HorizonCos);
        }

        // 가시성 계산
        float SinH = sqrt(1.0 - MaxHorizonCos * MaxHorizonCos);
        float CosN = dot(Normal, ViewDir);

        Visibility += CosN * 3.14159 - MaxHorizonCos * SinH - CosN * acos(MaxHorizonCos);
    }

    Visibility /= (NUM_SLICES * 3.14159);
    return saturate(Visibility);
}
```

### SSAO 블러

```hlsl
// 깊이 인식 블러 (엣지 보존)
float BlurSSAO(float2 UV)
{
    float CenterDepth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float CenterAO = SSAOTexture.Sample(PointSampler, UV).r;

    float Result = 0;
    float TotalWeight = 0;

    for (int y = -BLUR_RADIUS; y <= BLUR_RADIUS; y++)
    {
        for (int x = -BLUR_RADIUS; x <= BLUR_RADIUS; x++)
        {
            float2 SampleUV = UV + float2(x, y) * TexelSize;

            float SampleDepth = SceneDepthTexture.Sample(PointSampler, SampleUV).r;
            float SampleAO = SSAOTexture.Sample(PointSampler, SampleUV).r;

            // 깊이 차이에 따른 가중치
            float DepthDiff = abs(SampleDepth - CenterDepth);
            float DepthWeight = exp(-DepthDiff * DepthWeight);

            // 공간 가중치 (가우시안)
            float SpatialWeight = GaussianWeights[abs(x)][abs(y)];

            float Weight = DepthWeight * SpatialWeight;

            Result += SampleAO * Weight;
            TotalWeight += Weight;
        }
    }

    return Result / TotalWeight;
}
```

---

## SSR (Screen Space Reflections)

### SSR 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    Screen Space Reflections                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  레이마칭 기반 반사:                                             │
│                                                                 │
│     카메라 ●                                                    │
│            \                                                    │
│             \   뷰 레이                                         │
│              \                                                  │
│               ● 표면 히트                                       │
│              /                                                  │
│             /   반사 레이                                       │
│            /                                                    │
│           ●     깊이 버퍼와 교차하면 반사 색상 사용              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  Step 1: 반사 방향 계산                                  │   │
│  │  Step 2: 반사 방향으로 레이마칭                          │   │
│  │  Step 3: 깊이 버퍼와 교차 검사                           │   │
│  │  Step 4: 교차점의 색상 샘플링                            │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### SSR 레이마칭

```hlsl
// SSR 히트 찾기
struct FSSRHitResult
{
    bool bHit;
    float2 HitUV;
    float HitDepth;
};

FSSRHitResult TraceSSR(float3 Position, float3 ReflectDir)
{
    FSSRHitResult Result = (FSSRHitResult)0;

    // 스크린 공간에서 시작/끝점
    float4 StartClip = mul(float4(Position, 1), ViewProjection);
    float4 EndClip = mul(float4(Position + ReflectDir * MaxDistance, 1), ViewProjection);

    float2 StartUV = StartClip.xy / StartClip.w * 0.5 + 0.5;
    float2 EndUV = EndClip.xy / EndClip.w * 0.5 + 0.5;

    float2 RayDir = EndUV - StartUV;
    float RayLength = length(RayDir);
    RayDir = normalize(RayDir);

    // 히에라키컬 트레이싱 (HZB 사용)
    float CurrentMip = 0;
    float2 CurrentUV = StartUV;
    float CurrentDepth = StartClip.z / StartClip.w;

    for (int i = 0; i < MAX_ITERATIONS; i++)
    {
        // 현재 Mip에서 스텝 크기
        float StepSize = exp2(CurrentMip) * TexelSize;
        float2 NextUV = CurrentUV + RayDir * StepSize;

        // HZB에서 깊이 샘플
        float HZBDepth = HZBTexture.SampleLevel(PointSampler, NextUV, CurrentMip).r;

        // 레이 깊이 계산
        float T = length(NextUV - StartUV) / RayLength;
        float RayDepth = lerp(StartClip.z / StartClip.w, EndClip.z / EndClip.w, T);

        if (RayDepth > HZBDepth)
        {
            // 교차 가능성 있음
            if (CurrentMip == 0)
            {
                // 최하위 Mip - 정밀 테스트
                float DepthDiff = abs(RayDepth - HZBDepth);
                if (DepthDiff < DepthThreshold)
                {
                    Result.bHit = true;
                    Result.HitUV = NextUV;
                    Result.HitDepth = HZBDepth;
                    return Result;
                }
            }
            else
            {
                // 더 낮은 Mip으로 내려감
                CurrentMip = max(CurrentMip - 1, 0);
                continue;
            }
        }
        else
        {
            // 교차 없음 - 더 높은 Mip으로 올라감
            CurrentMip = min(CurrentMip + 1, MAX_MIP);
        }

        CurrentUV = NextUV;
    }

    return Result;
}
```

### SSR 품질 향상

```hlsl
// 러프니스 기반 콘 트레이싱
float4 TraceSSRWithRoughness(float2 UV, float Roughness)
{
    float3 Position = ReconstructPosition(UV, SceneDepth);
    float3 Normal = DecodeNormal(NormalTexture.Sample(PointSampler, UV));
    float3 ViewDir = normalize(-Position);
    float3 ReflectDir = reflect(-ViewDir, Normal);

    float4 Result = float4(0, 0, 0, 0);
    float TotalWeight = 0;

    // 러프니스에 따른 샘플 수
    int NumSamples = lerp(1, MAX_SAMPLES, Roughness);

    for (int i = 0; i < NumSamples; i++)
    {
        // GGX 중요도 샘플링
        float2 Xi = Hammersley(i, NumSamples);
        float3 H = ImportanceSampleGGX(Xi, Normal, Roughness);
        float3 SampleDir = reflect(-ViewDir, H);

        // 레이 트레이싱
        FSSRHitResult Hit = TraceSSR(Position, SampleDir);

        if (Hit.bHit)
        {
            float3 HitColor = SceneColorTexture.Sample(LinearSampler, Hit.HitUV).rgb;

            // BRDF 가중치
            float NoH = saturate(dot(Normal, H));
            float VoH = saturate(dot(ViewDir, H));
            float Weight = D_GGX(Roughness, NoH) * VoH / max(NoH, 0.001);

            Result.rgb += HitColor * Weight;
            TotalWeight += Weight;
        }
    }

    if (TotalWeight > 0)
    {
        Result.rgb /= TotalWeight;
        Result.a = 1.0;
    }

    return Result;
}
```

### SSR과 다른 반사 블렌딩

```hlsl
// SSR + 환경 반사 블렌딩
float4 CompositeReflections(float2 UV)
{
    float Roughness = RoughnessTexture.Sample(PointSampler, UV).r;

    // SSR 결과
    float4 SSR = SSRTexture.Sample(LinearSampler, UV);

    // 환경 반사 (큐브맵 또는 Lumen)
    float3 EnvReflection = SampleEnvironmentReflection(UV, Roughness);

    // SSR 신뢰도에 따른 블렌딩
    float SSRConfidence = SSR.a;

    // 화면 가장자리 페이드
    float2 EdgeFade = abs(UV - 0.5) * 2.0;
    float ScreenEdgeFade = 1.0 - max(EdgeFade.x, EdgeFade.y);
    ScreenEdgeFade = saturate(ScreenEdgeFade * 4.0);

    SSRConfidence *= ScreenEdgeFade;

    // 최종 블렌딩
    float3 FinalReflection = lerp(EnvReflection, SSR.rgb, SSRConfidence);

    return float4(FinalReflection, 1);
}
```

---

## SSS (Screen Space Subsurface Scattering)

### SSS 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    Subsurface Scattering                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  빛이 반투명 물질 내부에서 산란:                                  │
│                                                                 │
│        ☀ 입사광                                                 │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────────────┐                                       │
│  │ ░░░░░░░░░░░░░░░░░░░ │  ← 피부, 왁스, 대리석 등               │
│  │ ░░░↙░░░░░░░░░↘░░░░ │     빛이 내부에서 퍼짐                  │
│  │ ░↙░░░░░░░░░░░░░↘░░ │                                        │
│  │ ↙░░░░░░░░░░░░░░░░↘ │                                        │
│  └─────────────────────┘                                       │
│    ↑               ↑                                           │
│  출사광           출사광                                        │
│  (입사점과 다른 위치)                                           │
│                                                                 │
│  스크린 스페이스 근사:                                           │
│  - 화면에서 블러로 산란 효과 시뮬레이션                          │
│  - 깊이 인식 블러로 실루엣 보존                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Separable SSS

```hlsl
// Separable SSS (Jimenez et al.)
float4 SeparableSSSBlur(float2 UV, float2 BlurDir)
{
    // 커널 파라미터 (피부용)
    static const float Kernel[13] = {
        0.0560, 0.0670, 0.0780, 0.0890, 0.0990,
        0.1060, 0.1130,  // 중심
        0.1060, 0.0990, 0.0890, 0.0780, 0.0670, 0.0560
    };
    static const float Offsets[13] = {
        -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6
    };

    // 현재 픽셀 정보
    float4 CenterColor = SceneColorTexture.Sample(PointSampler, UV);
    float CenterDepth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float SSSRadius = GetSubsurfaceRadius(UV);

    // SSS가 적용되지 않는 머티리얼은 스킵
    if (SSSRadius <= 0)
    {
        return CenterColor;
    }

    float4 Result = float4(0, 0, 0, 0);
    float TotalWeight = 0;

    // 분리 가능 블러
    for (int i = 0; i < 13; i++)
    {
        float2 SampleUV = UV + BlurDir * Offsets[i] * SSSRadius;

        float4 SampleColor = SceneColorTexture.Sample(LinearSampler, SampleUV);
        float SampleDepth = SceneDepthTexture.Sample(PointSampler, SampleUV).r;

        // 깊이 가중치 (실루엣 보존)
        float DepthDiff = abs(SampleDepth - CenterDepth);
        float DepthWeight = exp(-DepthDiff * DepthFalloff);

        float Weight = Kernel[i] * DepthWeight;

        // 색상별 다른 산란 거리 (빨간색이 더 멀리)
        float3 ColorWeight = float3(
            Weight,
            Weight * 0.8,
            Weight * 0.6
        );

        Result.rgb += SampleColor.rgb * ColorWeight;
        TotalWeight += Weight;
    }

    Result.rgb /= TotalWeight;
    Result.a = CenterColor.a;

    return Result;
}
```

### SSS 프로파일

```cpp
// SSS 프로파일 (머티리얼별 산란 특성)
UCLASS()
class USubsurfaceProfile : public UObject
{
    // 산란 반경 (월드 단위)
    UPROPERTY()
    float ScatterRadius = 1.2f;

    // 서브서피스 컬러 (산란 시 색조)
    UPROPERTY()
    FLinearColor SubsurfaceColor = FLinearColor(0.48f, 0.41f, 0.28f);

    // 경계 색상 블리딩
    UPROPERTY()
    FLinearColor BoundaryColorBleed = FLinearColor(0.3f, 0.1f, 0.1f);

    // 전달 함수 (커스텀 커널)
    UPROPERTY()
    FLinearColor FalloffColor = FLinearColor(1.0f, 0.37f, 0.3f);
};
```

---

## 스크린 스페이스 그림자

### Contact Shadows

```hlsl
// 접촉 그림자 (근거리 디테일 그림자)
float ComputeContactShadow(float3 WorldPosition, float3 LightDirection)
{
    // 스크린 공간에서 레이마칭
    float4 StartClip = mul(float4(WorldPosition, 1), ViewProjection);
    float2 StartUV = StartClip.xy / StartClip.w * 0.5 + 0.5;

    float3 EndPosition = WorldPosition + LightDirection * ContactShadowLength;
    float4 EndClip = mul(float4(EndPosition, 1), ViewProjection);
    float2 EndUV = EndClip.xy / EndClip.w * 0.5 + 0.5;

    float2 RayDir = EndUV - StartUV;
    float RayLength = length(RayDir);
    int NumSteps = int(RayLength / TexelSize.x);

    float2 StepUV = RayDir / NumSteps;

    float Shadow = 1.0;

    for (int i = 1; i <= NumSteps; i++)
    {
        float2 SampleUV = StartUV + StepUV * i;

        // 레이 깊이
        float T = float(i) / NumSteps;
        float RayDepth = lerp(StartClip.z / StartClip.w, EndClip.z / EndClip.w, T);

        // 씬 깊이
        float SceneDepth = SceneDepthTexture.Sample(PointSampler, SampleUV).r;

        // 오클루전 체크
        if (RayDepth > SceneDepth + Bias)
        {
            float DepthDiff = RayDepth - SceneDepth;
            if (DepthDiff < Thickness)
            {
                Shadow = 0;
                break;
            }
        }
    }

    return Shadow;
}
```

---

## 성능 최적화

### 해상도 스케일링

```cpp
// 스크린 스페이스 효과 해상도
r.SSR.Quality=0-4            // SSR 품질
r.SSR.HalfResSceneColor=1    // 절반 해상도

r.AmbientOcclusionLevels=0-3 // SSAO 품질
r.SSAO.Downsample=1          // 다운샘플

r.SSS.Quality=0-1            // SSS 품질
r.SSS.HalfRes=1              // 절반 해상도
```

### 시간 분산

```cpp
// 프레임 간 작업 분산
class FTemporalDistribution
{
    // SSAO: 체커보드 렌더링
    void RenderSSAOTemporal(int FrameNumber)
    {
        // 프레임마다 다른 픽셀 처리
        int Pattern = FrameNumber % 4;
        // 0: (0,0), (1,1) / 1: (1,0), (0,1) / ...
    }

    // SSR: 확률적 레이 트레이싱
    void RenderSSRTemporal(int FrameNumber)
    {
        // 프레임마다 다른 샘플
        float BlueNoise = GetBlueNoise(PixelCoord, FrameNumber);
        // TAA로 누적
    }
};
```

---

## 요약

| 효과 | 원리 | 입력 데이터 | 비용 |
|------|------|------------|------|
| SSAO | 반구 오클루전 테스트 | Depth, Normal | 중간 |
| SSR | 깊이 버퍼 레이마칭 | Depth, Color | 높음 |
| SSS | 깊이 인식 블러 | Depth, Color | 중간 |
| Contact Shadow | 근거리 레이마칭 | Depth | 낮음 |

스크린 스페이스 기법은 동적 씬에서 효율적인 시각 효과를 제공합니다.
