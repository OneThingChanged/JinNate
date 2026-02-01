# 03. 머티리얼 컴파일

머티리얼 컴파일 과정, HLSL 생성, 머티리얼 템플릿 시스템을 분석합니다.

---

## 컴파일 개요

### 컴파일 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 컴파일 파이프라인                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 노드 그래프                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  UMaterial::Expressions[]                            │    │
│     │  각 표현식 노드들의 연결 정보                         │    │
│     └────────────────────────┬────────────────────────────┘    │
│                              │                                  │
│  2. 컴파일 시작               ▼                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  FMaterialCompiler::Compile()                        │    │
│     │  - 출력 핀부터 역방향으로 노드 순회                   │    │
│     │  - 각 노드의 Compile() 호출                          │    │
│     └────────────────────────┬────────────────────────────┘    │
│                              │                                  │
│  3. HLSL 코드 조각 생성       ▼                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  float3 Local0 = Texture.Sample(UV);                 │    │
│     │  float Local1 = Local0.r * Param;                    │    │
│     │  PixelMaterialInputs.BaseColor = Local1;             │    │
│     └────────────────────────┬────────────────────────────┘    │
│                              │                                  │
│  4. 템플릿에 삽입             ▼                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  MaterialTemplate.usf 에 생성된 코드 삽입            │    │
│     │  → 완전한 셰이더 소스                                │    │
│     └────────────────────────┬────────────────────────────┘    │
│                              │                                  │
│  5. 패스별 셰이더 컴파일       ▼                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  BasePassPS, DepthOnlyPS, ShadowDepthPS, ...         │    │
│     │  각 렌더 패스별로 셰이더 컴파일                       │    │
│     └────────────────────────┬────────────────────────────┘    │
│                              │                                  │
│  6. 셰이더 맵 저장             ▼                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  FMaterialShaderMap에 컴파일된 셰이더들 저장          │    │
│     │  캐싱, DDC 저장                                       │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컴파일러 클래스

```cpp
// 머티리얼 컴파일러 인터페이스
class FMaterialCompiler
{
public:
    // 상수 생성
    virtual int32 Constant(float X) = 0;
    virtual int32 Constant2(float X, float Y) = 0;
    virtual int32 Constant3(float X, float Y, float Z) = 0;
    virtual int32 Constant4(float X, float Y, float Z, float W) = 0;

    // 수학 연산
    virtual int32 Add(int32 A, int32 B) = 0;
    virtual int32 Sub(int32 A, int32 B) = 0;
    virtual int32 Mul(int32 A, int32 B) = 0;
    virtual int32 Div(int32 A, int32 B) = 0;
    virtual int32 Dot(int32 A, int32 B) = 0;
    virtual int32 Cross(int32 A, int32 B) = 0;
    virtual int32 Lerp(int32 A, int32 B, int32 Alpha) = 0;

    // 텍스처
    virtual int32 TextureSample(int32 TextureIndex, int32 CoordinateIndex, ...) = 0;
    virtual int32 TextureCoordinate(uint32 CoordinateIndex, ...) = 0;

    // 파라미터
    virtual int32 ScalarParameter(FName ParameterName, float DefaultValue) = 0;
    virtual int32 VectorParameter(FName ParameterName, FLinearColor DefaultValue) = 0;

    // 월드 데이터
    virtual int32 WorldPosition(EWorldPositionIncludedOffsets Offset) = 0;
    virtual int32 PixelNormalWS() = 0;
    virtual int32 CameraVector() = 0;

    // 코드 생성
    virtual int32 CustomExpression(UMaterialExpressionCustom* Custom, ...) = 0;
};

// HLSL 컴파일러 구현
class FHLSLMaterialTranslator : public FMaterialCompiler
{
    // 생성된 코드 저장
    FString ResourcesString;      // 리소스 선언
    FString MaterialTemplate;     // 머티리얼 코드

    // 심볼 테이블
    TMap<int32, FString> CodeChunks;  // 인덱스 → 코드 조각

    // 현재 컴파일 중인 프로퍼티
    EMaterialProperty CurrentProperty;

    virtual int32 Add(int32 A, int32 B) override
    {
        // 새 로컬 변수 생성
        FString Code = FString::Printf(TEXT("(%s + %s)"),
            *GetCodeChunk(A), *GetCodeChunk(B));

        return AddCodeChunk(MCT_Float, Code);
    }

    int32 AddCodeChunk(EMaterialValueType Type, const FString& Code)
    {
        int32 Index = NextIndex++;
        CodeChunks.Add(Index, Code);
        return Index;
    }
};
```

