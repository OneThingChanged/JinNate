# 템포럴 효과

Motion Blur, Depth of Field, TAA 등 시간 기반 포스트 이펙트를 분석합니다.

---

## 셰이딩 레이트와 템포럴 효과

템포럴 효과는 적응형 셰이딩과 함께 사용되어 품질과 성능을 최적화합니다.

![셰이딩 레이트 시각화](../images/ch07/1617944-20210505184710085-994097301.jpg)

*Shading Rate 시각화 - DOF나 Motion Blur 영역에서 셰이딩 레이트를 낮춰 성능 최적화 (파란색: 낮은 레이트, 녹색-빨간색: 높은 레이트)*

---

## 모션 블러 (Motion Blur)

### 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    모션 블러                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  실제 카메라에서:                                                │
│  - 셔터가 열린 동안 물체가 이동                                   │
│  - 이동 경로가 센서에 기록                                       │
│  - 셔터 스피드가 느릴수록 더 많은 블러                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │    프레임 시작      셔터 열림       프레임 끝            │   │
│  │         ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━●                   │   │
│  │                     ↑                                    │   │
│  │               이 구간이 블러됨                            │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  게임에서 구현:                                                  │
│  - 속도 버퍼 (Velocity Buffer) 사용                             │
│  - 속도 방향으로 샘플링                                          │
│  - 카메라 모션 + 오브젝트 모션                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 속도 버퍼

```cpp
// 속도 버퍼 생성
// G-Buffer 패스에서 함께 출력

struct FVelocityOutput
{
    float2 Velocity;  // 스크린 스페이스 속도
};

// 버텍스 셰이더에서 이전/현재 위치 계산
void VelocityVS(
    in float3 Position : POSITION,
    out float4 OutPosition : SV_POSITION,
    out float4 OutPrevPosition : TEXCOORD0,
    out float4 OutCurrPosition : TEXCOORD1)
{
    // 현재 프레임 위치
    OutCurrPosition = mul(float4(Position, 1), ViewProjection);
    OutPosition = OutCurrPosition;

    // 이전 프레임 위치
    float4 PrevWorldPos = mul(float4(Position, 1), PrevLocalToWorld);
    OutPrevPosition = mul(PrevWorldPos, PrevViewProjection);
}

// 픽셀 셰이더에서 속도 계산
float2 VelocityPS(
    float4 Position : SV_POSITION,
    float4 PrevPosition : TEXCOORD0,
    float4 CurrPosition : TEXCOORD1) : SV_Target
{
    // NDC 좌표 계산
    float2 CurrNDC = CurrPosition.xy / CurrPosition.w;
    float2 PrevNDC = PrevPosition.xy / PrevPosition.w;

    // 속도 = 현재 - 이전
    float2 Velocity = (CurrNDC - PrevNDC) * 0.5;

    // 최대 속도 클램핑
    float Speed = length(Velocity);
    if (Speed > MaxVelocity)
    {
        Velocity = Velocity / Speed * MaxVelocity;
    }

    return Velocity;
}
```

### 모션 블러 셰이더

```hlsl
// 퍼-픽셀 모션 블러
float4 MotionBlurPS(float2 UV : TEXCOORD0) : SV_Target
{
    // 현재 픽셀의 속도
    float2 Velocity = VelocityTexture.Sample(PointSampler, UV).xy;

    // 속도가 없으면 블러 없음
    float Speed = length(Velocity);
    if (Speed < MinVelocityThreshold)
    {
        return SceneColorTexture.Sample(LinearSampler, UV);
    }

    // 속도 방향 정규화
    float2 Direction = Velocity / Speed;

    // 블러 거리 (속도에 비례)
    float BlurDistance = min(Speed * MotionBlurScale, MaxBlurRadius);

    // 속도 방향으로 샘플링
    float3 Color = float3(0, 0, 0);
    float TotalWeight = 0;

    for (int i = 0; i < NUM_SAMPLES; i++)
    {
        float T = (float(i) / (NUM_SAMPLES - 1)) - 0.5;  // -0.5 ~ 0.5
        float2 SampleUV = UV + Direction * T * BlurDistance;

        // 속도 일관성 체크
        float2 SampleVelocity = VelocityTexture.Sample(PointSampler, SampleUV).xy;
        float VelocityDot = dot(normalize(SampleVelocity), Direction);

        // 비슷한 방향으로 움직이는 픽셀만 블러
        float Weight = saturate(VelocityDot);

        Color += SceneColorTexture.Sample(LinearSampler, SampleUV).rgb * Weight;
        TotalWeight += Weight;
    }

    return float4(Color / max(TotalWeight, 0.0001), 1);
}
```

