# 04. 머티리얼 컴파일

> 원문: [剖析虚幻渲染体系（09）- 材质体系](https://www.cnblogs.com/timlly/p/15109132.html)

UMaterialExpression, FHLSLMaterialTranslator, 머티리얼 컴파일 흐름을 상세히 분석합니다.

---

## 9.4 머티리얼 컴파일

머티리얼 컴파일은 머티리얼 에디터의 노드 그래프를 HLSL 셰이더 코드로 변환하는 과정입니다.

![머티리얼 컴파일 개요](../images/ch10/1617944-20210806160612858-228220747.jpg)

### 9.4.1 컴파일 컴포넌트 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 컴파일 컴포넌트                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UMaterialExpression (약 200개 서브클래스)                       │
│      │                                                          │
│      └── 각 머티리얼 노드의 기본 클래스                          │
│          Compile() 메서드로 HLSL 코드 조각 생성                  │
│          입력/출력 핀, 에디터 위치 정보 포함                     │
│                                                                 │
│  UMaterialGraphNode                                             │
│      │                                                          │
│      └── 에디터에서 생성되는 그래프 노드                         │
│          UEdGraphNode (UI) + UMaterialExpression (연산) 분리     │
│                                                                 │
│  UMaterialGraph                                                 │
│      │                                                          │
│      └── 전체 노드 그래프 컨테이너                               │
│          머티리얼 노드 배열, 연결 정보 관리                      │
│                                                                 │
│  FMaterialCompiler (인터페이스)                                  │
│      │                                                          │
│      └── 머티리얼 표현식을 셰이더 코드로 변환하는 추상 인터페이스│
│                                                                 │
│  FHLSLMaterialTranslator                                        │
│      │                                                          │
│      └── FMaterialCompiler 구현체                               │
│          노드 그래프를 HLSL 코드로 변환                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.4.2 UMaterialExpression

`UMaterialExpression`은 약 200개의 서브클래스를 가진 머티리얼 노드의 기반 클래스입니다.

![UMaterialExpression 계층](../images/ch10/1617944-20210806160621921-1750895487.jpg)

```cpp
// Engine/Source/Runtime/Engine/Classes/Materials/MaterialExpression.h

UCLASS(abstract, hidecategories=Object)
class UMaterialExpression : public UObject
{
    GENERATED_UCLASS_BODY()

    // 소속 머티리얼
    UPROPERTY()
    UMaterial* Material;

    // 소속 머티리얼 함수
    UPROPERTY()
    UMaterialFunction* Function;

    // 에디터 위치
    UPROPERTY()
    int32 MaterialExpressionEditorX;

    UPROPERTY()
    int32 MaterialExpressionEditorY;

    // 출력 핀 이름들
    UPROPERTY()
    TArray<FExpressionOutput> Outputs;

    // 에디터 표시 이름
    UPROPERTY()
    FString Desc;

    // 컴파일 시 활성화 여부
    UPROPERTY()
    uint32 bCollapsed : 1;

public:
    // 핵심 컴파일 메서드 (서브클래스에서 구현)
    virtual int32 Compile(
        class FMaterialCompiler* Compiler,
        int32 OutputIndex
    ) PURE_VIRTUAL(UMaterialExpression::Compile, return INDEX_NONE;);

    // 출력 타입 획득
    virtual EMaterialValueType GetOutputType(int32 OutputIndex)
    {
        return MCT_Unknown;
    }

    // 입력 핀 개수
    virtual uint32 GetInputType(int32 InputIndex)
    {
        return MCT_Float;
    }

    // 에디터 표시명
    virtual void GetCaption(TArray<FString>& OutCaptions) const;

    // 입력 핀 정보
    virtual FExpressionInput* GetInput(int32 InputIndex);
    virtual FName GetInputName(int32 InputIndex) const;

#if WITH_EDITOR
    // 에디터 전용 기능
    virtual void PostEditChangeProperty(FPropertyChangedEvent& PropertyChangedEvent) override;
#endif
};
```

### 주요 표현식 서브클래스

| 클래스 | 노드 이름 | 설명 |
|--------|-----------|------|
| `UMaterialExpressionAdd` | Add | 두 입력 더하기 |
| `UMaterialExpressionMultiply` | Multiply | 두 입력 곱하기 |
| `UMaterialExpressionLerp` | Lerp | 선형 보간 |
| `UMaterialExpressionTextureSample` | TextureSample | 텍스처 샘플링 |
| `UMaterialExpressionScalarParameter` | ScalarParameter | 스칼라 파라미터 |
| `UMaterialExpressionVectorParameter` | VectorParameter | 벡터 파라미터 |
| `UMaterialExpressionTextureParameter` | TextureParameter | 텍스처 파라미터 |
| `UMaterialExpressionTime` | Time | 게임 시간 |
| `UMaterialExpressionWorldPosition` | WorldPosition | 월드 위치 |
| `UMaterialExpressionVertexNormalWS` | VertexNormalWS | 월드 공간 버텍스 노멀 |

---

### 9.4.3 표현식 컴파일 예시

#### Add 노드 컴파일

```cpp
// UMaterialExpressionAdd::Compile()

int32 UMaterialExpressionAdd::Compile(FMaterialCompiler* Compiler, int32 OutputIndex)
{
    // A 입력이 연결되어 있지 않으면 ConstA 사용
    int32 Arg1 = A.GetTracedInput().Expression ?
        A.Compile(Compiler) :
        Compiler->Constant(ConstA);

    // B 입력이 연결되어 있지 않으면 ConstB 사용
    int32 Arg2 = B.GetTracedInput().Expression ?
        B.Compile(Compiler) :
        Compiler->Constant(ConstB);

    // 컴파일러의 Add 메서드 호출
    return Compiler->Add(Arg1, Arg2);
}
```

#### Multiply 노드 컴파일

```cpp
// UMaterialExpressionMultiply::Compile()

int32 UMaterialExpressionMultiply::Compile(FMaterialCompiler* Compiler, int32 OutputIndex)
{
    int32 Arg1 = A.GetTracedInput().Expression ?
        A.Compile(Compiler) :
        Compiler->Constant(ConstA);

    int32 Arg2 = B.GetTracedInput().Expression ?
        B.Compile(Compiler) :
        Compiler->Constant(ConstB);

    return Compiler->Mul(Arg1, Arg2);
}
```

#### TextureSample 노드 컴파일

```cpp
// UMaterialExpressionTextureSample::Compile()

int32 UMaterialExpressionTextureSample::Compile(FMaterialCompiler* Compiler, int32 OutputIndex)
{
    // 텍스처 획득
    int32 TextureCodeIndex = Texture.Compile(Compiler);

    // UV 좌표 컴파일
    int32 UVIndex = Coordinates.GetTracedInput().Expression ?
        Coordinates.Compile(Compiler) :
        Compiler->TextureCoordinate(ConstCoordinate, false, false);

    // MipLevel 또는 MipBias 처리
    int32 MipValue = INDEX_NONE;
    if (MipValueMode == TMVM_MipLevel)
    {
        MipValue = MipValue0.Compile(Compiler);
    }
    else if (MipValueMode == TMVM_MipBias)
    {
        MipValue = MipValue0.Compile(Compiler);
    }

    // 텍스처 샘플링 코드 생성
    return Compiler->TextureSample(
        TextureCodeIndex,
        UVIndex,
        SamplerType,
        MipValueMode,
        MipValue
    );
}
```

---

### 9.4.4 FMaterialCompiler 인터페이스

`FMaterialCompiler`는 머티리얼 표현식을 셰이더 코드로 변환하는 추상 인터페이스입니다.

```cpp
// Engine/Source/Runtime/Engine/Public/MaterialCompiler.h

class FMaterialCompiler
{
public:
    // 에러 처리
    virtual int32 Errorf(const TCHAR* Format, ...) = 0;

    // 상수 생성
    virtual int32 Constant(float X) = 0;
    virtual int32 Constant2(float X, float Y) = 0;
    virtual int32 Constant3(float X, float Y, float Z) = 0;
    virtual int32 Constant4(float X, float Y, float Z, float W) = 0;

    // 산술 연산
    virtual int32 Add(int32 A, int32 B) = 0;
    virtual int32 Sub(int32 A, int32 B) = 0;
    virtual int32 Mul(int32 A, int32 B) = 0;
    virtual int32 Div(int32 A, int32 B) = 0;
    virtual int32 Dot(int32 A, int32 B) = 0;
    virtual int32 Cross(int32 A, int32 B) = 0;

    // 수학 함수
    virtual int32 Power(int32 Base, int32 Exponent) = 0;
    virtual int32 SquareRoot(int32 X) = 0;
    virtual int32 Sine(int32 X) = 0;
    virtual int32 Cosine(int32 X) = 0;
    virtual int32 Floor(int32 X) = 0;
    virtual int32 Ceil(int32 X) = 0;
    virtual int32 Frac(int32 X) = 0;
    virtual int32 Abs(int32 X) = 0;

    // 벡터 연산
    virtual int32 Lerp(int32 X, int32 Y, int32 A) = 0;
    virtual int32 Saturate(int32 X) = 0;
    virtual int32 Clamp(int32 X, int32 A, int32 B) = 0;
    virtual int32 Normalize(int32 VectorInput) = 0;

    // 텍스처 연산
    virtual int32 TextureSample(
        int32 TextureIndex,
        int32 CoordinateIndex,
        EMaterialSamplerType SamplerType,
        int32 MipValueIndex = INDEX_NONE,
        ETextureMipValueMode MipValueMode = TMVM_None
    ) = 0;
    virtual int32 TextureCoordinate(uint32 CoordinateIndex, bool UnMirrorU, bool UnMirrorV) = 0;

    // 파라미터
    virtual int32 ScalarParameter(FName ParameterName, float DefaultValue) = 0;
    virtual int32 VectorParameter(FName ParameterName, const FLinearColor& DefaultValue) = 0;

    // 셰이더 입력
    virtual int32 VertexColor() = 0;
    virtual int32 WorldPosition(EWorldPositionIncludedOffsets WorldPositionIncludedOffsets) = 0;
    virtual int32 CameraVector() = 0;
    virtual int32 LightVector() = 0;

    // 커스텀 코드
    virtual int32 CustomExpression(
        class UMaterialExpressionCustom* Custom,
        int32 OutputIndex,
        TArray<int32>& CompiledInputs
    ) = 0;
};
```

---

### 9.4.5 FHLSLMaterialTranslator

`FHLSLMaterialTranslator`는 `FMaterialCompiler`를 구현하여 실제 HLSL 코드를 생성합니다.

![FHLSLMaterialTranslator](../images/ch10/1617944-20210806160631455-530688433.jpg)

```cpp
// Engine/Source/Runtime/Engine/Private/Materials/HLSLMaterialTranslator.cpp

class FHLSLMaterialTranslator : public FMaterialCompiler
{
private:
    // 생성된 코드 청크들
    TArray<FShaderCodeChunk> CodeChunks;

    // Uniform Expression들
    TArray<FMaterialUniformExpression*> UniformExpressions;

    // 현재 셰이더 주파수 (Vertex/Pixel/Compute)
    EShaderFrequency ShaderFrequency;

    // 머티리얼 컴파일 출력
    FMaterialCompilationOutput& MaterialCompilationOutput;

public:
    // Add 연산 구현
    virtual int32 Add(int32 A, int32 B) override
    {
        if (A == INDEX_NONE || B == INDEX_NONE)
        {
            return INDEX_NONE;
        }

        // 결과 타입 결정
        EMaterialValueType ResultType = GetArithmeticResultType(A, B);

        // 코드 청크 생성
        return AddCodeChunk(
            ResultType,
            TEXT("(%s + %s)"),
            *GetParameterCode(A),
            *GetParameterCode(B)
        );
    }

    // Multiply 연산 구현
    virtual int32 Mul(int32 A, int32 B) override
    {
        if (A == INDEX_NONE || B == INDEX_NONE)
        {
            return INDEX_NONE;
        }

        EMaterialValueType ResultType = GetArithmeticResultType(A, B);

        return AddCodeChunk(
            ResultType,
            TEXT("(%s * %s)"),
            *GetParameterCode(A),
            *GetParameterCode(B)
        );
    }

    // Lerp 연산 구현
    virtual int32 Lerp(int32 X, int32 Y, int32 A) override
    {
        if (X == INDEX_NONE || Y == INDEX_NONE || A == INDEX_NONE)
        {
            return INDEX_NONE;
        }

        EMaterialValueType ResultType = GetArithmeticResultType(X, Y);

        return AddCodeChunk(
            ResultType,
            TEXT("lerp(%s, %s, %s)"),
            *GetParameterCode(X),
            *GetParameterCode(Y),
            *GetParameterCode(A)
        );
    }

    // 텍스처 샘플 구현
    virtual int32 TextureSample(
        int32 TextureIndex,
        int32 CoordinateIndex,
        EMaterialSamplerType SamplerType,
        int32 MipValueIndex,
        ETextureMipValueMode MipValueMode) override
    {
        FString SampleCode;

        if (MipValueMode == TMVM_None)
        {
            SampleCode = FString::Printf(
                TEXT("Texture2DSample(%s, %sSampler, %s)"),
                *GetParameterCode(TextureIndex),
                *GetParameterCode(TextureIndex),
                *GetParameterCode(CoordinateIndex)
            );
        }
        else if (MipValueMode == TMVM_MipLevel)
        {
            SampleCode = FString::Printf(
                TEXT("Texture2DSampleLevel(%s, %sSampler, %s, %s)"),
                *GetParameterCode(TextureIndex),
                *GetParameterCode(TextureIndex),
                *GetParameterCode(CoordinateIndex),
                *GetParameterCode(MipValueIndex)
            );
        }

        return AddCodeChunk(MCT_Float4, *SampleCode);
    }

private:
    // 코드 청크 추가
    int32 AddCodeChunk(EMaterialValueType Type, const TCHAR* Format, ...)
    {
        int32 Index = CodeChunks.Num();

        FShaderCodeChunk Chunk;
        Chunk.Type = Type;

        va_list Args;
        va_start(Args, Format);
        Chunk.Definition = FString::PrintfImpl(Format, Args);
        va_end(Args);

        CodeChunks.Add(Chunk);
        return Index;
    }

    // 파라미터 코드 획득
    FString GetParameterCode(int32 Index) const
    {
        if (Index == INDEX_NONE)
        {
            return TEXT("0");
        }

        const FShaderCodeChunk& Chunk = CodeChunks[Index];

        // Uniform Expression인 경우 변수명 반환
        if (Chunk.UniformExpression)
        {
            return Chunk.UniformExpression->GetParameterName();
        }

        // 일반 코드인 경우 Local 변수명 반환
        return FString::Printf(TEXT("Local%d"), Index);
    }
};
```

---

### 9.4.6 코드 청크 시스템

컴파일 과정에서 각 노드는 코드 청크(Code Chunk)를 생성하고, 이들이 누적되어 최종 HLSL 코드가 됩니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    코드 청크 시스템                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【코드 청크 구조】                                              │
│                                                                 │
│  struct FShaderCodeChunk                                         │
│  {                                                               │
│      EMaterialValueType Type;        // 결과 타입 (float, float3...)│
│      FString Definition;             // HLSL 코드 정의           │
│      FMaterialUniformExpression* UniformExpression;  // 균등 표현식│
│      bool bInline;                   // 인라인 여부              │
│  };                                                              │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【청크 생성 예시】                                              │
│                                                                 │
│  TextureSample 노드:                                             │
│      Index: 0                                                    │
│      Code: "Texture2DSample(Tex, TexSampler, UV)"               │
│      Type: MCT_Float4                                            │
│                                                                 │
│  Multiply 노드:                                                  │
│      Index: 1                                                    │
│      Code: "(Local0 * Param)"                                    │
│      Type: MCT_Float4                                            │
│                                                                 │
│  Lerp 노드:                                                      │
│      Index: 2                                                    │
│      Code: "lerp(Local1, Color, Alpha)"                          │
│      Type: MCT_Float4                                            │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【생성된 HLSL 코드】                                            │
│                                                                 │
│  float4 Local0 = Texture2DSample(Tex, TexSampler, UV);          │
│  float4 Local1 = (Local0 * Param);                              │
│  float4 Local2 = lerp(Local1, Color, Alpha);                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.4.7 컴파일 흐름

전체 머티리얼 컴파일 흐름은 다음과 같습니다.

![머티리얼 컴파일 흐름](../images/ch10/1617944-20210806160646329-1846548437.webp)

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 컴파일 전체 흐름                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 【트리거】                                                   │
│     머티리얼 저장/적용 또는 에디터에서 변경                      │
│         │                                                       │
│         ▼                                                       │
│  2. 【컴파일 시작】                                              │
│     FMaterial::BeginCompileShaderMap()                          │
│         │                                                       │
│         ▼                                                       │
│  3. 【번역기 생성】                                              │
│     FHLSLMaterialTranslator 인스턴스 생성                        │
│         │                                                       │
│         ▼                                                       │
│  4. 【출력 핀 순회】                                             │
│     BaseColor, Normal, Metallic, Roughness, ... 각 출력 핀      │
│         │                                                       │
│         ▼                                                       │
│  5. 【노드 트리 역순회】                                         │
│                                                                 │
│     BaseColor 핀                                                 │
│         │                                                       │
│         └── 연결된 Lerp 노드                                    │
│                 │                                               │
│                 ├── X 입력: Multiply 노드                       │
│                 │       │                                       │
│                 │       └── A 입력: TextureSample 노드          │
│                 │                                               │
│                 ├── Y 입력: VectorParameter 노드                │
│                 │                                               │
│                 └── Alpha 입력: ScalarParameter 노드            │
│                                                                 │
│         │                                                       │
│         ▼                                                       │
│  6. 【각 노드 Compile() 호출】                                   │
│                                                                 │
│     TextureSample.Compile(Compiler) → 코드 ID: 0                │
│     Multiply.Compile(Compiler)      → 코드 ID: 1                │
│     VectorParameter.Compile(...)    → 코드 ID: 2                │
│     ScalarParameter.Compile(...)    → 코드 ID: 3                │
│     Lerp.Compile(Compiler)          → 코드 ID: 4                │
│                                                                 │
│         │                                                       │
│         ▼                                                       │
│  7. 【HLSL 코드 청크 누적】                                      │
│                                                                 │
│     float4 Local0 = Texture2DSample(Tex, TexSampler, UV);       │
│     float4 Local1 = (Local0 * Material.Param1);                 │
│     float3 Local2 = Material.VectorParam;                       │
│     float  Local3 = Material.ScalarParam;                       │
│     float4 Local4 = lerp(Local1, Local2, Local3);               │
│                                                                 │
│         │                                                       │
│         ▼                                                       │
│  8. 【MaterialTemplate.ush에 삽입】                              │
│                                                                 │
│     void CalcMaterialParametersEx(...)                          │
│     {                                                           │
│         // 생성된 코드                                          │
│         %MATERIAL_CODE%                                          │
│                                                                 │
│         // 출력 할당                                            │
│         PixelMaterialInputs.BaseColor = Local4.rgb;             │
│     }                                                           │
│                                                                 │
│         │                                                       │
│         ▼                                                       │
│  9. 【패스별 셰이더 컴파일】                                     │
│     BasePass, DepthPass, ShadowDepth, Velocity, ...             │
│         │                                                       │
│         ▼                                                       │
│  10. 【FMaterialShaderMap 생성】                                 │
│      컴파일된 셰이더들을 ShaderMap에 저장 및 캐싱                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.4.8 MaterialTemplate.ush

생성된 HLSL 코드는 `MaterialTemplate.ush` 템플릿에 삽입됩니다.

```hlsl
// Engine/Shaders/Private/MaterialTemplate.ush (간략화)

// 머티리얼 입력 구조체
struct FMaterialPixelParameters
{
    float4 SvPosition;
    float3 WorldPosition;
    float3 WorldNormal;
    float3 ReflectionVector;
    float2 TexCoords[NUM_MATERIAL_TEXCOORDS];
    float4 VertexColor;
    // ...
};

// 머티리얼 출력 구조체
struct FPixelMaterialInputs
{
    float3 BaseColor;
    float  Metallic;
    float  Specular;
    float  Roughness;
    float3 EmissiveColor;
    float  Opacity;
    float  OpacityMask;
    float3 Normal;
    // ...
};

// 머티리얼 파라미터 계산 함수
// 여기에 노드 그래프에서 생성된 코드가 삽입됨
void CalcMaterialParametersEx(
    FMaterialPixelParameters Parameters,
    FPixelMaterialInputs PixelMaterialInputs)
{
    // %MATERIAL_CODE% - 생성된 코드가 여기에 삽입됨

    // 예시: 생성된 코드
    float4 Local0 = Texture2DSample(Material.Texture_0, Material.Texture_0Sampler, Parameters.TexCoords[0]);
    float4 Local1 = (Local0 * Material.ScalarExpressions[0]);
    float3 Local2 = lerp(Local1.rgb, Material.VectorExpressions[0].rgb, Material.ScalarExpressions[1]);

    // 출력 할당
    PixelMaterialInputs.BaseColor = Local2;
    PixelMaterialInputs.Metallic = Material.ScalarExpressions[2];
    PixelMaterialInputs.Roughness = Material.ScalarExpressions[3];
    PixelMaterialInputs.Normal = normalize(Parameters.WorldNormal);
    // ...
}
```

### 템플릿 플레이스홀더

```
┌─────────────────────────────────────────────────────────────────┐
│                    MaterialTemplate.ush 플레이스홀더             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  %DIFFUSE_COLOR%           - 디퓨즈 컬러 코드                   │
│  %SPECULAR_COLOR%          - 스페큘러 컬러 코드                 │
│  %NORMAL%                  - 노멀 코드                          │
│  %EMISSIVE_COLOR%          - 이미시브 컬러 코드                 │
│  %OPACITY%                 - 오파시티 코드                      │
│  %OPACITY_MASK%            - 오파시티 마스크 코드               │
│  %METALLIC%                - 메탈릭 코드                        │
│  %ROUGHNESS%               - 러프니스 코드                      │
│  %SUBSURFACE_COLOR%        - 서브서피스 컬러 코드               │
│  %AMBIENT_OCCLUSION%       - AO 코드                            │
│  %REFRACTION%              - 굴절 코드                          │
│  %PIXEL_DEPTH_OFFSET%      - 픽셀 깊이 오프셋 코드              │
│  %WORLD_POSITION_OFFSET%   - 월드 위치 오프셋 코드              │
│                                                                 │
│  %MATERIAL_CODE%           - 전체 생성 코드                     │
│  %UNIFORM_EXPRESSIONS%     - 균등 표현식 선언                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.4.9 셰이더 주파수 제한

특정 표현식은 셰이더 주파수에 따라 제한됩니다.

```cpp
// DDX/DDY는 픽셀 셰이더에서만 사용 가능
int32 FHLSLMaterialTranslator::DDX(int32 X)
{
    if (ShaderFrequency == SF_Compute)
    {
        // 컴퓨트 셰이더에서는 0 반환
        return Constant(0.f);
    }

    if (ShaderFrequency != SF_Pixel)
    {
        // 픽셀 셰이더가 아니면 에러
        return NonPixelShaderExpressionError();
    }

    return AddCodeChunk(GetParameterType(X), TEXT("ddx(%s)"), *GetParameterCode(X));
}

int32 FHLSLMaterialTranslator::NonPixelShaderExpressionError()
{
    return Errorf(TEXT("This expression is only valid in pixel shaders."));
}
```

### 셰이더 주파수별 사용 가능 표현식

| 표현식 | Vertex | Pixel | Compute |
|--------|:------:|:-----:|:-------:|
| WorldPosition | O | O | O |
| VertexNormal | O | O | - |
| DDX/DDY | - | O | - |
| SceneTexture | - | O | - |
| TextureSample | O | O | O |
| Time | O | O | O |
| CameraVector | - | O | - |

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/15109132.html)
- [UE 머티리얼 문서](https://docs.unrealengine.com/5.0/en-US/unreal-engine-materials/)