---

## 머티리얼 템플릿

### MaterialTemplate.usf 구조

```hlsl
// MaterialTemplate.usf (단순화된 구조)

// 생성된 유니폼 선언
// %UNIFORM_DECLARATIONS%
Texture2D Material_Texture2D_0;
SamplerState Material_Texture2D_0Sampler;
float4 Material_VectorParameter_0;
float Material_ScalarParameter_0;

// 생성된 함수들
// %MATERIAL_FUNCTIONS%

// 머티리얼 픽셀 파라미터 계산
void CalcPixelMaterialInputs(
    in FMaterialPixelParameters Parameters,
    inout FPixelMaterialInputs PixelMaterialInputs)
{
    // 생성된 코드
    // %PIXEL_MATERIAL_INPUTS%

    float4 Local0 = Material_Texture2D_0.Sample(
        Material_Texture2D_0Sampler,
        Parameters.TexCoords[0]);

    float3 Local1 = Local0.rgb * Material_VectorParameter_0.rgb;

    float Local2 = Material_ScalarParameter_0;

    // 출력 핀에 연결
    PixelMaterialInputs.BaseColor = Local1;
    PixelMaterialInputs.Metallic = 0;
    PixelMaterialInputs.Specular = 0.5;
    PixelMaterialInputs.Roughness = Local2;
    PixelMaterialInputs.Normal = float3(0, 0, 1);
    PixelMaterialInputs.EmissiveColor = 0;
    PixelMaterialInputs.Opacity = 1;
    PixelMaterialInputs.OpacityMask = 1;
}

// 버텍스 오프셋 계산
float3 GetMaterialWorldPositionOffset(
    FMaterialVertexParameters Parameters)
{
    // %WORLD_POSITION_OFFSET%
    return float3(0, 0, 0);
}
```

### 코드 생성 예시

```
┌─────────────────────────────────────────────────────────────────┐
│                    노드 그래프 → HLSL                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  노드 그래프:                                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  [TextureSample] ──→ [Multiply] ──→ [BaseColor]          │  │
│  │       ↑                  ↑                                │  │
│  │  [TexCoord]         [Constant: 0.5]                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  생성된 HLSL:                                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  // Local0: TextureCoordinate                            │  │
│  │  float2 Local0 = Parameters.TexCoords[0].xy;             │  │
│  │                                                          │  │
│  │  // Local1: TextureSample                                │  │
│  │  float4 Local1 = Material_Texture2D_0.Sample(            │  │
│  │      Material_Texture2D_0Sampler, Local0);               │  │
│  │                                                          │  │
│  │  // Local2: Constant                                     │  │
│  │  float Local2 = 0.5;                                     │  │
│  │                                                          │  │
│  │  // Local3: Multiply                                     │  │
│  │  float3 Local3 = Local1.rgb * Local2;                    │  │
│  │                                                          │  │
│  │  // 출력 연결                                             │  │
│  │  PixelMaterialInputs.BaseColor = Local3;                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 유니폼 표현식

### 정적 vs 동적 파라미터

```
┌─────────────────────────────────────────────────────────────────┐
│                    유니폼 표현식 타입                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  정적 표현식 (Static):                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 컴파일 시점에 값이 결정                               │   │
│  │  - 셰이더 바이너리에 상수로 포함                         │   │
│  │  - 변경 시 재컴파일 필요                                 │   │
│  │  예: Constant, Static Bool, Static Component Mask       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  동적 유니폼 (Dynamic Uniform):                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 런타임에 값 변경 가능                                 │   │
│  │  - Uniform Buffer에 저장                                 │   │
│  │  - 재컴파일 없이 업데이트                                │   │
│  │  예: Scalar/Vector Parameter, Time                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  텍스처:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 텍스처 파라미터는 동적                                │   │
│  │  - 머티리얼 인스턴스에서 교체 가능                       │   │
│  │  - 샘플러 상태도 파라미터화 가능                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 유니폼 버퍼 생성