### 카메라 모션 블러

```hlsl
// 카메라 전체 움직임에 의한 블러
float2 ComputeCameraVelocity(float2 UV, float Depth)
{
    // 현재 월드 위치 재구성
    float3 WorldPos = ReconstructWorldPosition(UV, Depth, InvViewProjection);

    // 이전 프레임에서의 스크린 위치
    float4 PrevClipPos = mul(float4(WorldPos, 1), PrevViewProjection);
    float2 PrevNDC = PrevClipPos.xy / PrevClipPos.w;
    float2 PrevUV = PrevNDC * 0.5 + 0.5;

    // 현재 위치와의 차이
    return UV - PrevUV;
}

// 오브젝트 모션 + 카메라 모션 결합
float2 GetCombinedVelocity(float2 UV, float Depth)
{
    // 오브젝트 속도 (Velocity Buffer에서)
    float2 ObjectVelocity = VelocityTexture.Sample(PointSampler, UV).xy;

    // 오브젝트 속도가 기록되지 않은 경우 (정적 지오메트리)
    if (ObjectVelocity.x == 0 && ObjectVelocity.y == 0)
    {
        // 카메라 모션만 사용
        return ComputeCameraVelocity(UV, Depth);
    }

    return ObjectVelocity;
}
```

---

## 피사계 심도 (Depth of Field)

### DOF 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    피사계 심도                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  카메라 렌즈 시스템:                                             │
│                                                                 │
│      근거리          초점면          원거리                      │
│   (Out of Focus)   (In Focus)    (Out of Focus)                │
│         │              │              │                         │
│    ●----│----◎---------●---------◎---│----●                    │
│         │              │              │                         │
│         └──────────────┼──────────────┘                         │
│                        │                                        │
│                   피사계 심도 범위                               │
│                                                                 │
│  Circle of Confusion (CoC):                                     │
│  - 초점이 맞지 않은 점이 맺히는 원의 크기                         │
│  - 조리개 (F-Stop)가 작을수록 CoC가 큼                           │
│  - 초점 거리에서 멀수록 CoC가 큼                                  │
│                                                                 │
│      ·      │      ●      │      ·                              │
│     CoC     │    초점     │    CoC                              │
│    (큼)     │   (최소)    │   (큼)                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Circle of Confusion 계산

```hlsl
// CoC (Circle of Confusion) 계산
float ComputeCoC(float SceneDepth, float FocalDistance, float FocalLength, float Aperture)
{
    // 물리 기반 CoC 공식
    // CoC = |S2 - S1| * A * f / (S1 * (S2 - f))
    // S1 = 초점 거리, S2 = 씬 깊이, A = 조리개 직경, f = 렌즈 초점 거리

    float S1 = FocalDistance;
    float S2 = SceneDepth;
    float f = FocalLength;
    float A = f / Aperture;  // Aperture = F-Stop

    float CoC = abs(S2 - S1) * A * f / (S1 * (S2 - f));

    // 최대 CoC 클램핑
    CoC = min(CoC, MaxCoCRadius);

    // 부호: 양수 = 후방 보케, 음수 = 전방 보케
    float Sign = (S2 > S1) ? 1.0 : -1.0;

    return CoC * Sign;
}

// 간단한 CoC 계산 (게임용)
float ComputeCoCSimple(float SceneDepth, float FocalDistance, float FocalRange)
{
    float Distance = abs(SceneDepth - FocalDistance);
    float CoC = saturate(Distance / FocalRange);

    float Sign = (SceneDepth > FocalDistance) ? 1.0 : -1.0;
    return CoC * Sign * MaxCoCRadius;
}
```

### 가우시안 DOF

