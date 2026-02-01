# 셰이더 아키텍처

UE 셰이더 시스템의 클래스 구조와 생명주기를 분석합니다.

---

## 셰이더 타입 시스템

### FShaderType

```cpp
// 셰이더 타입 - 셰이더 클래스의 메타데이터
class FShaderType
{
public:
    // 셰이더 이름
    const TCHAR* Name;

    // 셰이더 파일 경로
    const TCHAR* SourceFilename;

    // 진입점 함수
    const TCHAR* FunctionName;

    // 셰이더 스테이지 (VS, PS, CS 등)
    EShaderFrequency Frequency;

    // 순열 차원 수
    int32 TotalPermutationCount;

    // 컴파일 가능 여부 판단
    bool (*ShouldCompilePermutation)(const FShaderPermutationParameters&);

    // 셰이더 생성
    FShader* (*ConstructSerializedInstance)();
    FShader* (*ConstructCompiledInstance)(const FShaderCompilerOutput&);

    // 전역 타입 레지스트리
    static TLinkedList<FShaderType*>* GetTypeList();
};

// 셰이더 타입 선언 매크로
#define DECLARE_SHADER_TYPE(ShaderClass, ShaderMetaTypeShortcut) \
    public: \
    using ShaderMetaType = F##ShaderMetaTypeShortcut##ShaderType; \
    static ShaderMetaType StaticType; \
    ...
```

### 셰이더 스테이지

```cpp
// 셰이더 스테이지 열거형
enum EShaderFrequency
{
    SF_Vertex,          // 버텍스 셰이더
    SF_Hull,            // 헐 셰이더 (테셀레이션)
    SF_Domain,          // 도메인 셰이더 (테셀레이션)
    SF_Geometry,        // 지오메트리 셰이더
    SF_Pixel,           // 픽셀 (프래그먼트) 셰이더
    SF_Compute,         // 컴퓨트 셰이더
    SF_RayGen,          // 레이 제너레이션 (DXR)
    SF_RayMiss,         // 레이 미스 (DXR)
    SF_RayHitGroup,     // 레이 히트 그룹 (DXR)
    SF_RayCallable,     // 레이 콜러블 (DXR)

    SF_NumFrequencies,
};
```

---

## 셰이더 클래스 계층

### FShader

```cpp
// 모든 셰이더의 기본 클래스
class FShader
{
public:
    // 타입 정보
    FShaderType* GetType() const { return Type; }

    // 리소스 (컴파일된 바이트코드)
    FShaderResource* GetResource() const { return Resource; }

    // 파라미터 맵
    const FShaderParameterMapInfo& GetParameterMapInfo() const;

    // 해시
    FSHAHash GetOutputHash() const { return OutputHash; }

    // 직렬화
    virtual bool SerializeBase(FArchive& Ar, bool bShadersInline);

protected:
    FShaderType* Type;
    FShaderResource* Resource;
    FSHAHash OutputHash;
    FShaderParameterBindings Bindings;
};
```

### FGlobalShader

```cpp
// 전역 셰이더 - 머티리얼과 무관
class FGlobalShader : public FShader
{
    DECLARE_SHADER_TYPE(FGlobalShader, Global);

public:
    FGlobalShader() {}
    FGlobalShader(const ShaderMetaType::CompiledShaderInitializerType& Initializer)
        : FShader(Initializer)
    {}

    // 글로벌 셰이더 맵에서 검색
    static FGlobalShader* GetShader(FGlobalShaderMap* ShaderMap);
};

// 전역 셰이더 예시: 포스트 프로세스
class FBloomDownsampleCS : public FGlobalShader
{
    DECLARE_GLOBAL_SHADER(FBloomDownsampleCS);
    SHADER_USE_PARAMETER_STRUCT(FBloomDownsampleCS, FGlobalShader);

    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_RDG_TEXTURE(Texture2D, InputTexture)
        SHADER_PARAMETER_RDG_TEXTURE_UAV(RWTexture2D, OutputTexture)
        SHADER_PARAMETER(FVector2f, InputTexelSize)
        SHADER_PARAMETER(float, BloomThreshold)
    END_SHADER_PARAMETER_STRUCT()
};

IMPLEMENT_GLOBAL_SHADER(FBloomDownsampleCS, "/Engine/Private/Bloom.usf", "DownsampleCS", SF_Compute);
```