```cpp
// 머티리얼 유니폼 표현식
class FUniformExpressionSet
{
    // 스칼라 파라미터
    TArray<FMaterialScalarParameterInfo> UniformScalarExpressions;

    // 벡터 파라미터
    TArray<FMaterialVectorParameterInfo> UniformVectorExpressions;

    // 텍스처 파라미터
    TArray<FMaterialTextureParameterInfo> UniformTextureExpressions;

    // 유니폼 버퍼 레이아웃
    FShaderParametersMetadata* UniformBufferLayout;

    // 유니폼 버퍼 생성
    TUniformBufferRef<FMaterialUniformShaderParameters> CreateUniformBuffer(
        const FMaterialRenderProxy* MaterialProxy,
        const UMaterial* Material,
        const FUniformExpressionCache& ExpressionCache)
    {
        FMaterialUniformShaderParameters Parameters;

        // 스칼라 파라미터 채우기
        for (const auto& Scalar : UniformScalarExpressions)
        {
            float Value;
            MaterialProxy->GetScalarValue(Scalar.ParameterInfo, &Value, Context);
            Parameters.ScalarExpressions[Scalar.Index] = Value;
        }

        // 벡터 파라미터 채우기
        for (const auto& Vector : UniformVectorExpressions)
        {
            FLinearColor Value;
            MaterialProxy->GetVectorValue(Vector.ParameterInfo, &Value, Context);
            Parameters.VectorExpressions[Vector.Index] = Value;
        }

        return CreateUniformBufferImmediate(Parameters, UniformBuffer_SingleFrame);
    }
};
```

---

## 패스별 컴파일

### 셰이더 타입별 컴파일

```
┌─────────────────────────────────────────────────────────────────┐
│                    패스별 셰이더 생성                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  하나의 머티리얼 → 여러 셰이더:                                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UMaterial                                              │   │
│  │      │                                                  │   │
│  │      ├── BasePass                                       │   │
│  │      │   ├── TBasePassVS<LightMapPolicy>               │   │
│  │      │   └── TBasePassPS<LightMapPolicy>               │   │
│  │      │                                                  │   │
│  │      ├── Depth Pass                                     │   │
│  │      │   ├── TDepthOnlyVS                              │   │
│  │      │   └── TDepthOnlyPS (Masked만)                   │   │
│  │      │                                                  │   │
│  │      ├── Shadow Depth                                   │   │
│  │      │   ├── TShadowDepthVS                            │   │
│  │      │   └── TShadowDepthPS (Masked만)                 │   │
│  │      │                                                  │   │
│  │      ├── Velocity Pass                                  │   │
│  │      │   └── FVelocityPS                               │   │
│  │      │                                                  │   │
│  │      └── Custom Passes...                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  × VertexFactory 조합:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - FLocalVertexFactory (Static Mesh)                    │   │
│  │  - FGPUSkinVertexFactory (Skeletal Mesh)               │   │
│  │  - FLandscapeVertexFactory (Landscape)                 │   │
│  │  - FParticleVertexFactory (Particles)                  │   │
│  │  = 수십~수백 개의 셰이더 순열                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 셰이더 맵 구조

```cpp
// 머티리얼 셰이더 맵
class FMaterialShaderMap : public FShaderMapBase
{
    // 셰이더 맵 ID
    FMaterialShaderMapId ShaderMapId;

    // 머티리얼 타입별 셰이더
    TMap<FShaderType*, FShader*> Shaders;

    // 버텍스 팩토리별 메시 셰이더 맵
    TMap<FVertexFactoryType*, FMeshMaterialShaderMap*> MeshShaderMaps;

    // 플랫폼
    EShaderPlatform Platform;

public:
    // 셰이더 검색
    FShader* GetShader(FShaderType* ShaderType) const
    {
        FShader* const* Found = Shaders.Find(ShaderType);
        return Found ? *Found : nullptr;
    }

    // 메시 셰이더 검색
    FShader* GetShader(FShaderType* ShaderType, FVertexFactoryType* VFType) const
    {
        FMeshMaterialShaderMap* const* MeshMap = MeshShaderMaps.Find(VFType);
        if (MeshMap)
        {
            return (*MeshMap)->GetShader(ShaderType);
        }
        return nullptr;
    }
};
```

---

## 정적 분기

### Static Switch Parameter

```cpp
// 정적 스위치 파라미터
class UMaterialExpressionStaticSwitchParameter : public UMaterialExpressionStaticBoolParameter
{
    UPROPERTY()
    FExpressionInput A;  // true일 때

