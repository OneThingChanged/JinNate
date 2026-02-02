# 03. 머티리얼 렌더링

> 원문: [剖析虚幻渲染体系（09）- 材质体系](https://www.cnblogs.com/timlly/p/15109132.html)

머티리얼 데이터 초기화, ShaderMap 전달, 렌더링 흐름을 상세히 분석합니다.

---

## 9.3 머티리얼 렌더링

### 9.3.1 머티리얼 데이터 흐름

머티리얼 렌더링에 필요한 데이터는 게임 스레드에서 렌더 스레드로 여러 단계를 거쳐 전달됩니다.

![머티리얼 데이터 흐름](../images/ch10/1617944-20210806160539506-774173291.jpg)

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 데이터 흐름                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【1. 에셋 로드】                                                │
│                                                                 │
│  .uasset (디스크)                                                │
│      │                                                          │
│      ▼                                                          │
│  UMaterial / UMaterialInstance (역직렬화)                        │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【2. 렌더 프록시 생성】                                         │
│                                                                 │
│  PostInitProperties() 호출                                       │
│      │                                                          │
│      ├── UMaterial                                              │
│      │       └── FDefaultMaterialInstance 생성                  │
│      │                                                          │
│      └── UMaterialInstance                                      │
│              └── FMaterialInstanceResource 생성                 │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【3. 머티리얼 리소스 생성】                                     │
│                                                                 │
│  PostLoad() 호출                                                 │
│      │                                                          │
│      ▼                                                          │
│  FindOrCreateMaterialResource()                                  │
│      │                                                          │
│      └── FMaterialResource 생성 (피처 레벨/품질별)              │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【4. ShaderMap 로드】                                           │
│                                                                 │
│  ProcessSerializedInlineShaderMaps()                             │
│      │                                                          │
│      └── SetInlineShaderMap()                                   │
│              │                                                  │
│              ├── GameThreadShaderMap 설정                       │
│              │                                                  │
│              └── ENQUEUE_RENDER_COMMAND                         │
│                      │                                          │
│                      └── RenderingThreadShaderMap 설정          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.3.2 FMaterialRenderProxy 생성 시점

`FMaterialRenderProxy`는 `PostInitProperties()` 단계에서 생성됩니다:

```cpp
// UMaterial::PostInitProperties()
void UMaterial::PostInitProperties()
{
    Super::PostInitProperties();

    if (!HasAnyFlags(RF_ClassDefaultObject))
    {
        // FDefaultMaterialInstance 생성
        DefaultMaterialInstance = new FDefaultMaterialInstance(this);
    }
}

// UMaterialInstance::PostInitProperties()
void UMaterialInstance::PostInitProperties()
{
    Super::PostInitProperties();

    if (!HasAnyFlags(RF_ClassDefaultObject))
    {
        // FMaterialInstanceResource 생성
        Resource = new FMaterialInstanceResource(this);
    }
}
```

### 생성 타임라인

| 단계 | 함수 | 생성되는 객체 | 설명 |
|------|------|---------------|------|
| 1 | `PostInitProperties()` | `FMaterialRenderProxy` | 렌더 프록시 (게임↔렌더 스레드 브릿지) |
| 2 | `PostLoad()` | `FMaterialResource` | 셰이더 리소스 (컴파일 결과물) |
| 3 | `ProcessSerializedInlineShaderMaps()` | ShaderMap 바인딩 | 쿠킹된 셰이더 로드 |

---

### 9.3.3 FMaterialResource 생성 시점

`FMaterialResource`는 여러 시점에서 생성될 수 있습니다:

```cpp
// 주요 생성 경로: UMaterial::PostLoad()
void UMaterial::PostLoad()
{
    Super::PostLoad();

    // 인라인 셰이더 맵 처리
    ProcessSerializedInlineShaderMaps(this, LoadedMaterialResources, LoadedMaterialResourceMap);

    // 피처 레벨별 머티리얼 리소스 생성
    for (int32 FeatureLevelIndex = 0; FeatureLevelIndex < ERHIFeatureLevel::Num; FeatureLevelIndex++)
    {
        ERHIFeatureLevel::Type FeatureLevel = (ERHIFeatureLevel::Type)FeatureLevelIndex;

        // 각 품질 레벨에 대해
        for (int32 QualityLevelIndex = 0; QualityLevelIndex < EMaterialQualityLevel::Num; QualityLevelIndex++)
        {
            EMaterialQualityLevel::Type QualityLevel = (EMaterialQualityLevel::Type)QualityLevelIndex;

            // 리소스 찾거나 생성
            FMaterialResource* Resource = FindOrCreateMaterialResource(FeatureLevel, QualityLevel);
        }
    }
}
```

### 생성 트리거

```
┌─────────────────────────────────────────────────────────────────┐
│                FMaterialResource 생성 트리거                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. UMaterial::PostLoad()                                        │
│     └── 에셋 로드 완료 시                                        │
│                                                                 │
│  2. UMaterial::CacheResourceShadersForRendering()               │
│     └── 셰이더 캐싱 요청 시                                      │
│                                                                 │
│  3. UMaterial::BeginCacheForCookedPlatformData()                │
│     └── 쿠킹 시작 시                                             │
│                                                                 │
│  4. UMaterial::SetMaterialUsage()                                │
│     └── 사용 플래그 변경 시 (예: 스켈레탈 메시 사용 설정)        │
│                                                                 │
│  5. FMaterialResource::CacheShaders()                           │
│     └── 명시적 셰이더 캐싱 시                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.3.4 ShaderMap 설정 메커니즘

ShaderMap은 게임 스레드에서 설정되고 렌더 스레드로 전파됩니다:

![ShaderMap 전파](../images/ch10/1617944-20210806160549309-1028989438.jpg)

```cpp
// FMaterial::SetGameThreadShaderMap() - 일반적인 설정 경로
void FMaterial::SetGameThreadShaderMap(FMaterialShaderMap* InShaderMap)
{
    checkSlow(IsInGameThread() || IsAsyncLoading());

    GameThreadShaderMap = InShaderMap;

    // 렌더 스레드로 비동기 전파
    FMaterial* Material = this;
    ENQUEUE_RENDER_COMMAND(SetShaderMap)(
        [Material, InShaderMap](FRHICommandListImmediate& RHICmdList)
        {
            Material->SetRenderingThreadShaderMap(InShaderMap);
        }
    );
}

// FMaterial::SetInlineShaderMap() - 쿠킹된 인라인 셰이더용
void FMaterial::SetInlineShaderMap(FMaterialShaderMap* InShaderMap)
{
    checkSlow(IsInGameThread() || IsAsyncLoading());

    GameThreadShaderMap = InShaderMap;
    bContainsInlineShaders = true;
    bLoadedCookedShaderMapId = true;

    // 렌더 스레드로 전파
    FMaterial* Material = this;
    ENQUEUE_RENDER_COMMAND(SetInlineShaderMap)(
        [Material, InShaderMap](FRHICommandListImmediate& RHICmdList)
        {
            Material->SetRenderingThreadShaderMap(InShaderMap);
        }
    );
}

// FMaterial::SetRenderingThreadShaderMap() - 렌더 스레드에서 호출
void FMaterial::SetRenderingThreadShaderMap(FMaterialShaderMap* InShaderMap)
{
    checkSlow(IsInRenderingThread());
    RenderingThreadShaderMap = InShaderMap;
}
```

### ShaderMap 설정 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                    ShaderMap 설정 흐름                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【쿠킹된 에셋 로드 (일반적 경로)】                              │
│                                                                 │
│  UMaterial::PostLoad()                                           │
│      │                                                          │
│      ▼                                                          │
│  ProcessSerializedInlineShaderMaps()                             │
│      │                                                          │
│      ▼                                                          │
│  FMaterial::SetInlineShaderMap(InShaderMap)                      │
│      │                                                          │
│      ├── GameThreadShaderMap = InShaderMap                      │
│      │                                                          │
│      └── ENQUEUE_RENDER_COMMAND                                 │
│              │                                                  │
│              ▼                                                  │
│          SetRenderingThreadShaderMap(InShaderMap)               │
│              │                                                  │
│              └── RenderingThreadShaderMap = InShaderMap         │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【에디터에서 컴파일 (개발 경로)】                               │
│                                                                 │
│  FMaterial::CacheShaders()                                       │
│      │                                                          │
│      ▼                                                          │
│  FMaterial::BeginCompileShaderMap()                              │
│      │                                                          │
│      ▼                                                          │
│  (비동기 컴파일 완료 후)                                         │
│      │                                                          │
│      ▼                                                          │
│  FMaterial::SetGameThreadShaderMap(CompiledShaderMap)           │
│      │                                                          │
│      └── (이하 동일)                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.3.5 렌더링 시점 데이터 접근

컴포넌트가 메시 배치를 수집할 때 머티리얼 데이터에 접근하는 과정:

![렌더링 시점 데이터 접근](../images/ch10/1617944-20210806160603315-1384351096.jpg)

```cpp
// FPrimitiveSceneProxy::GetDynamicMeshElements() 내부 흐름

void FStaticMeshSceneProxy::GetDynamicMeshElements(
    const TArray<const FSceneView*>& Views,
    const FSceneViewFamily& ViewFamily,
    uint32 VisibilityMap,
    FMeshElementCollector& Collector) const
{
    // 1. 머티리얼 인터페이스에서 렌더 프록시 획득
    const FMaterialRenderProxy* MaterialRenderProxy =
        MaterialInterface->GetRenderProxy();

    // 2. 폴백을 포함한 FMaterial 획득
    const FMaterialRenderProxy* FallbackProxy = nullptr;
    const FMaterial* Material = MaterialRenderProxy->GetMaterialWithFallback(
        ViewFamily.GetFeatureLevel(),
        FallbackProxy
    );

    // 3. 실제 사용할 프록시 결정
    const FMaterialRenderProxy* ActualProxy =
        FallbackProxy ? FallbackProxy : MaterialRenderProxy;

    // 4. 메시 배치에 프록시 설정
    FMeshBatch& Mesh = Collector.AllocateMesh();
    Mesh.MaterialRenderProxy = ActualProxy;

    // 5. ShaderMap에서 셰이더 획득
    FShader* VertexShader = Material->GetShader<FLocalVertexFactory>(
        &FLocalVertexFactory::StaticType
    );

    // ...
}
```

### 렌더링 데이터 접근 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                    렌더링 시점 데이터 접근                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FPrimitiveSceneProxy::GetDynamicMeshElements()                 │
│      │                                                          │
│      ▼                                                          │
│  UMaterialInterface::GetRenderProxy()                           │
│      │                                                          │
│      └── FMaterialRenderProxy* 획득                             │
│              │                                                  │
│              ▼                                                  │
│          GetMaterialWithFallback(FeatureLevel, OutFallback)     │
│              │                                                  │
│              ├── 성공: FMaterial* (FMaterialResource) 반환      │
│              │                                                  │
│              └── 실패: 기본 머티리얼 폴백 적용                  │
│                                                                 │
│  FMaterial*                                                      │
│      │                                                          │
│      ├── GetRenderingThreadShaderMap()                          │
│      │       └── FMaterialShaderMap* 반환                       │
│      │                                                          │
│      ├── GetShader<ShaderType>(VertexFactoryType)               │
│      │       └── FShader* 반환                                  │
│      │                                                          │
│      └── GetUniformExpressions()                                │
│              └── FUniformExpressionSet& 반환                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.3.6 폴백(Fallback) 메커니즘

머티리얼이 아직 준비되지 않은 경우(컴파일 중, 오류 등) 기본 머티리얼로 대체합니다:

```cpp
const FMaterial* FMaterialRenderProxy::GetMaterialWithFallback(
    ERHIFeatureLevel::Type FeatureLevel,
    const FMaterialRenderProxy*& OutFallbackProxy) const
{
    // 현재 프록시에서 머티리얼 획득 시도
    const FMaterial* Material = GetMaterialNoFallback(FeatureLevel);

    // 유효성 검사
    if (!Material || !Material->IsRenderingThreadShaderMapComplete())
    {
        // 폴백: 기본 Surface 머티리얼 사용
        UMaterial* DefaultMaterial = UMaterial::GetDefaultMaterial(MD_Surface);
        OutFallbackProxy = DefaultMaterial->GetRenderProxy();

        Material = OutFallbackProxy->GetMaterialNoFallback(FeatureLevel);

        // 기본 머티리얼도 실패하면 최종 폴백
        if (!Material || !Material->IsRenderingThreadShaderMapComplete())
        {
            OutFallbackProxy = GEngine->WireframeMaterial->GetRenderProxy();
            Material = OutFallbackProxy->GetMaterialNoFallback(FeatureLevel);
        }
    }

    return Material;
}
```

### 폴백 계층

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 폴백 계층                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  시도 1: 요청된 머티리얼                                         │
│      │                                                          │
│      └── 실패 시 ─────────────────────────────────────┐         │
│                                                       ▼         │
│  시도 2: GetDefaultMaterial(MD_Surface)                         │
│          └── WorldGridMaterial (회색 체크무늬)                  │
│              │                                                  │
│              └── 실패 시 ─────────────────────────────┐         │
│                                                       ▼         │
│  시도 3: WireframeMaterial                                      │
│          └── 와이어프레임 렌더링                                │
│                                                                 │
│  ※ 폴백으로 렌더링 중단 방지 및 시각적 피드백 제공              │
│  ※ 에디터에서 컴파일 중인 머티리얼은 체크무늬로 표시            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.3.7 FMaterialShaderMap

`FMaterialShaderMap`은 머티리얼에 대해 컴파일된 모든 셰이더를 저장하는 컨테이너입니다:

```cpp
class FMaterialShaderMap : public TShaderMap<FMaterialShaderMapContent>
{
    // 셰이더 맵 식별자
    FMaterialShaderMapId ShaderMapId;

    // 이 셰이더 맵을 사용하는 머티리얼들
    TArray<FMaterial*> CompilingMaterialArray;

    // 플랫폼
    EShaderPlatform Platform;

public:
    // 셰이더 획득
    FShader* GetShader(FShaderType* ShaderType, FVertexFactoryType* VertexFactoryType) const;

    // 완료 여부 확인
    bool IsComplete(const FMaterial* Material, bool bSilent) const;

    // 셰이더 파이프라인 획득
    FShaderPipeline* GetShaderPipeline(const FShaderPipelineType* ShaderPipelineType,
                                        FVertexFactoryType* VertexFactoryType) const;
};
```

### ShaderMap 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMaterialShaderMap 구조                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FMaterialShaderMap                                              │
│      │                                                          │
│      ├── ShaderMapId (식별자)                                   │
│      │       ├── StaticParameterSetHash                         │
│      │       ├── BaseMaterialId                                 │
│      │       └── QualityLevel, FeatureLevel                     │
│      │                                                          │
│      ├── Shaders (셰이더 컬렉션)                                │
│      │       ├── [BasePassVS] ────→ FShader*                    │
│      │       ├── [BasePassPS] ────→ FShader*                    │
│      │       ├── [DepthOnlyVS] ───→ FShader*                    │
│      │       ├── [DepthOnlyPS] ───→ FShader*                    │
│      │       ├── [ShadowDepthVS] ─→ FShader*                    │
│      │       └── ...                                            │
│      │                                                          │
│      └── ShaderPipelines (파이프라인)                           │
│              ├── [BasePass Pipeline]                            │
│              ├── [Shadow Pipeline]                              │
│              └── ...                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/15109132.html)
- [UE 머티리얼 문서](https://docs.unrealengine.com/5.0/en-US/unreal-engine-materials/)