```hlsl
// 가우시안 DOF (빠르지만 품질 낮음)
float4 GaussianDOFPS(float2 UV : TEXCOORD0) : SV_Target
{
    float Depth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float CoC = ComputeCoC(Depth, FocalDistance, FocalRange);

    // CoC 크기에 비례한 가우시안 블러
    float3 Color = float3(0, 0, 0);
    float TotalWeight = 0;

    int BlurRadius = int(abs(CoC) * BlurScale);

    for (int y = -BlurRadius; y <= BlurRadius; y++)
    {
        for (int x = -BlurRadius; x <= BlurRadius; x++)
        {
            float2 Offset = float2(x, y) * TexelSize;
            float2 SampleUV = UV + Offset;

            float SampleDepth = SceneDepthTexture.Sample(PointSampler, SampleUV).r;
            float SampleCoC = ComputeCoC(SampleDepth, FocalDistance, FocalRange);

            // 가우시안 가중치
            float Distance = length(float2(x, y));
            float Weight = exp(-Distance * Distance / (2.0 * abs(CoC) * abs(CoC)));

            // 깊이 기반 가중치 (전경이 배경을 가리지 않도록)
            if (SampleDepth < Depth && SampleCoC < 0)
            {
                Weight *= 0.1;  // 전경 블러가 배경에 영향 최소화
            }

            Color += SceneColorTexture.Sample(LinearSampler, SampleUV).rgb * Weight;
            TotalWeight += Weight;
        }
    }

    return float4(Color / TotalWeight, 1);
}
```

### 보케 DOF

```hlsl
// 보케 DOF (고품질)
float4 BokehDOFPS(float2 UV : TEXCOORD0) : SV_Target
{
    float Depth = SceneDepthTexture.Sample(PointSampler, UV).r;
    float CoC = ComputeCoC(Depth, FocalDistance, FocalRange);

    // 보케 형태 샘플링 (육각형, 원형 등)
    float3 Color = float3(0, 0, 0);
    float TotalWeight = 0;

    // 조리개 블레이드에 따른 보케 형태
    for (int i = 0; i < NUM_BOKEH_SAMPLES; i++)
    {
        // 보케 커널에서 샘플 위치
        float2 BokehOffset = BokehKernel[i] * abs(CoC);
        float2 SampleUV = UV + BokehOffset * TexelSize;

        float3 SampleColor = SceneColorTexture.Sample(LinearSampler, SampleUV).rgb;
        float SampleDepth = SceneDepthTexture.Sample(PointSampler, SampleUV).r;

        // 밝은 영역 강조 (실제 보케처럼)
        float Brightness = max(SampleColor.r, max(SampleColor.g, SampleColor.b));
        float BrightnessWeight = 1.0 + Brightness * BokehBrightness;

        // 깊이 가중치
        float DepthWeight = 1.0;
        if (SampleDepth < Depth)
        {
            // 전경 샘플
            DepthWeight = saturate(1.0 - (Depth - SampleDepth) / ForegroundFalloff);
        }

        float Weight = BrightnessWeight * DepthWeight;
        Color += SampleColor * Weight;
        TotalWeight += Weight;
    }

    return float4(Color / TotalWeight, 1);
}
```

### UE DOF 설정

```cpp
// DOF 파라미터
UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldFocalDistance = 0.0f;  // 초점 거리 (cm)

UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldFstop = 4.0f;  // F-Stop (조리개)

UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldSensorWidth = 24.576f;  // 센서 크기 (mm)

UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldFocalRegion = 0.0f;  // 선명한 영역 크기

UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldNearTransitionRegion = 300.0f;  // 근거리 전환 영역

UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldFarTransitionRegion = 500.0f;  // 원거리 전환 영역

// 보케 설정
UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldDepthBlurAmount = 1.0f;

UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
float DepthOfFieldDepthBlurRadius = 0.0f;

// 보케 형태
UPROPERTY(EditAnywhere, Category="Lens|Depth of Field")
UTexture* DepthOfFieldBokehShape;
```

---

## TAA (Temporal Anti-Aliasing)

### TAA 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    Temporal Anti-Aliasing                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  프레임 간 정보 누적:                                            │
│                                                                 │
│  Frame N-2    Frame N-1    Frame N                              │
│  ┌─────┐      ┌─────┐      ┌─────┐                              │
│  │ · · │      │· · ·│      │ ·· ·│                              │
│  │· · ·│  +   │ · · │  +   │· · ·│  =  더 부드러운 결과          │
│  │ · · │      │· · ·│      │ · · │                              │
│  └─────┘      └─────┘      └─────┘                              │
│                                                                 │
│  서브픽셀 지터링:                                                │
│  ┌───────────────────────┐                                      │
│  │ ┌─┐   프레임마다 다른  │                                      │
│  │ │●│   위치에서 샘플링  │                                      │
│  │ └─┘                   │                                      │
│  │   ●                   │   여러 프레임의 정보를 합쳐           │
│  │      ●                │   서브픽셀 디테일 재구성              │
│  │         ●             │                                      │
│  └───────────────────────┘                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### TAA 구현

