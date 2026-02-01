# 셰이더 타입

버텍스, 픽셀, 컴퓨트 등 각 셰이더 스테이지의 역할과 구현을 분석합니다.

---

## 그래픽스 파이프라인 스테이지

```
┌─────────────────────────────────────────────────────────────────┐
│                    그래픽스 파이프라인                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Input Assembler                       │   │
│  │  버텍스/인덱스 버퍼에서 데이터 읽기                       │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Vertex Shader (VS) - 프로그래머블            │   │
│  │  버텍스 변환, 스키닝, 월드 좌표 계산                      │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Hull Shader (HS) - 선택적                    │   │
│  │  테셀레이션 인자 계산                                     │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Tessellator - 고정 기능                      │   │
│  │  프리미티브 분할                                          │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Domain Shader (DS) - 선택적                  │   │
│  │  분할된 버텍스 위치 계산                                  │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Geometry Shader (GS) - 선택적                │   │
│  │  프리미티브 생성/제거/수정                                │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Rasterizer - 고정 기능                       │   │
│  │  프리미티브 → 프래그먼트 변환                             │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Pixel Shader (PS) - 프로그래머블             │   │
│  │  픽셀 색상 계산, 라이팅, 텍스처링                         │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Output Merger - 고정 기능                    │   │
│  │  깊이/스텐실 테스트, 블렌딩, RenderTarget 출력            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Vertex Shader

### 역할

버텍스 셰이더는 각 정점에 대해 실행되며, 주로 좌표 변환을 담당합니다.

```hlsl
// 버텍스 셰이더 입력
struct FVertexInput
{
    float3 Position : POSITION;
    float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD0;
    float4 Color : COLOR;
};

// 버텍스 셰이더 출력
struct FVertexOutput
{
    float4 Position : SV_POSITION;  // 클립 공간 위치 (필수)
    float3 WorldPosition : TEXCOORD0;
    float3 WorldNormal : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
};

// 기본 버텍스 셰이더
FVertexOutput MainVS(FVertexInput Input)
{
    FVertexOutput Output;

    // 월드 변환
    float4 WorldPos = mul(float4(Input.Position, 1), LocalToWorld);
    Output.WorldPosition = WorldPos.xyz;

    // 클립 공간 변환
    Output.Position = mul(WorldPos, ViewProjection);

    // 노말 변환
    Output.WorldNormal = mul(Input.Normal, (float3x3)LocalToWorld);

    // UV 패스스루
    Output.TexCoord = Input.TexCoord;

    return Output;
}
```

### UE 버텍스 팩토리

```cpp
// FLocalVertexFactory - 스태틱 메시
class FLocalVertexFactory : public FVertexFactory
{
public:
    struct FDataType
    {
        FVertexStreamComponent PositionComponent;
        FVertexStreamComponent TangentBasisComponents[2];
        FVertexStreamComponent TextureCoordinates[MAX_TEXCOORDS];
        FVertexStreamComponent ColorComponent;
    };

    // 셰이더 파라미터
    static void ModifyCompilationEnvironment(const FVertexFactoryShaderPermutationParameters& Parameters,
                                              FShaderCompilerEnvironment& OutEnvironment)
    {
        OutEnvironment.SetDefine(TEXT("LOCAL_VERTEX_FACTORY"), 1);
    }
};

// FGPUSkinVertexFactory - 스켈레탈 메시
class FGPUSkinVertexFactory : public FVertexFactory
{
public:
    // 본 행렬 버퍼
    FShaderResourceViewRHIRef BoneBuffer;