### FMaterialShader

```cpp
// 머티리얼 셰이더 - 특정 머티리얼 타입에 종속
class FMaterialShader : public FShader
{
    DECLARE_SHADER_TYPE(FMaterialShader, Material);

public:
    FMaterialShader() {}
    FMaterialShader(const ShaderMetaType::CompiledShaderInitializerType& Initializer)
        : FShader(Initializer)
    {}

    // 머티리얼 타입 접근
    const FMaterial* GetMaterial() const;

    // 컴파일 조건
    static bool ShouldCompilePermutation(
        const FMaterialShaderPermutationParameters& Parameters)
    {
        // 디퍼드만 지원하는 셰이더
        return Parameters.MaterialParameters.bIsUsedWithDeferredShading;
    }
};
```

### FMeshMaterialShader

```cpp
// 메시 머티리얼 셰이더 - 버텍스 팩토리 + 머티리얼 조합
class FMeshMaterialShader : public FMaterialShader
{
    DECLARE_SHADER_TYPE(FMeshMaterialShader, MeshMaterial);

public:
    FMeshMaterialShader() {}
    FMeshMaterialShader(const ShaderMetaType::CompiledShaderInitializerType& Initializer)
        : FMaterialShader(Initializer)
    {}

    // 버텍스 팩토리 접근
    const FVertexFactory* GetVertexFactory() const;

    // 컴파일 조건
    static bool ShouldCompilePermutation(
        const FMeshMaterialShaderPermutationParameters& Parameters)
    {
        // 버텍스 팩토리와 머티리얼 조합 체크
        return Parameters.VertexFactoryType->SupportsPositionOnly()
            && Parameters.MaterialParameters.bIsDefaultMaterial;
    }
};

// 메시 머티리얼 셰이더 예시: BasePass
class FBasePassPS : public FMeshMaterialShader
{
    DECLARE_SHADER_TYPE(FBasePassPS, MeshMaterial);

    // 순열 정의
    class FSkylightDim : SHADER_PERMUTATION_BOOL("USE_SKYLIGHT");
    class FLightmapDim : SHADER_PERMUTATION_INT("LIGHTMAP_TYPE", 3);

    using FPermutationDomain = TShaderPermutationDomain<
        FSkylightDim,
        FLightmapDim
    >;

    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_STRUCT_INCLUDE(FViewShaderParameters, View)
        SHADER_PARAMETER_STRUCT_INCLUDE(FMaterialShaderParameters, Material)
    END_SHADER_PARAMETER_STRUCT()
};
```

---

## 셰이더 맵

### FGlobalShaderMap

```cpp
// 전역 셰이더 맵 - 플랫폼당 하나
class FGlobalShaderMap
{
public:
    // 플랫폼별 셰이더 맵
    static FGlobalShaderMap* GetGlobalShaderMap(EShaderPlatform Platform);

    // 셰이더 조회
    template<typename ShaderType>
    ShaderType* GetShader()
    {
        return static_cast<ShaderType*>(
            GetShader(&ShaderType::StaticType, FShaderPermutationNone()));
    }

    // 순열이 있는 셰이더 조회
    template<typename ShaderType>
    ShaderType* GetShader(typename ShaderType::FPermutationDomain PermutationVector)
    {
        return static_cast<ShaderType*>(
            GetShader(&ShaderType::StaticType, PermutationVector.ToDimensionValueId()));
    }

private:
    TMap<FShaderType*, TUniquePtr<FShader>> ShaderMap;
};

// 사용 예시
void UseGlobalShader()
{
    FGlobalShaderMap* GlobalShaderMap = GetGlobalShaderMap(GMaxRHIShaderPlatform);

    // 순열 없는 셰이더
    auto* BlitShader = GlobalShaderMap->GetShader<FBlitPS>();

    // 순열 있는 셰이더
    FBloomPS::FPermutationDomain PermutationVector;
    PermutationVector.Set<FBloomPS::FHighQualityDim>(true);
    auto* BloomShader = GlobalShaderMap->GetShader<FBloomPS>(PermutationVector);
}
```

