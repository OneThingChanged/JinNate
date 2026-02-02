# 01. 머티리얼 기초 (상)

> 원문: [剖析虚幻渲染体系（09）- 材质体系](https://www.cnblogs.com/timlly/p/15109132.html)

UMaterialInterface, UMaterial, UMaterialInstance의 정의와 관계를 상세히 분석합니다.

---

## 9.2 머티리얼 기초

언리얼의 머티리얼 시스템은 게임 스레드와 렌더 스레드로 나뉘어 설계되어 있습니다. 게임 스레드에서는 `UMaterialInterface`를 기반으로 한 클래스들이, 렌더 스레드에서는 `FMaterialRenderProxy`와 `FMaterial`을 기반으로 한 클래스들이 사용됩니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 시스템 계층 구조                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【게임 스레드 (Game Thread)】                                   │
│                                                                 │
│      UMaterialInterface (추상 기반 클래스)                       │
│              │                                                  │
│              ├── UMaterial (마스터 머티리얼)                     │
│              │                                                  │
│              └── UMaterialInstance (파라미터 인스턴스)           │
│                      │                                          │
│                      ├── UMaterialInstanceConstant              │
│                      │                                          │
│                      └── UMaterialInstanceDynamic               │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【렌더 스레드 (Render Thread)】                                 │
│                                                                 │
│      FMaterialRenderProxy (추상 기반 클래스)                     │
│              │                                                  │
│              ├── FDefaultMaterialInstance (UMaterial용)         │
│              │                                                  │
│              └── FMaterialInstanceResource (UMaterialInstance용)│
│                                                                 │
│      FMaterial (추상 기반 클래스)                                │
│              │                                                  │
│              └── FMaterialResource (구현 클래스)                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.2.1 UMaterialInterface

`UMaterialInterface`는 언리얼 머티리얼 시스템의 최상위 추상 클래스로, 모든 머티리얼 타입의 기반이 됩니다.

### 클래스 정의

```cpp
// Engine/Source/Runtime/Engine/Classes/Materials/MaterialInterface.h

class UMaterialInterface : public UObject, public IBlendableInterface
{
    GENERATED_UCLASS_BODY()

protected:
    // 서브서피스 프로파일 설정
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = Material)
    USubsurfaceProfile* SubsurfaceProfile;

private:
    // Lightmass 머티리얼 설정
    UPROPERTY(EditAnywhere, Category = Lightmass)
    FLightmassMaterialInterfaceSettings LightmassSettings;

    // 사용자 정의 에셋 데이터
    UPROPERTY(EditAnywhere, AdvancedDisplay, Instanced, Category = Material)
    TArray<UAssetUserData*> AssetUserData;

protected:
    // 텍스처 스트리밍 데이터
    UPROPERTY()
    TArray<FMaterialTextureInfo> TextureStreamingData;

public:
    // 주요 인터페이스 메서드
    virtual UMaterial* GetMaterial() PURE_VIRTUAL(...);
    virtual const UMaterial* GetMaterial_Concurrent(...) const PURE_VIRTUAL(...);
    virtual FMaterialResource* GetMaterialResource(...) PURE_VIRTUAL(...);
    virtual FMaterialRenderProxy* GetRenderProxy() const PURE_VIRTUAL(...);
    virtual UPhysicalMaterial* GetPhysicalMaterial() const PURE_VIRTUAL(...);

    // 파라미터 접근 메서드
    virtual bool GetScalarParameterValue(...) const PURE_VIRTUAL(...);
    virtual bool GetVectorParameterValue(...) const PURE_VIRTUAL(...);
    virtual bool GetTextureParameterValue(...) const PURE_VIRTUAL(...);
    virtual bool GetFontParameterValue(...) const PURE_VIRTUAL(...);

    // 텍스처 정보
    virtual void GetUsedTextures(...) const PURE_VIRTUAL(...);
    virtual void GetUsedTexturesAndIndices(...) const;
};
```

### 주요 멤버 변수

| 멤버 | 타입 | 설명 |
|------|------|------|
| `SubsurfaceProfile` | `USubsurfaceProfile*` | 서브서피스 스캐터링 설정 |
| `LightmassSettings` | `FLightmassMaterialInterfaceSettings` | 오프라인 GI 설정 |
| `AssetUserData` | `TArray<UAssetUserData*>` | 사용자 정의 데이터 저장소 |
| `TextureStreamingData` | `TArray<FMaterialTextureInfo>` | 텍스처 스트리밍 메타데이터 |

---

## 9.2.2 UMaterial

`UMaterial`은 머티리얼 에디터에서 생성되는 실제 머티리얼 에셋으로, `.uasset` 파일에 저장됩니다. 머티리얼 그래프의 노드와 연결, 그리고 모든 속성들을 포함합니다.

![UMaterial 에디터 인터페이스](../images/ch10/1617944-20210806160425033-2089277002.jpg)

### 클래스 정의

```cpp
// Engine/Source/Runtime/Engine/Classes/Materials/Material.h

class UMaterial : public UMaterialInterface
{
    GENERATED_UCLASS_BODY()

    // 물리 머티리얼 참조
    UPROPERTY(EditAnywhere, Category = PhysicalMaterial)
    UPhysicalMaterial* PhysMaterial;

    // 머티리얼 도메인 (Surface, Deferred Decal, Light Function, ...)
    UPROPERTY(EditAnywhere, Category = Material)
    TEnumAsByte<EMaterialDomain> MaterialDomain;

    // 블렌드 모드 (Opaque, Masked, Translucent, ...)
    UPROPERTY(EditAnywhere, Category = Material)
    TEnumAsByte<EBlendMode> BlendMode;

    // 음영 모델 (Default Lit, Unlit, Subsurface, ...)
    UPROPERTY(EditAnywhere, Category = Material)
    TEnumAsByte<EMaterialShadingModel> ShadingModel;

    // 투명도 관련 설정
    UPROPERTY(EditAnywhere, Category = Translucency)
    float OpacityMaskClipValue;

    // 양면 렌더링
    UPROPERTY(EditAnywhere, Category = Material)
    uint8 TwoSided : 1;

    // Dithered LOD 전환
    UPROPERTY(EditAnywhere, Category = Material, AdvancedDisplay)
    uint8 DitheredLODTransition : 1;

    // 다양한 머티리얼 플래그들...
    UPROPERTY()
    uint8 bUsedAsSpecialEngineMaterial : 1;

    UPROPERTY()
    uint8 bUsedWithSkeletalMesh : 1;

    UPROPERTY()
    uint8 bUsedWithParticleSprites : 1;

    // ... 더 많은 사용처 플래그들

private:
    // 렌더링 리소스 (피처 레벨 및 품질별)
    TArray<FMaterialResource*> MaterialResources;

    // 기본 렌더 프록시 인스턴스
    FDefaultMaterialInstance* DefaultMaterialInstance;

public:
    // 머티리얼 표현식 (노드들)
    UPROPERTY()
    TArray<UMaterialExpression*> Expressions;

    // 머티리얼 함수 정보
    UPROPERTY()
    TArray<FMaterialFunctionInfo> MaterialFunctionInfos;

    // 파라미터 컬렉션 정보
    UPROPERTY()
    TArray<FMaterialParameterCollectionInfo> MaterialParameterCollectionInfos;
};
```

### 머티리얼 속성 패널

머티리얼 에디터의 Details 패널에서 설정할 수 있는 주요 속성들:

![머티리얼 속성 패널](../images/ch10/1617944-20210806160439021-539785201.jpg)

### 주요 속성 설명

```
┌─────────────────────────────────────────────────────────────────┐
│                    UMaterial 주요 속성                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【Material Domain】                                            │
│    ├── Surface        : 일반 메시 표면                          │
│    ├── Deferred Decal : 디퍼드 데칼                             │
│    ├── Light Function : 라이트 함수                             │
│    ├── Volume         : 볼류메트릭                               │
│    ├── Post Process   : 포스트 프로세스                         │
│    └── UI             : 위젯/UI                                 │
│                                                                 │
│  【Blend Mode】                                                 │
│    ├── Opaque         : 불투명                                  │
│    ├── Masked         : 알파 마스크                             │
│    ├── Translucent    : 반투명                                  │
│    ├── Additive       : 가산 블렌딩                             │
│    └── Modulate       : 곱셈 블렌딩                             │
│                                                                 │
│  【Shading Model】                                              │
│    ├── Default Lit    : 기본 조명                               │
│    ├── Unlit          : 조명 없음                               │
│    ├── Subsurface     : 서브서피스 스캐터링                     │
│    ├── Preintegrated Skin : 사전 적분 피부                      │
│    ├── Clear Coat     : 클리어 코트                             │
│    ├── Subsurface Profile : 프로파일 기반 서브서피스           │
│    ├── Two Sided Foliage : 양면 폴리지                          │
│    ├── Hair           : 헤어                                    │
│    ├── Cloth          : 천                                      │
│    ├── Eye            : 눈                                      │
│    └── Single Layer Water : 단층 수면                           │
│                                                                 │
│  【Usage Flags】                                                │
│    ├── bUsedWithSkeletalMesh      : 스켈레탈 메시 사용          │
│    ├── bUsedWithParticleSprites   : 파티클 사용                 │
│    ├── bUsedWithStaticLighting    : 정적 라이팅 사용            │
│    ├── bUsedWithMorphTargets      : 모프 타겟 사용              │
│    ├── bUsedWithSplineMeshes      : 스플라인 메시 사용          │
│    ├── bUsedWithInstancedStaticMeshes : 인스턴스 메시 사용      │
│    └── ... (더 많은 플래그)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 머티리얼 표현식 (Material Expressions)

`UMaterial`은 머티리얼 그래프의 모든 노드들을 `Expressions` 배열에 저장합니다:

```cpp
// 각 노드는 UMaterialExpression의 서브클래스
TArray<UMaterialExpression*> Expressions;

// 예시 표현식 타입들:
// - UMaterialExpressionTextureSample
// - UMaterialExpressionMultiply
// - UMaterialExpressionAdd
// - UMaterialExpressionLerp
// - UMaterialExpressionScalarParameter
// - UMaterialExpressionVectorParameter
// - UMaterialExpressionTextureParameter
// ...
```

---

## 9.2.3 UMaterialInstance

`UMaterialInstance`는 부모 머티리얼의 파라미터를 재정의할 수 있는 인스턴스입니다. 셰이더를 재컴파일하지 않고도 텍스처, 색상, 스칼라 값 등을 변경할 수 있습니다.

### 핵심 특징

```
┌─────────────────────────────────────────────────────────────────┐
│                    UMaterialInstance 특징                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 독립적으로 존재할 수 없음                                    │
│     └── 반드시 부모 머티리얼(UMaterialInterface)이 필요          │
│                                                                 │
│  2. 계층 구조 형성 가능                                          │
│     └── 인스턴스의 인스턴스 생성 가능                            │
│     └── 최종 루트는 반드시 UMaterial                             │
│                                                                 │
│  3. 파라미터만 재정의 가능                                       │
│     └── Scalar, Vector, Texture, Font 파라미터                  │
│     └── 머티리얼 속성(Blend Mode 등)은 변경 불가                 │
│                                                                 │
│  4. 셰이더 재컴파일 없음                                         │
│     └── 파라미터 변경 시 기존 셰이더 재사용                      │
│     └── 빠른 이터레이션 가능                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 클래스 정의

```cpp
// Engine/Source/Runtime/Engine/Classes/Materials/MaterialInstance.h

class UMaterialInstance : public UMaterialInterface
{
    GENERATED_UCLASS_BODY()

public:
    // 부모 머티리얼 인터페이스 (필수)
    UPROPERTY(EditAnywhere, Category = MaterialInstance)
    UMaterialInterface* Parent;

    // 오버라이드된 스칼라 파라미터들
    UPROPERTY(EditAnywhere, Category = MaterialInstance)
    TArray<FScalarParameterValue> ScalarParameterValues;

    // 오버라이드된 벡터 파라미터들
    UPROPERTY(EditAnywhere, Category = MaterialInstance)
    TArray<FVectorParameterValue> VectorParameterValues;

    // 오버라이드된 텍스처 파라미터들
    UPROPERTY(EditAnywhere, Category = MaterialInstance)
    TArray<FTextureParameterValue> TextureParameterValues;

    // 오버라이드된 폰트 파라미터들
    UPROPERTY(EditAnywhere, Category = MaterialInstance)
    TArray<FFontParameterValue> FontParameterValues;

    // 오버라이드 가능한 기본 속성들
    UPROPERTY(EditAnywhere, Category = MaterialInstance)
    uint8 bOverrideSubsurfaceProfile : 1;

private:
    // 렌더 프록시 리소스
    FMaterialInstanceResource* Resource;

public:
    // 베이스 속성 오버라이드
    UPROPERTY(EditAnywhere, Category = MaterialInstance)
    FMaterialInstanceBasePropertyOverrides BasePropertyOverrides;
};
```

### 파라미터 값 구조체

```cpp
// 스칼라 파라미터
USTRUCT()
struct FScalarParameterValue
{
    UPROPERTY(EditAnywhere)
    FMaterialParameterInfo ParameterInfo;  // 파라미터 이름 및 연관 정보

    UPROPERTY(EditAnywhere)
    float ParameterValue;  // 스칼라 값
};

// 벡터 파라미터
USTRUCT()
struct FVectorParameterValue
{
    UPROPERTY(EditAnywhere)
    FMaterialParameterInfo ParameterInfo;

    UPROPERTY(EditAnywhere)
    FLinearColor ParameterValue;  // RGBA 색상 값
};

// 텍스처 파라미터
USTRUCT()
struct FTextureParameterValue
{
    UPROPERTY(EditAnywhere)
    FMaterialParameterInfo ParameterInfo;

    UPROPERTY(EditAnywhere)
    UTexture* ParameterValue;  // 텍스처 에셋 참조
};
```

### 머티리얼 인스턴스 계층 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 인스턴스 계층                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                     UMaterial (Root)                            │
│                     "M_Character_Base"                          │
│                           │                                     │
│              ┌────────────┼────────────┐                        │
│              │            │            │                        │
│              ▼            ▼            ▼                        │
│     MI_Character    MI_Character   MI_Character                 │
│       _Skin_A        _Skin_B        _Cloth                      │
│           │              │              │                       │
│           │              │         ┌────┴────┐                  │
│           ▼              ▼         ▼         ▼                  │
│     MI_Skin_A       MI_Skin_B   MI_Cloth  MI_Cloth              │
│       _Damage        _Wet        _Red      _Blue                │
│                                                                 │
│  * 모든 인스턴스는 궁극적으로 UMaterial에서 파생                 │
│  * 인스턴스는 부모의 파라미터만 오버라이드 가능                  │
│  * 셰이더 코드는 루트 UMaterial에서만 컴파일됨                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.2.4 UMaterialInstanceConstant

`UMaterialInstanceConstant`는 에디터에서 생성되어 쿠킹 시 한 번 컴파일되는 정적 인스턴스입니다.

![MaterialInstanceConstant 에디터](../images/ch10/1617944-20210806160447383-1290871477.jpg)

### 특징

```cpp
// Engine/Source/Runtime/Engine/Classes/Materials/MaterialInstanceConstant.h

class UMaterialInstanceConstant : public UMaterialInstance
{
    GENERATED_UCLASS_BODY()

    // 에디터 전용: 파라미터 상태 오버라이드 정보
    UPROPERTY()
    TArray<FGuid> ParameterStateId;

public:
    // 정적 파라미터 값들
    UPROPERTY()
    FStaticParameterSet StaticParameters;
};
```

```
┌─────────────────────────────────────────────────────────────────┐
│                UMaterialInstanceConstant 특징                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【장점】                                                        │
│    • 쿠킹 시 최적화된 형태로 저장                                │
│    • 런타임 오버헤드 최소화                                      │
│    • 정적 스위치 파라미터 지원                                   │
│                                                                 │
│  【단점】                                                        │
│    • 런타임에 파라미터 변경 불가                                 │
│    • 정적 파라미터 변경 시 재컴파일 필요                         │
│                                                                 │
│  【사용 시나리오】                                               │
│    • 캐릭터 스킨 배리에이션                                      │
│    • 환경 에셋 색상 변형                                         │
│    • 미리 정의된 머티리얼 프리셋                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.2.5 UMaterialInstanceDynamic

`UMaterialInstanceDynamic`은 런타임에 생성되어 동적으로 파라미터를 변경할 수 있는 인스턴스입니다.

### 클래스 정의 및 사용법

```cpp
// Engine/Source/Runtime/Engine/Classes/Materials/MaterialInstanceDynamic.h

class UMaterialInstanceDynamic : public UMaterialInstance
{
    GENERATED_UCLASS_BODY()

public:
    // 생성 메서드 (부모 머티리얼 필수)
    static UMaterialInstanceDynamic* Create(
        UMaterialInterface* ParentMaterial,
        UObject* InOuter
    );

    static UMaterialInstanceDynamic* Create(
        UMaterialInterface* ParentMaterial,
        UObject* InOuter,
        FName Name
    );

    // 스칼라 파라미터 설정
    UFUNCTION(BlueprintCallable, Category = "Material")
    void SetScalarParameterValue(FName ParameterName, float Value);

    // 벡터 파라미터 설정
    UFUNCTION(BlueprintCallable, Category = "Material")
    void SetVectorParameterValue(FName ParameterName, FLinearColor Value);

    // 텍스처 파라미터 설정
    UFUNCTION(BlueprintCallable, Category = "Material")
    void SetTextureParameterValue(FName ParameterName, UTexture* Value);

    // 파라미터 값 가져오기
    UFUNCTION(BlueprintCallable, Category = "Material")
    float GetScalarParameterValue(FName ParameterName);

    UFUNCTION(BlueprintCallable, Category = "Material")
    FLinearColor GetVectorParameterValue(FName ParameterName);

    UFUNCTION(BlueprintCallable, Category = "Material")
    UTexture* GetTextureParameterValue(FName ParameterName);

    // 부모 머티리얼의 모든 파라미터를 기본값으로 복사
    UFUNCTION(BlueprintCallable, Category = "Material")
    void CopyMaterialInstanceParameters(UMaterialInterface* Source);
};
```

### 사용 예시

```cpp
// C++ 사용 예시
void AMyActor::BeginPlay()
{
    Super::BeginPlay();

    // 메시 컴포넌트에서 머티리얼 가져오기
    UMaterialInterface* BaseMaterial = MeshComponent->GetMaterial(0);

    // 동적 인스턴스 생성
    UMaterialInstanceDynamic* DynamicMaterial =
        UMaterialInstanceDynamic::Create(BaseMaterial, this);

    // 파라미터 설정
    DynamicMaterial->SetVectorParameterValue("BaseColor", FLinearColor::Red);
    DynamicMaterial->SetScalarParameterValue("Roughness", 0.5f);

    // 메시에 적용
    MeshComponent->SetMaterial(0, DynamicMaterial);
}

void AMyActor::Tick(float DeltaTime)
{
    Super::Tick(DeltaTime);

    // 런타임에 파라미터 변경
    float PulseValue = FMath::Sin(GetWorld()->GetTimeSeconds()) * 0.5f + 0.5f;
    DynamicMaterial->SetScalarParameterValue("EmissiveIntensity", PulseValue);
}
```

```
┌─────────────────────────────────────────────────────────────────┐
│               UMaterialInstanceDynamic 특징                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【장점】                                                        │
│    • 런타임에 파라미터 자유롭게 변경 가능                        │
│    • 블루프린트에서 직접 사용 가능                               │
│    • 프로시저럴 이펙트 구현에 적합                               │
│                                                                 │
│  【단점】                                                        │
│    • 인스턴스마다 추가 메모리 사용                               │
│    • 파라미터 변경 시 Uniform Buffer 업데이트 비용               │
│    • 쿠킹/저장 불가 (런타임 전용)                                │
│                                                                 │
│  【사용 시나리오】                                               │
│    • 캐릭터 데미지 표현 (피격 시 색상 변경)                      │
│    • 히트 플래시 효과                                            │
│    • 인터랙티브 환경 (조명에 따른 색상 변화)                     │
│    • 프로시저럴 애니메이션 (파동, 물결 등)                       │
│    • UI 머티리얼 동적 제어                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## UMaterial vs UMaterialInstance 비교

| 항목 | UMaterial | UMaterialInstance |
|------|-----------|-------------------|
| **그래프 편집** | 가능 | 불가능 |
| **노드 추가** | 가능 | 불가능 |
| **파라미터 변경** | 가능 | 가능 (부모 파라미터만) |
| **블렌드 모드 변경** | 가능 | 불가능 |
| **셰이딩 모델 변경** | 가능 | 불가능 |
| **셰이더 컴파일** | 필요 | 불필요 |
| **독립 존재** | 가능 | 불가능 (부모 필요) |
| **에디터 생성** | 가능 | Constant만 가능 |
| **런타임 생성** | 불가능 | Dynamic만 가능 |

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/15109132.html)
- [UE 머티리얼 문서](https://docs.unrealengine.com/5.0/en-US/unreal-engine-materials/)