    // GPU 스키닝
    static void ModifyCompilationEnvironment(...)
    {
        OutEnvironment.SetDefine(TEXT("GPUSKIN_VERTEX_FACTORY"), 1);
        OutEnvironment.SetDefine(TEXT("MAX_BONES_PER_VERTEX"), 4);
    }
};
```

### 스키닝 버텍스 셰이더

```hlsl
// GPU 스키닝
float3 SkinPosition(float3 Position, uint4 BlendIndices, float4 BlendWeights)
{
    float3 Result = float3(0, 0, 0);

    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float4x4 BoneMatrix = GetBoneMatrix(BlendIndices[i]);
        Result += mul(float4(Position, 1), BoneMatrix).xyz * BlendWeights[i];
    }

    return Result;
}

FVertexOutput SkinVS(FVertexInput Input)
{
    FVertexOutput Output;

    // 스킨드 위치
    float3 SkinnedPosition = SkinPosition(
        Input.Position,
        Input.BlendIndices,
        Input.BlendWeights);

    Output.WorldPosition = mul(float4(SkinnedPosition, 1), LocalToWorld).xyz;
    Output.Position = mul(float4(Output.WorldPosition, 1), ViewProjection);

    // 스킨드 노말
    float3 SkinnedNormal = SkinNormal(Input.Normal, Input.BlendIndices, Input.BlendWeights);
    Output.WorldNormal = normalize(mul(SkinnedNormal, (float3x3)LocalToWorld));

    return Output;
}
```

---

## Pixel Shader

### 역할

픽셀 셰이더는 래스터라이즈된 각 프래그먼트에 대해 실행되며, 최종 색상을 계산합니다.

```hlsl
// 픽셀 셰이더 - G-Buffer 출력
void GBufferPS(
    FVertexOutput Input,
    out float4 OutGBufferA : SV_Target0,
    out float4 OutGBufferB : SV_Target1,
    out float4 OutGBufferC : SV_Target2
)
{
    // 텍스처 샘플링
    float4 BaseColor = BaseColorTexture.Sample(LinearSampler, Input.TexCoord);
    float3 Normal = NormalTexture.Sample(LinearSampler, Input.TexCoord).xyz * 2 - 1;
    float Roughness = RoughnessTexture.Sample(LinearSampler, Input.TexCoord).r;
    float Metallic = MetallicTexture.Sample(LinearSampler, Input.TexCoord).r;

    // 월드 노말 계산
    float3 WorldNormal = normalize(Input.WorldNormal);
    float3 WorldTangent = normalize(Input.WorldTangent);
    float3 WorldBitangent = cross(WorldNormal, WorldTangent);
    float3x3 TBN = float3x3(WorldTangent, WorldBitangent, WorldNormal);
    float3 FinalNormal = normalize(mul(Normal, TBN));

    // G-Buffer 인코딩
    OutGBufferA = float4(FinalNormal * 0.5 + 0.5, 1);
    OutGBufferB = float4(Metallic, Roughness, 0, 0);
    OutGBufferC = float4(BaseColor.rgb, 1);
}
```

### 포워드 라이팅 픽셀 셰이더

```hlsl
// 포워드 라이팅 픽셀 셰이더
float4 ForwardLightingPS(FVertexOutput Input) : SV_Target
{
    // 머티리얼 속성
    float3 BaseColor = GetBaseColor(Input.TexCoord);
    float3 Normal = GetWorldNormal(Input);
    float Roughness = GetRoughness(Input.TexCoord);
    float Metallic = GetMetallic(Input.TexCoord);

    // 뷰 방향
    float3 ViewDir = normalize(CameraPosition - Input.WorldPosition);

    // 라이팅 누적
    float3 Lighting = float3(0, 0, 0);

    // 방향광
    {
        float3 L = -DirectionalLightDirection;
        float NoL = saturate(dot(Normal, L));

        float3 Diffuse = BaseColor * (1 - Metallic) / PI;
        float3 Specular = SpecularBRDF(Normal, ViewDir, L, Roughness, Metallic, BaseColor);

        Lighting += (Diffuse + Specular) * DirectionalLightColor * NoL;
    }

    // 포인트 라이트
    for (int i = 0; i < NumPointLights; i++)
    {
        FPointLight Light = PointLights[i];
        float3 L = normalize(Light.Position - Input.WorldPosition);
        float Distance = length(Light.Position - Input.WorldPosition);
        float Attenuation = 1.0 / (Distance * Distance);

        float NoL = saturate(dot(Normal, L));
        float3 Diffuse = BaseColor * (1 - Metallic) / PI;
        float3 Specular = SpecularBRDF(Normal, ViewDir, L, Roughness, Metallic, BaseColor);

        Lighting += (Diffuse + Specular) * Light.Color * Attenuation * NoL;
    }

    // 앰비언트
    Lighting += GetAmbient(Normal) * BaseColor;

    return float4(Lighting, 1);
}
```

---

## Compute Shader

### 역할

컴퓨트 셰이더는 범용 GPU 연산을 수행합니다. 그래픽스 파이프라인과 독립적으로 실행됩니다.

```hlsl
// 컴퓨트 셰이더 기본 구조
[numthreads(8, 8, 1)]  // 스레드 그룹 크기
void MainCS(
    uint3 GroupId : SV_GroupID,           // 그룹 ID
    uint3 GroupThreadId : SV_GroupThreadID, // 그룹 내 스레드 ID
    uint3 DispatchThreadId : SV_DispatchThreadID, // 전역 스레드 ID
    uint GroupIndex : SV_GroupIndex       // 그룹 내 1D 인덱스
)
{
    // 작업 수행
    uint2 PixelCoord = DispatchThreadId.xy;

    // 읽기
    float4 Color = InputTexture[PixelCoord];

    // 처리
    Color = ProcessColor(Color);

    // 쓰기
    OutputTexture[PixelCoord] = Color;
}
```

### UE 컴퓨트 셰이더 구현

```cpp
// C++ 컴퓨트 셰이더 정의
class FMyComputeShader : public FGlobalShader
{
    DECLARE_GLOBAL_SHADER(FMyComputeShader);
    SHADER_USE_PARAMETER_STRUCT(FMyComputeShader, FGlobalShader);

    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_RDG_TEXTURE(Texture2D, InputTexture)
        SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D<float4>, OutputTexture)
        SHADER_PARAMETER(FVector2f, TextureSize)
        SHADER_PARAMETER(float, Strength)
    END_SHADER_PARAMETER_STRUCT()

    static bool ShouldCompilePermutation(const FGlobalShaderPermutationParameters& Parameters)
    {
        return IsFeatureLevelSupported(Parameters.Platform, ERHIFeatureLevel::SM5);
    }
};