### FMaterialShaderMap

```cpp
// 머티리얼 셰이더 맵 - 머티리얼당 하나
class FMaterialShaderMap
{
public:
    // 머티리얼에서 셰이더 맵 얻기
    static FMaterialShaderMap* GetShaderMap(const FMaterial* Material);

    // 셰이더 조회
    template<typename ShaderType>
    ShaderType* GetShader(FVertexFactoryType* VertexFactoryType)
    {
        FMeshMaterialShaderMap* MeshShaderMap = GetMeshShaderMap(VertexFactoryType);
        return MeshShaderMap ? MeshShaderMap->GetShader<ShaderType>() : nullptr;
    }

private:
    // 버텍스 팩토리별 서브맵
    TMap<FVertexFactoryType*, FMeshMaterialShaderMap*> MeshShaderMaps;
};
```

---

## 셰이더 리소스

### FShaderResource

```cpp
// 컴파일된 셰이더 바이너리
class FShaderResource
{
public:
    // 플랫폼별 바이너리
    TArray<uint8> Code;

    // 셰이더 스테이지
    EShaderFrequency Frequency;

    // 대상 플랫폼
    EShaderPlatform Platform;

    // RHI 셰이더 객체
    FRHIShader* GetRHIShader() const;

    // 코드 해시
    FSHAHash GetOutputHash() const;

    // 통계
    int32 GetCodeSize() const { return Code.Num(); }
    int32 GetNumInstructions() const;
};

// RHI 셰이더 생성
FRHIShader* FShaderResource::CreateRHIShader()
{
    switch (Frequency)
    {
        case SF_Vertex:
            return RHICreateVertexShader(Code);
        case SF_Pixel:
            return RHICreatePixelShader(Code);
        case SF_Compute:
            return RHICreateComputeShader(Code);
        // ...
    }
}
```

---

## 셰이더 컴파일 환경

### FShaderCompilerEnvironment

```cpp
// 셰이더 컴파일러 환경 설정
struct FShaderCompilerEnvironment
{
    // 정의 매크로
    TMap<FString, FString> Definitions;

    // 인클루드 경로
    TArray<FString> IncludePaths;

    // 컴파일러 플래그
    uint32 CompilerFlags;

    // 대상 플랫폼
    EShaderPlatform TargetPlatform;

    // 매크로 설정
    void SetDefine(const TCHAR* Name, const TCHAR* Value)
    {
        Definitions.Add(Name, Value);
    }

    void SetDefine(const TCHAR* Name, int32 Value)
    {
        Definitions.Add(Name, FString::Printf(TEXT("%d"), Value));
    }
};

// 환경 설정 예시
void SetupShaderCompilerEnvironment(FShaderCompilerEnvironment& Env)
{
    // 플랫폼 정의
    Env.SetDefine(TEXT("PLATFORM_SUPPORTS_SM6"), 1);

    // 기능 정의
    Env.SetDefine(TEXT("USE_DEVELOPMENT_SHADERS"), 1);
    Env.SetDefine(TEXT("MAX_LIGHTS"), 4);

    // 최적화 레벨
    Env.CompilerFlags |= CFLAG_StandardOptimization;
}
```

---

## 셰이더 생명주기

### 컴파일 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 생명주기                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 에디터 시작 / 머티리얼 저장                                  │
│       │                                                         │
│       ▼                                                         │
│  2. 셰이더 타입 등록                                             │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ FShaderType::GetTypeList()->AddTail(&StaticType)    │    │
│     └─────────────────────────────────────────────────────┘    │
│       │                                                         │
│       ▼                                                         │
│  3. 컴파일 요청                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ for each Permutation:                               │    │
│     │   if ShouldCompilePermutation():                    │    │
│     │     QueueCompile(...)                               │    │
│     └─────────────────────────────────────────────────────┘    │
│       │                                                         │
│       ▼                                                         │
│  4. 셰이더 컴파일 (비동기)                                       │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ ShaderCompilerWorker 프로세스에서 컴파일              │    │
│     │ 결과를 DDC (Derived Data Cache)에 저장               │    │
│     └─────────────────────────────────────────────────────┘    │
│       │                                                         │
│       ▼                                                         │
│  5. 셰이더 로드                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ DDC에서 로드 또는 재컴파일                           │    │
│     │ FShader 인스턴스 생성                                │    │
│     └─────────────────────────────────────────────────────┘    │
│       │                                                         │
│       ▼                                                         │
│  6. 런타임 사용                                                  │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ GetShader<T>() 로 조회                               │    │
│     │ 파라미터 바인딩                                      │    │
│     │ Draw/Dispatch                                        │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 코드 예시