```hlsl
// TAA 셰이더
float4 TemporalAAPS(float2 UV : TEXCOORD0) : SV_Target
{
    // 현재 프레임 컬러 (지터 적용됨)
    float3 CurrentColor = SceneColorTexture.Sample(PointSampler, UV).rgb;

    // 모션 벡터
    float2 Velocity = VelocityTexture.Sample(PointSampler, UV).xy;

    // 히스토리 위치
    float2 HistoryUV = UV - Velocity;

    // 히스토리 컬러 (바이큐빅 샘플링)
    float3 HistoryColor = SampleHistoryBicubic(HistoryUV);

    // 이웃 픽셀에서 컬러 범위 계산 (클램핑용)
    float3 NearMin, NearMax;
    ComputeNeighborhoodMinMax(UV, NearMin, NearMax);

    // 히스토리 클램핑 (고스팅 방지)
    HistoryColor = clamp(HistoryColor, NearMin, NearMax);

    // 블렌딩 가중치
    float BlendWeight = 0.9;  // 히스토리 90%, 현재 10%

    // 모션에 따른 가중치 조절
    float Speed = length(Velocity);
    if (Speed > MotionThreshold)
    {
        // 빠른 움직임에서는 현재 프레임 비중 증가
        BlendWeight = lerp(BlendWeight, 0.5, saturate(Speed / MaxMotion));
    }

    // 히스토리 유효성 체크
    if (HistoryUV.x < 0 || HistoryUV.x > 1 || HistoryUV.y < 0 || HistoryUV.y > 1)
    {
        // 화면 밖 → 현재 프레임만 사용
        BlendWeight = 0;
    }

    // 최종 블렌딩
    float3 Result = lerp(CurrentColor, HistoryColor, BlendWeight);

    return float4(Result, 1);
}

// 이웃 픽셀 범위 계산
void ComputeNeighborhoodMinMax(float2 UV, out float3 OutMin, out float3 OutMax)
{
    float3 Samples[9];
    int Index = 0;

    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            float2 SampleUV = UV + float2(x, y) * TexelSize;
            Samples[Index++] = SceneColorTexture.Sample(PointSampler, SampleUV).rgb;
        }
    }

    OutMin = min(min(Samples[0], Samples[1]), min(Samples[2], Samples[3]));
    OutMin = min(OutMin, min(min(Samples[4], Samples[5]), min(Samples[6], Samples[7])));
    OutMin = min(OutMin, Samples[8]);

    OutMax = max(max(Samples[0], Samples[1]), max(Samples[2], Samples[3]));
    OutMax = max(OutMax, max(max(Samples[4], Samples[5]), max(Samples[6], Samples[7])));
    OutMax = max(OutMax, Samples[8]);
}
```

### 지터 시퀀스

```cpp
// 할튼 시퀀스 (저불일치 시퀀스)
float2 GetHaltonJitter(int FrameIndex, int SampleCount)
{
    int Index = FrameIndex % SampleCount;

    // Halton(2) for X, Halton(3) for Y
    float X = HaltonSequence(Index, 2);
    float Y = HaltonSequence(Index, 3);

    // -0.5 ~ 0.5 범위로
    return float2(X - 0.5f, Y - 0.5f);
}

float HaltonSequence(int Index, int Base)
{
    float Result = 0;
    float F = 1.0f / Base;
    int I = Index;

    while (I > 0)
    {
        Result += F * (I % Base);
        I = I / Base;
        F = F / Base;
    }

    return Result;
}

// 프로젝션 매트릭스에 지터 적용
FMatrix ApplyTemporalJitter(const FMatrix& Projection, float2 Jitter, float2 ViewportSize)
{
    FMatrix JitteredProjection = Projection;

    // 픽셀 단위를 NDC 단위로 변환
    float2 JitterNDC = Jitter * 2.0f / ViewportSize;

    // 프로젝션 매트릭스의 [2][0], [2][1] 수정
    JitteredProjection.M[2][0] += JitterNDC.X;
    JitteredProjection.M[2][1] += JitterNDC.Y;

    return JitteredProjection;
}
```

---

## FXAA

### FXAA 개념