    UPROPERTY()
    FExpressionInput B;  // false일 때

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        bool bValue = DefaultValue;

        // 정적 값 확인
        if (/* 머티리얼 인스턴스에서 오버라이드 */)
        {
            bValue = OverrideValue;
        }

        // 조건에 따라 한쪽만 컴파일
        if (bValue)
        {
            return A.Compile(Compiler);
        }
        else
        {
            return B.Compile(Compiler);
        }
    }
};
```

### 정적 분기 효과

```
┌─────────────────────────────────────────────────────────────────┐
│                    정적 분기 vs 동적 분기                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  동적 분기 (if문):                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  if (UseNormalMap)                                      │   │
│  │  {                                                      │   │
│  │      Normal = SampleNormalMap(UV);                      │   │
│  │  }                                                      │   │
│  │  else                                                   │   │
│  │  {                                                      │   │
│  │      Normal = VertexNormal;                             │   │
│  │  }                                                      │   │
│  │                                                         │   │
│  │  문제: GPU에서 양쪽 모두 실행 가능 (divergence)          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  정적 분기 (Static Switch):                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  // UseNormalMap = true인 머티리얼                       │   │
│  │  Normal = SampleNormalMap(UV);                          │   │
│  │                                                         │   │
│  │  // UseNormalMap = false인 머티리얼 (별도 셰이더)        │   │
│  │  Normal = VertexNormal;                                 │   │
│  │                                                         │   │
│  │  장점: 불필요한 코드 완전 제거                           │   │
│  │  단점: 셰이더 순열 증가                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 컴파일 최적화

### 컴파일 캐싱

```cpp
// DDC (Derived Data Cache) 활용
class FMaterialShaderMapDDC
{
    static FString GetDerivedDataKey(const FMaterialShaderMapId& Id)
    {
        // 머티리얼 해시 + 플랫폼 + 셰이더 버전
        return FDerivedDataCacheInterface::BuildCacheKey(
            TEXT("MaterialShaderMap"),
            MATERIALSHADERMAP_DERIVEDDATA_VER,
            Id.GetHash()
        );
    }

    static bool GetFromDDC(const FMaterialShaderMapId& Id, FMaterialShaderMap*& OutShaderMap)
    {
        FString Key = GetDerivedDataKey(Id);

        TArray<uint8> Data;
        if (GetDerivedDataCacheRef().GetSynchronous(*Key, Data))
        {
            FMemoryReader Ar(Data, true);
            OutShaderMap = new FMaterialShaderMap();
            OutShaderMap->Serialize(Ar);
            return true;
        }
        return false;
    }
};
```

### 병렬 컴파일

```
┌─────────────────────────────────────────────────────────────────┐
│                    병렬 셰이더 컴파일                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Main Thread                                             │  │
│  │  ├── 머티리얼 컴파일 요청                                 │  │
│  │  ├── 컴파일 작업 큐에 추가                                │  │
│  │  └── (다른 작업 계속)                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Shader Compiler Worker (다중 인스턴스)                   │  │
│  │  ├── Worker 1: BasePass VS 컴파일                        │  │
│  │  ├── Worker 2: BasePass PS 컴파일                        │  │
│  │  ├── Worker 3: DepthOnly PS 컴파일                       │  │
│  │  └── Worker 4: Shadow PS 컴파일                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ShaderCompileWorker.exe (별도 프로세스):                       │
│  - 멀티 코어 활용                                              │
│  - 크래시 격리                                                 │
│  - 에디터 응답성 유지                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 요약

머티리얼 컴파일 핵심:

1. **컴파일 흐름** - 노드 순회 → HLSL 생성 → 템플릿 삽입 → 셰이더 컴파일
2. **템플릿 시스템** - MaterialTemplate.usf에 생성 코드 삽입
3. **유니폼 표현식** - 정적(컴파일 타임) vs 동적(런타임) 파라미터
4. **패스별 셰이더** - BasePass, DepthPass, ShadowPass 등 각각 컴파일
5. **최적화** - DDC 캐싱, 병렬 컴파일, 정적 분기

컴파일된 셰이더는 FMaterialShaderMap에 저장되어 렌더링에 사용됩니다.

---

## 참고 자료

- [UE Material Compilation](https://docs.unrealengine.com/5.0/en-US/how-to-compile-materials-in-unreal-engine/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