```cpp
// 셰이더 사용 예시
void RenderBloom(FRDGBuilder& GraphBuilder, const FViewInfo& View)
{
    // 1. 셰이더 가져오기
    FGlobalShaderMap* ShaderMap = GetGlobalShaderMap(View.GetShaderPlatform());

    FBloomDownsampleCS::FPermutationDomain PermutationVector;
    PermutationVector.Set<FBloomDownsampleCS::FQualityDim>(View.BloomQuality);

    TShaderMapRef<FBloomDownsampleCS> ComputeShader(ShaderMap, PermutationVector);

    // 2. 파라미터 설정
    FBloomDownsampleCS::FParameters* Parameters =
        GraphBuilder.AllocParameters<FBloomDownsampleCS::FParameters>();

    Parameters->InputTexture = SceneColor;
    Parameters->OutputTexture = GraphBuilder.CreateUAV(OutputTexture);
    Parameters->InputTexelSize = FVector2f(1.0f / InputSize.X, 1.0f / InputSize.Y);
    Parameters->BloomThreshold = View.BloomThreshold;

    // 3. 디스패치
    FComputeShaderUtils::AddPass(
        GraphBuilder,
        RDG_EVENT_NAME("BloomDownsample"),
        ComputeShader,
        Parameters,
        FComputeShaderUtils::GetGroupCount(OutputSize, 8));
}
```

---

## 버텍스 팩토리

### FVertexFactory

```cpp
// 버텍스 팩토리 - 버텍스 데이터 형식 정의
class FVertexFactory
{
public:
    // 버텍스 스트림 선언
    virtual void InitRHI() override
    {
        FVertexDeclarationElementList Elements;

        // 위치
        Elements.Add(FVertexElement(
            0, STRUCT_OFFSET(FVertex, Position),
            VET_Float3, 0, sizeof(FVertex)));

        // 노말
        Elements.Add(FVertexElement(
            0, STRUCT_OFFSET(FVertex, Normal),
            VET_PackedNormal, 1, sizeof(FVertex)));

        // UV
        Elements.Add(FVertexElement(
            0, STRUCT_OFFSET(FVertex, UV),
            VET_Float2, 2, sizeof(FVertex)));

        InitDeclaration(Elements);
    }

    // 셰이더 파라미터
    virtual void GetVertexFactoryShaderParameters(FVertexFactoryShaderParameters& Parameters);
};

// 버텍스 팩토리 타입
class FLocalVertexFactory : public FVertexFactory
{
    DECLARE_VERTEX_FACTORY_TYPE(FLocalVertexFactory);

    // 스태틱 메시용 기본 팩토리
};

class FGPUSkinVertexFactory : public FVertexFactory
{
    DECLARE_VERTEX_FACTORY_TYPE(FGPUSkinVertexFactory);

    // 스켈레탈 메시용 팩토리
    // 본 행렬 스트림 추가
};
```

---

## 요약

| 클래스 | 용도 |
|--------|------|
| FShaderType | 셰이더 메타데이터, 컴파일 조건 |
| FShader | 셰이더 기본 클래스 |
| FGlobalShader | 전역 셰이더 (포스트 프로세스 등) |
| FMaterialShader | 머티리얼 종속 셰이더 |
| FMeshMaterialShader | 메시+머티리얼 조합 셰이더 |
| FShaderResource | 컴파일된 바이너리 |
| FVertexFactory | 버텍스 데이터 형식 |

셰이더 아키텍처는 UE 렌더링의 핵심 기반입니다.
