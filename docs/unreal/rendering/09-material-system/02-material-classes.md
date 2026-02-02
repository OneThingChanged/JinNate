# 02. 머티리얼 기초 (하)

> 원문: [剖析虚幻渲染体系（09）- 材质体系](https://www.cnblogs.com/timlly/p/15109132.html)

FMaterialRenderProxy, FMaterial, FMaterialResource 클래스와 머티리얼 시스템 전체 구조를 분석합니다.

---

## 9.2.6 FMaterialRenderProxy

`FMaterialRenderProxy`는 게임 스레드의 `UMaterialInterface`에 대응하는 렌더 스레드 표현입니다. `UPrimitiveComponent`와 `FPrimitiveSceneProxy`의 관계와 유사하게, 게임 스레드와 렌더 스레드 간의 머티리얼 데이터 전달을 담당합니다.

![FMaterialRenderProxy 구조](../images/ch10/1617944-20210806160456148-576731307.jpg)

### 핵심 역할

```
┌─────────────────────────────────────────────────────────────────┐
│                  FMaterialRenderProxy 핵심 역할                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 데이터 전달                                                  │
│     └── 게임 스레드의 머티리얼 데이터를 렌더 스레드로 전송        │
│                                                                 │
│  2. Uniform Expression 캐시 관리                                 │
│     └── 머티리얼 파라미터의 균등 표현식 캐시 유지                 │
│                                                                 │
│  3. ShaderMap 접근 제공                                          │
│     └── 서브클래스를 통해 셰이더 맵 접근 인터페이스 제공          │
│                                                                 │
│  4. 파라미터 쿼리                                                │
│     └── 벡터, 스칼라, 텍스처 값 조회 기능 제공                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 클래스 정의

```cpp
// Engine/Source/Runtime/Engine/Public/MaterialShared.h

class FMaterialRenderProxy : public FRenderResource
{
public:
    // Uniform Expression 캐시 컨테이너
    mutable FUniformExpressionCacheContainer UniformExpressionCache;

    // 불변 샘플러 상태
    FImmutableSamplerState ImmutableSamplerState;

    // 모든 프록시를 추적하는 전역 맵 (ShaderMap 전파용)
    static TSet<FMaterialRenderProxy*> MaterialRenderProxyMap;

public:
    // 유효한 FMaterial 획득 (폴백 포함)
    virtual const FMaterial* GetMaterialWithFallback(
        ERHIFeatureLevel::Type FeatureLevel,
        const FMaterialRenderProxy*& OutFallbackMaterialRenderProxy
    ) const = 0;

    // 폴백 없이 직접 FMaterial 획득
    virtual const FMaterial* GetMaterialNoFallback(
        ERHIFeatureLevel::Type FeatureLevel
    ) const = 0;

    // 연관된 UMaterialInterface 반환
    virtual UMaterialInterface* GetMaterialInterface() const = 0;

    // 파라미터 값 조회
    virtual bool GetVectorValue(
        const FHashedMaterialParameterInfo& ParameterInfo,
        FLinearColor* OutValue,
        const FMaterialRenderContext& Context
    ) const = 0;

    virtual bool GetScalarValue(
        const FHashedMaterialParameterInfo& ParameterInfo,
        float* OutValue,
        const FMaterialRenderContext& Context
    ) const = 0;

    virtual bool GetTextureValue(
        const FHashedMaterialParameterInfo& ParameterInfo,
        const UTexture** OutValue,
        const FMaterialRenderContext& Context
    ) const = 0;
};
```

### 주요 멤버 변수

| 멤버 | 타입 | 설명 |
|------|------|------|
| `UniformExpressionCache` | `FUniformExpressionCacheContainer` | 균등 표현식 캐시 |
| `ImmutableSamplerState` | `FImmutableSamplerState` | 불변 샘플러 상태 |
| `MaterialRenderProxyMap` | `TSet<FMaterialRenderProxy*>` | 전역 프록시 추적 맵 |

---

## 9.2.7 FDefaultMaterialInstance

`FDefaultMaterialInstance`는 `UMaterial`을 렌더링하기 위한 프록시 클래스입니다.

```cpp
// Engine/Source/Runtime/Engine/Private/Materials/Material.cpp

class FDefaultMaterialInstance : public FMaterialRenderProxy
{
private:
    // 소유자 UMaterial
    UMaterial* Material;

public:
    FDefaultMaterialInstance(UMaterial* InMaterial)
        : Material(InMaterial)
    {}

    // FMaterial 획득 (폴백 메커니즘 포함)
    virtual const FMaterial* GetMaterialWithFallback(
        ERHIFeatureLevel::Type FeatureLevel,
        const FMaterialRenderProxy*& OutFallbackMaterialRenderProxy
    ) const override
    {
        // 현재 머티리얼에서 FMaterialResource 획득 시도
        const FMaterialResource* MaterialResource =
            Material->GetMaterialResource(FeatureLevel);

        // ShaderMap 유효성 검사
        if (MaterialResource &&
            MaterialResource->GetRenderingThreadShaderMap())
        {
            return MaterialResource;
        }

        // 실패 시 기본 머티리얼로 폴백
        OutFallbackMaterialRenderProxy =
            UMaterial::GetDefaultMaterial(MD_Surface)->GetRenderProxy();
        return OutFallbackMaterialRenderProxy->GetMaterialNoFallback(FeatureLevel);
    }

    // 벡터 파라미터 값 조회
    virtual bool GetVectorValue(
        const FHashedMaterialParameterInfo& ParameterInfo,
        FLinearColor* OutValue,
        const FMaterialRenderContext& Context
    ) const override
    {
        // UMaterial에서 파라미터 값 검색
        return Material->GetVectorParameterValue(
            ParameterInfo.Name, *OutValue
        );
    }

    // 스칼라 파라미터 값 조회
    virtual bool GetScalarValue(
        const FHashedMaterialParameterInfo& ParameterInfo,
        float* OutValue,
        const FMaterialRenderContext& Context
    ) const override
    {
        return Material->GetScalarParameterValue(
            ParameterInfo.Name, *OutValue
        );
    }
};
```

### 폴백 메커니즘

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 폴백 메커니즘                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GetMaterialWithFallback() 호출                                 │
│      │                                                          │
│      ▼                                                          │
│  FMaterialResource 획득 시도                                     │
│      │                                                          │
│      ├── 성공 + ShaderMap 유효                                  │
│      │       │                                                  │
│      │       └── FMaterialResource 반환                         │
│      │                                                          │
│      └── 실패 또는 ShaderMap 무효                               │
│              │                                                  │
│              ▼                                                  │
│          기본 머티리얼 (WorldGridMaterial) 사용                  │
│              │                                                  │
│              └── 회색 체크무늬 패턴으로 렌더링                   │
│                                                                 │
│  ※ 머티리얼 컴파일 중이거나 오류 발생 시 폴백 적용               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.2.8 FMaterialInstanceResource

`FMaterialInstanceResource`는 `UMaterialInstance`를 렌더링하기 위한 프록시 클래스입니다.

```cpp
// Engine/Source/Runtime/Engine/Private/Materials/MaterialInstance.cpp

class FMaterialInstanceResource : public FMaterialRenderProxy
{
private:
    // 게임 스레드용 부모 참조
    UMaterialInterface* GameThread_Parent;

    // 렌더 스레드용 부모 참조
    UMaterialInterface* Parent;

    // 소유자 머티리얼 인스턴스
    UMaterialInstance* Owner;

    // 파라미터 배열들
    TArray<TNamedParameter<FLinearColor>> VectorParameterArray;
    TArray<TNamedParameter<float>> ScalarParameterArray;
    TArray<TNamedParameter<const UTexture*>> TextureParameterArray;
    TArray<TNamedParameter<const URuntimeVirtualTexture*>> RuntimeVirtualTextureParameterArray;

public:
    // 게임 스레드에서 파라미터 업데이트
    void GameThread_SetParameter(FName Name, const FLinearColor& Value)
    {
        // 렌더 커맨드를 통해 렌더 스레드로 전달
        ENQUEUE_RENDER_COMMAND(SetVectorParameter)(
            [this, Name, Value](FRHICommandListImmediate& RHICmdList)
            {
                RenderThread_UpdateParameter(Name, Value);
            }
        );
    }

    // 렌더 스레드에서 파라미터 업데이트
    void RenderThread_UpdateParameter(FName Name, const FLinearColor& Value)
    {
        // 배열에서 파라미터 찾아서 업데이트
        for (TNamedParameter<FLinearColor>& Param : VectorParameterArray)
        {
            if (Param.Name == Name)
            {
                Param.Value = Value;
                // 캐시 무효화
                InvalidateUniformExpressionCache(false);
                return;
            }
        }
        // 새 파라미터 추가
        VectorParameterArray.Add(TNamedParameter<FLinearColor>(Name, Value));
        InvalidateUniformExpressionCache(false);
    }

    // 파라미터 값 조회
    virtual bool GetVectorValue(
        const FHashedMaterialParameterInfo& ParameterInfo,
        FLinearColor* OutValue,
        const FMaterialRenderContext& Context
    ) const override
    {
        // 로컬 배열에서 먼저 검색
        for (const TNamedParameter<FLinearColor>& Param : VectorParameterArray)
        {
            if (Param.Name == ParameterInfo.Name)
            {
                *OutValue = Param.Value;
                return true;
            }
        }
        // 찾지 못하면 부모에게 위임
        return Parent->GetRenderProxy()->GetVectorValue(
            ParameterInfo, OutValue, Context
        );
    }
};
```

### 스레드 안전성

```
┌─────────────────────────────────────────────────────────────────┐
│                    스레드 간 파라미터 동기화                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【게임 스레드】                                                 │
│                                                                 │
│  SetVectorParameterValue("Color", Red)                          │
│      │                                                          │
│      ▼                                                          │
│  GameThread_SetParameter()                                      │
│      │                                                          │
│      └── ENQUEUE_RENDER_COMMAND ─────────────────────┐          │
│                                                      │          │
│  ─────────────────────────────────────────────────────│──────── │
│                                                      │          │
│  【렌더 스레드】                                      ▼          │
│                                                                 │
│                                  RenderThread_UpdateParameter() │
│                                          │                      │
│                                          ├── 배열 업데이트       │
│                                          │                      │
│                                          └── 캐시 무효화        │
│                                                                 │
│  ※ 경쟁 조건(Race Condition) 방지를 위한 명시적 분리            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.2.9 FMaterial

`FMaterial`은 머티리얼과 셰이더 컴파일을 연결하는 추상 클래스로, 렌더링에 필요한 셰이더 맵과 컴파일 상태를 관리합니다.

![FMaterial 클래스 구조](../images/ch10/1617944-20210806160504062-1932418885.png)

### 세 가지 핵심 기능

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMaterial 세 가지 핵심 기능                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 【컴파일 표현】                                              │
│     머티리얼을 컴파일 프로세스로 표현                            │
│     확장 가능성 훅(Hook) 제공                                    │
│     셰이더 타입별 캐싱 여부 결정                                 │
│                                                                 │
│  2. 【데이터 전달】                                              │
│     머티리얼 데이터를 렌더러로 전달                              │
│     함수를 통해 속성 접근 제공                                   │
│     GetUniformExpressions() 등의 인터페이스                      │
│                                                                 │
│  3. 【ShaderMap 캐싱】                                           │
│     컴파일된 ShaderMap 캐싱                                      │
│     비동기 셰이더 컴파일에 필요한 임시 출력 저장                 │
│     게임/렌더 스레드별 ShaderMap 분리 관리                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 클래스 정의

```cpp
// Engine/Source/Runtime/Engine/Public/MaterialShared.h

class FMaterial
{
protected:
    // 게임 스레드용 ShaderMap
    TRefCountPtr<FMaterialShaderMap> GameThreadShaderMap;

    // 렌더 스레드용 ShaderMap
    TRefCountPtr<FMaterialShaderMap> RenderingThreadShaderMap;

    // 품질 레벨
    EMaterialQualityLevel::Type QualityLevel;

    // 피처 레벨
    ERHIFeatureLevel::Type FeatureLevel;

    // 컴파일 상태
    uint32 bContainsInlineShaders : 1;
    uint32 bLoadedCookedShaderMapId : 1;

public:
    // 특정 셰이더 타입의 캐싱 여부 결정
    virtual bool ShouldCache(EShaderPlatform Platform,
                             const FShaderType* ShaderType,
                             const FVertexFactoryType* VertexFactoryType) const;

    // Uniform Expression 획득
    virtual const FUniformExpressionSet& GetUniformExpressions() const;

    // 템플릿 기반 셰이더 획득
    template<typename ShaderType>
    ShaderType* GetShader(FVertexFactoryType* VertexFactoryType) const
    {
        return static_cast<ShaderType*>(
            GetShader(&ShaderType::StaticType, VertexFactoryType)
        );
    }

    // ShaderMap 접근
    FMaterialShaderMap* GetGameThreadShaderMap() const
    {
        return GameThreadShaderMap;
    }

    FMaterialShaderMap* GetRenderingThreadShaderMap() const
    {
        return RenderingThreadShaderMap;
    }

    // ShaderMap 설정 (게임 스레드에서 호출)
    void SetGameThreadShaderMap(FMaterialShaderMap* InShaderMap)
    {
        GameThreadShaderMap = InShaderMap;

        // 렌더 스레드로 비동기 전파
        FMaterial* Material = this;
        ENQUEUE_RENDER_COMMAND(SetRenderingThreadShaderMap)(
            [Material, InShaderMap](FRHICommandListImmediate& RHICmdList)
            {
                Material->RenderingThreadShaderMap = InShaderMap;
            }
        );
    }

    // 렌더링 스레드 ShaderMap 완료 여부
    bool IsRenderingThreadShaderMapComplete() const
    {
        return RenderingThreadShaderMap &&
               RenderingThreadShaderMap->IsComplete(this, true);
    }

    // 셰이더 캐싱
    bool CacheShaders(EShaderPlatform Platform, bool bApplyCompletedShaderMap);

    // 머티리얼 속성 (서브클래스에서 구현)
    virtual EMaterialDomain GetMaterialDomain() const = 0;
    virtual bool IsTwoSided() const = 0;
    virtual bool IsDitheredLODTransition() const = 0;
    virtual bool IsTranslucent() const = 0;
    virtual bool IsMasked() const = 0;
};
```

### 듀얼 ShaderMap 설계

```
┌─────────────────────────────────────────────────────────────────┐
│                    듀얼 ShaderMap 설계                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【게임 스레드】              【렌더 스레드】                     │
│                                                                 │
│  GameThreadShaderMap         RenderingThreadShaderMap           │
│        │                              │                         │
│        │                              │                         │
│        │    ENQUEUE_RENDER_COMMAND    │                         │
│        └──────────────────────────────┘                         │
│                                                                 │
│  ※ 설계 의도:                                                   │
│                                                                 │
│  • 게임 스레드에서 셰이더 컴파일 요청                            │
│  • 렌더 스레드에서 독립적으로 ShaderMap 접근                     │
│  • 컴파일 중에도 이전 ShaderMap으로 렌더링 계속                  │
│  • 스레드 안전한 업데이트 보장                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.2.10 FMaterialResource

`FMaterialResource`는 `FMaterial`의 유일한 구체적 구현체로, `UMaterial`과 `UMaterialInstance` 모두의 렌더링 리소스로 사용됩니다.

![FMaterialResource 구조](../images/ch10/1617944-20210806160514602-1260642356.png)

### 클래스 정의

```cpp
// Engine/Source/Runtime/Engine/Public/MaterialShared.h

class FMaterialResource : public FMaterial
{
private:
    // 연관된 UMaterial (항상 유효)
    UMaterial* Material;

    // 연관된 UMaterialInstance (선택적)
    UMaterialInstance* MaterialInstance;

public:
    FMaterialResource()
        : Material(nullptr)
        , MaterialInstance(nullptr)
    {}

    // 초기화
    void SetMaterial(UMaterial* InMaterial,
                     UMaterialInstance* InInstance = nullptr)
    {
        Material = InMaterial;
        MaterialInstance = InInstance;
    }

    // 머티리얼 속성 구현 (인스턴스 우선)
    virtual EMaterialDomain GetMaterialDomain() const override
    {
        return Material->MaterialDomain;
    }

    virtual bool IsTwoSided() const override
    {
        // MaterialInstance가 있으면 오버라이드 확인
        if (MaterialInstance &&
            MaterialInstance->BasePropertyOverrides.bOverride_TwoSided)
        {
            return MaterialInstance->BasePropertyOverrides.TwoSided;
        }
        return Material->TwoSided;
    }

    // 컴파일 속성 및 머티리얼 속성 설정
    void CompilePropertyAndSetMaterialProperty(
        EMaterialProperty Property,
        FMaterialCompiler* Compiler,
        EShaderFrequency OverrideShaderFrequency = SF_Pixel
    );

    // 셰이더 맵에서 셰이더 획득
    FShader* GetShader(FShaderType* ShaderType,
                       FVertexFactoryType* VertexFactoryType) const
    {
        return RenderingThreadShaderMap->GetShader(ShaderType, VertexFactoryType);
    }
};
```

### 데이터 우선순위

```
┌─────────────────────────────────────────────────────────────────┐
│                  FMaterialResource 데이터 우선순위               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  속성 조회 요청                                                  │
│      │                                                          │
│      ▼                                                          │
│  MaterialInstance != nullptr ?                                   │
│      │                                                          │
│      ├── Yes: MaterialInstance에서 오버라이드 확인               │
│      │       │                                                  │
│      │       ├── 오버라이드 있음 → 인스턴스 값 사용              │
│      │       │                                                  │
│      │       └── 오버라이드 없음 → Material 값 사용              │
│      │                                                          │
│      └── No: Material 값 직접 사용                               │
│                                                                 │
│  ※ 이 설계로 파라미터 변경 시 재컴파일 없이 값 변경 가능         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 생성 시점

```cpp
// UMaterial::FindOrCreateMaterialResource()

FMaterialResource* UMaterial::FindOrCreateMaterialResource(
    ERHIFeatureLevel::Type FeatureLevel,
    EMaterialQualityLevel::Type QualityLevel)
{
    // 기존 리소스 검색
    for (FMaterialResource* Resource : MaterialResources)
    {
        if (Resource->GetFeatureLevel() == FeatureLevel &&
            Resource->GetQualityLevel() == QualityLevel)
        {
            return Resource;
        }
    }

    // 새 리소스 생성
    FMaterialResource* NewResource = AllocateResource();
    NewResource->SetMaterial(this);
    MaterialResources.Add(NewResource);

    return NewResource;
}
```

FMaterialResource 생성은 다음 시점에 발생합니다:

- `UMaterial::PostLoad()` - 에셋 로드 시
- 셰이더 캐시 및 컴파일 작업 시
- 머티리얼 사용 플래그 업데이트 시

---

## 9.2.11 머티리얼 총람

### 전체 클래스 관계도

![머티리얼 시스템 전체 구조](../images/ch10/1617944-20210806160531633-1410619075.jpg)

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 시스템 전체 아키텍처                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    【게임 스레드】                        │   │
│  │                                                          │   │
│  │  UMaterialInterface                                      │   │
│  │      │                                                   │   │
│  │      ├── UMaterial ──────────────────┐                   │   │
│  │      │       │                       │                   │   │
│  │      │       │ MaterialResources     │ DefaultMaterial   │   │
│  │      │       ▼                       │ Instance          │   │
│  │      │  FMaterialResource[]          ▼                   │   │
│  │      │                         FDefaultMaterial          │   │
│  │      │                         Instance                  │   │
│  │      │                                                   │   │
│  │      └── UMaterialInstance ──────────┐                   │   │
│  │              │                       │                   │   │
│  │              │ Resource              │                   │   │
│  │              ▼                       ▼                   │   │
│  │         (공유)               FMaterialInstance           │   │
│  │                              Resource                    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              │ ENQUEUE_RENDER_COMMAND           │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    【렌더 스레드】                        │   │
│  │                                                          │   │
│  │  FMaterialRenderProxy                                    │   │
│  │      │                                                   │   │
│  │      ├── FDefaultMaterialInstance                        │   │
│  │      │       │                                           │   │
│  │      │       └── GetMaterialWithFallback()               │   │
│  │      │               │                                   │   │
│  │      │               ▼                                   │   │
│  │      │         FMaterialResource (FMaterial)             │   │
│  │      │               │                                   │   │
│  │      │               └── RenderingThreadShaderMap        │   │
│  │      │                                                   │   │
│  │      └── FMaterialInstanceResource                       │   │
│  │              │                                           │   │
│  │              └── 파라미터 배열 + GetMaterialWithFallback  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 설계 원칙

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 시스템 설계 원칙                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 【스레드 분리】                                              │
│     • 게임 스레드: UMaterialInterface 계층                       │
│     • 렌더 스레드: FMaterialRenderProxy + FMaterial 계층         │
│     • 명시적 커맨드 큐를 통한 동기화                             │
│                                                                 │
│  2. 【관심사 분리】                                              │
│     • UMaterialInterface: 에셋 라이프사이클, 에디터 데이터       │
│     • FMaterialRenderProxy: 스레드 안전한 데이터 전달            │
│     • FMaterial/FMaterialResource: 셰이더 컴파일, 파라미터 접근  │
│                                                                 │
│  3. 【인스턴스 체계】                                            │
│     • 마스터 머티리얼과 인스턴스 분리                            │
│     • 파라미터 변경 시 재컴파일 불필요                           │
│     • 셰이더 코드 재사용으로 메모리 절약                         │
│                                                                 │
│  4. 【폴백 메커니즘】                                            │
│     • 컴파일 미완료 또는 오류 시 기본 머티리얼 사용              │
│     • 렌더링 중단 없이 시각적 피드백 제공                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### FMaterialRenderContext

`FMaterialRenderContext`는 `FMaterialRenderProxy`와 `FMaterial`을 바인딩하여, 렌더러가 두 객체의 속성에 동시에 접근할 수 있게 합니다:

```cpp
struct FMaterialRenderContext
{
    const FMaterialRenderProxy* MaterialRenderProxy;
    const FMaterial& Material;

    FMaterialRenderContext(
        const FMaterialRenderProxy* InMaterialRenderProxy,
        const FMaterial& InMaterial)
        : MaterialRenderProxy(InMaterialRenderProxy)
        , Material(InMaterial)
    {}
};
```

### 초기화 타임라인

| 단계 | 시점 | 생성되는 객체 |
|------|------|---------------|
| 1 | `PostInitProperties()` | `FMaterialRenderProxy` (FDefaultMaterialInstance 또는 FMaterialInstanceResource) |
| 2 | `PostLoad()` | `FMaterialResource` (FindOrCreateMaterialResource) |
| 3 | 첫 렌더링 | ShaderMap 로드 및 바인딩 |

### 데이터 흐름 요약

| 단계 | 게임 스레드 | 렌더 스레드 |
|------|------------|------------|
| 에셋 | UMaterial, UMaterialInstance | - |
| 프록시 | - | FMaterialRenderProxy |
| 셰이더 | FMaterialResource (GameThread) | FMaterialResource (RenderThread) |
| ShaderMap | GameThreadShaderMap | RenderingThreadShaderMap |
| 파라미터 | 파라미터 배열 (게임 스레드) | 파라미터 배열 (렌더 스레드) |

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/15109132.html)
- [UE 머티리얼 문서](https://docs.unrealengine.com/5.0/en-US/unreal-engine-materials/)