IMPLEMENT_GLOBAL_SHADER(FMyComputeShader, "/Project/MyComputeShader.usf", "MainCS", SF_Compute);

// 디스패치
void DispatchMyComputeShader(FRDGBuilder& GraphBuilder, FRDGTextureRef Input, FRDGTextureRef Output)
{
    FMyComputeShader::FParameters* Parameters = GraphBuilder.AllocParameters<FMyComputeShader::FParameters>();
    Parameters->InputTexture = Input;
    Parameters->OutputTexture = GraphBuilder.CreateUAV(Output);
    Parameters->TextureSize = FVector2f(Input->Desc.Extent.X, Input->Desc.Extent.Y);
    Parameters->Strength = 1.0f;

    TShaderMapRef<FMyComputeShader> ComputeShader(GetGlobalShaderMap(GMaxRHIFeatureLevel));

    FComputeShaderUtils::AddPass(
        GraphBuilder,
        RDG_EVENT_NAME("MyComputeShader"),
        ComputeShader,
        Parameters,
        FIntVector(
            FMath::DivideAndRoundUp(Input->Desc.Extent.X, 8),
            FMath::DivideAndRoundUp(Input->Desc.Extent.Y, 8),
            1));
}
```

### 공유 메모리 사용

```hlsl
// 그룹 공유 메모리
groupshared float SharedData[64][64];