```hlsl
// FXAA (Fast Approximate Anti-Aliasing)
// 화면 공간에서 엣지 검출 후 블러

float4 FXAAPS(float2 UV : TEXCOORD0) : SV_Target
{
    // 휘도 샘플링
    float LumaM = Luminance(SceneColorTexture.Sample(LinearSampler, UV).rgb);
    float LumaS = Luminance(SceneColorTexture.Sample(LinearSampler, UV + float2(0, 1) * TexelSize).rgb);
    float LumaN = Luminance(SceneColorTexture.Sample(LinearSampler, UV + float2(0, -1) * TexelSize).rgb);
    float LumaE = Luminance(SceneColorTexture.Sample(LinearSampler, UV + float2(1, 0) * TexelSize).rgb);
    float LumaW = Luminance(SceneColorTexture.Sample(LinearSampler, UV + float2(-1, 0) * TexelSize).rgb);

    // 휘도 범위
    float LumaMin = min(LumaM, min(min(LumaS, LumaN), min(LumaE, LumaW)));
    float LumaMax = max(LumaM, max(max(LumaS, LumaN), max(LumaE, LumaW)));
    float LumaRange = LumaMax - LumaMin;

    // 범위가 작으면 AA 불필요
    if (LumaRange < max(FXAA_EDGE_THRESHOLD_MIN, LumaMax * FXAA_EDGE_THRESHOLD))
    {
        return SceneColorTexture.Sample(LinearSampler, UV);
    }

    // 엣지 방향 계산
    float2 Dir;
    Dir.x = -((LumaN + LumaS) - 2.0 * LumaM);
    Dir.y = ((LumaE + LumaW) - 2.0 * LumaM);

    float DirReduce = max((LumaN + LumaS + LumaE + LumaW) * 0.25 * FXAA_REDUCE_MUL, FXAA_REDUCE_MIN);
    float RcpDirMin = 1.0 / (min(abs(Dir.x), abs(Dir.y)) + DirReduce);
    Dir = min(float2(FXAA_SPAN_MAX, FXAA_SPAN_MAX),
              max(float2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), Dir * RcpDirMin)) * TexelSize;

    // 엣지 방향으로 블러
    float3 RgbA = 0.5 * (
        SceneColorTexture.Sample(LinearSampler, UV + Dir * (1.0/3.0 - 0.5)).rgb +
        SceneColorTexture.Sample(LinearSampler, UV + Dir * (2.0/3.0 - 0.5)).rgb);

    float3 RgbB = RgbA * 0.5 + 0.25 * (
        SceneColorTexture.Sample(LinearSampler, UV + Dir * -0.5).rgb +
        SceneColorTexture.Sample(LinearSampler, UV + Dir * 0.5).rgb);

    float LumaB = Luminance(RgbB);

    if (LumaB < LumaMin || LumaB > LumaMax)
    {
        return float4(RgbA, 1);
    }

    return float4(RgbB, 1);
}
```

---

## 성능 비교

```
┌────────────────────────────────────────────────────────────────┐
│                    AA 기법 비교                                 │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  기법        │ 품질  │ 성능  │ 모션 대응 │ 알파 엣지           │
│  ───────────┼───────┼───────┼──────────┼──────────            │
│  MSAA       │ ●●●○○ │ ●●○○○ │    ✗     │    ✓                 │
│  FXAA       │ ●●○○○ │ ●●●●● │    ✗     │    ✗                 │
│  SMAA       │ ●●●○○ │ ●●●●○ │    △     │    ✗                 │
│  TAA        │ ●●●●○ │ ●●●○○ │    ✓     │    ✓                 │
│  TSR        │ ●●●●● │ ●●●○○ │    ✓     │    ✓                 │
│                                                                │
│  ● = 상대적 점수 (높을수록 좋음)                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 요약

| 효과 | 원리 | 핵심 데이터 |
|------|------|------------|
| Motion Blur | 속도 방향 블러 | Velocity Buffer |
| DOF | CoC 기반 블러 | Scene Depth |
| TAA | 프레임 누적 | History Buffer |
| FXAA | 엣지 검출 블러 | Luminance |

템포럴 효과는 시간 정보를 활용하여 영화적 품질을 제공합니다.
---

<div style="display: flex; justify-content: space-between; align-items: center; padding: 16px 0;">
  <a href="../03-bloom-effects/" style="text-decoration: none;">← 이전: 03. 블룸과 광원 효과</a>
  <a href="../05-screen-space-effects/" style="text-decoration: none;">다음: 05. 스크린 스페이스 효과 →</a>
</div>