[numthreads(8, 8, 1)]
void BlurCS(uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex)
{
    // 1. 데이터 로드 (확장된 영역)
    int2 LoadCoord = DTid.xy - 4;  // 블러 반경만큼 확장
    SharedData[GTid.y + 4][GTid.x + 4] = InputTexture[LoadCoord].r;

    // 가장자리 픽셀 로드
    if (GTid.x < 4)
        SharedData[GTid.y + 4][GTid.x] = InputTexture[LoadCoord - int2(4, 0)].r;
    if (GTid.x >= 4)
        SharedData[GTid.y + 4][GTid.x + 8] = InputTexture[LoadCoord + int2(4, 0)].r;
    // ... Y 방향도 동일

    // 2. 동기화 (모든 스레드가 로드 완료할 때까지 대기)
    GroupMemoryBarrierWithGroupSync();

    // 3. 공유 메모리에서 블러 계산
    float Sum = 0;
    [unroll]
    for (int y = -4; y <= 4; y++)
    {
        [unroll]
        for (int x = -4; x <= 4; x++)
        {
            float Weight = GaussianWeights[y + 4][x + 4];
            Sum += SharedData[GTid.y + 4 + y][GTid.x + 4 + x] * Weight;
        }
    }

    // 4. 출력
    OutputTexture[DTid.xy] = Sum;
}
```

---

## Geometry Shader

### 역할

지오메트리 셰이더는 프리미티브 단위로 동작하며, 새 정점을 생성하거나 제거할 수 있습니다.

```hlsl
// 지오메트리 셰이더 - 빌보드 생성
[maxvertexcount(4)]
void BillboardGS(
    point FVertexOutput Input[1],
    inout TriangleStream<FBillboardOutput> OutputStream)
{
    float3 Center = Input[0].WorldPosition;
    float Size = Input[0].Size;

    // 카메라를 향하는 쿼드 생성
    float3 Right = CameraRight * Size;
    float3 Up = CameraUp * Size;

    float3 Corners[4];
    Corners[0] = Center - Right - Up;
    Corners[1] = Center + Right - Up;
    Corners[2] = Center - Right + Up;
    Corners[3] = Center + Right + Up;

    float2 UVs[4] = { float2(0,1), float2(1,1), float2(0,0), float2(1,0) };

    [unroll]
    for (int i = 0; i < 4; i++)
    {
        FBillboardOutput Output;
        Output.Position = mul(float4(Corners[i], 1), ViewProjection);
        Output.TexCoord = UVs[i];
        Output.Color = Input[0].Color;
        OutputStream.Append(Output);
    }
}
```

### 주의사항

```
주의: 지오메트리 셰이더는 성능이 좋지 않습니다.

이유:
- 각 프리미티브마다 순차 실행
- 웨이브 효율 저하
- 메모리 대역폭 증가

대안:
- Mesh Shader (DX12/Vulkan)
- 컴퓨트 셰이더 + Indirect Draw
- 인스턴싱
```

---

## Hull/Domain Shader (테셀레이션)

### 헐 셰이더

```hlsl
// 헐 셰이더 - 테셀레이션 인자 계산
struct FHullConstantOutput
{
    float EdgeFactors[3] : SV_TessFactor;
    float InsideFactor : SV_InsideTessFactor;
};

FHullConstantOutput HullConstantFunc(InputPatch<FVertexOutput, 3> Patch)
{
    FHullConstantOutput Output;

    // 거리 기반 테셀레이션
    float3 Center = (Patch[0].WorldPosition + Patch[1].WorldPosition + Patch[2].WorldPosition) / 3;
    float Distance = length(Center - CameraPosition);
    float Factor = clamp(MaxTessDistance / Distance, 1, MaxTessFactor);

    Output.EdgeFactors[0] = Factor;
    Output.EdgeFactors[1] = Factor;
    Output.EdgeFactors[2] = Factor;
    Output.InsideFactor = Factor;

    return Output;
}

[domain("tri")]
[partitioning("fractional_odd")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[patchconstantfunc("HullConstantFunc")]
FVertexOutput MainHS(
    InputPatch<FVertexOutput, 3> Patch,
    uint PointId : SV_OutputControlPointID)
{
    return Patch[PointId];
}
```

### 도메인 셰이더

```hlsl
// 도메인 셰이더 - 분할된 정점 위치 계산
[domain("tri")]
FVertexOutput MainDS(
    FHullConstantOutput Constants,
    float3 BaryCoords : SV_DomainLocation,
    const OutputPatch<FVertexOutput, 3> Patch)
{
    FVertexOutput Output;

    // Barycentric 보간
    float3 WorldPos = BaryCoords.x * Patch[0].WorldPosition
                    + BaryCoords.y * Patch[1].WorldPosition
                    + BaryCoords.z * Patch[2].WorldPosition;

    float3 Normal = normalize(
        BaryCoords.x * Patch[0].WorldNormal
      + BaryCoords.y * Patch[1].WorldNormal
      + BaryCoords.z * Patch[2].WorldNormal);

    // 디스플레이스먼트 맵핑
    float2 UV = BaryCoords.x * Patch[0].TexCoord
              + BaryCoords.y * Patch[1].TexCoord
              + BaryCoords.z * Patch[2].TexCoord;

    float Displacement = DisplacementMap.SampleLevel(LinearSampler, UV, 0).r;
    WorldPos += Normal * Displacement * DisplacementScale;

    Output.WorldPosition = WorldPos;
    Output.WorldNormal = Normal;
    Output.TexCoord = UV;
    Output.Position = mul(float4(WorldPos, 1), ViewProjection);

    return Output;
}
```

---

## Ray Tracing Shaders (DXR)

### 셰이더 타입

```hlsl
// Ray Generation Shader - 레이 생성
[shader("raygeneration")]
void RayGenShader()
{
    uint2 PixelCoord = DispatchRaysIndex().xy;
    float2 UV = (PixelCoord + 0.5) / DispatchRaysDimensions().xy;

    // 카메라 레이 생성
    RayDesc Ray;
    Ray.Origin = CameraPosition;
    Ray.Direction = GetRayDirection(UV);
    Ray.TMin = 0.001;
    Ray.TMax = 10000;

    FRayPayload Payload = (FRayPayload)0;

    TraceRay(TLAS, RAY_FLAG_NONE, 0xFF, 0, 0, 0, Ray, Payload);

    OutputTexture[PixelCoord] = float4(Payload.Color, 1);
}

// Closest Hit Shader - 가장 가까운 교차점
[shader("closesthit")]
void ClosestHitShader(inout FRayPayload Payload, FHitAttributes Attrs)
{
    // 히트 정보
    float3 WorldPos = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    float3 Normal = GetHitNormal(Attrs);

    // 라이팅 계산
    Payload.Color = CalculateLighting(WorldPos, Normal);
}

// Miss Shader - 교차 없음
[shader("miss")]
void MissShader(inout FRayPayload Payload)
{
    Payload.Color = SampleSkybox(WorldRayDirection());
}
```

---

## 요약

| 셰이더 타입 | 역할 | 입력 | 출력 |
|------------|------|------|------|
| Vertex | 정점 변환 | 정점 데이터 | 변환된 정점 |
| Pixel | 픽셀 색상 | 보간된 데이터 | 색상, 깊이 |
| Compute | 범용 연산 | 버퍼/텍스처 | 버퍼/텍스처 |
| Geometry | 프리미티브 생성 | 프리미티브 | 프리미티브들 |
| Hull/Domain | 테셀레이션 | 패치 | 분할된 정점 |
| Ray Tracing | 광선 추적 | 광선 | 교차 결과 |

각 셰이더 타입은 그래픽스 파이프라인에서 고유한 역할을 담당합니다.
