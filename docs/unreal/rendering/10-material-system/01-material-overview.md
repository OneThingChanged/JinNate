# 01. 머티리얼 개요

UE 머티리얼의 기본 아키텍처, 클래스 구조, 핵심 속성을 분석합니다.

---

## 머티리얼 아키텍처

### 클래스 구조

```cpp
// 머티리얼 인터페이스 (추상 기본 클래스)
class UMaterialInterface : public UObject
{
public:
    // 렌더링에 사용할 리소스 얻기
    virtual UMaterial* GetMaterial() = 0;
    virtual FMaterialResource* GetMaterialResource(ERHIFeatureLevel::Type FeatureLevel) = 0;

    // 파라미터 접근
    virtual bool GetScalarParameterValue(FName Name, float& OutValue) const;
    virtual bool GetVectorParameterValue(FName Name, FLinearColor& OutValue) const;
    virtual bool GetTextureParameterValue(FName Name, UTexture*& OutValue) const;

    // 물리 머티리얼
    UPhysicalMaterial* GetPhysicalMaterial() const;
};

// 마스터 머티리얼
class UMaterial : public UMaterialInterface
{
public:
    // 머티리얼 도메인
    UPROPERTY()
    TEnumAsByte<EMaterialDomain> MaterialDomain;

    // 블렌드 모드
    UPROPERTY()
    TEnumAsByte<EBlendMode> BlendMode;

    // 셰이딩 모델
    UPROPERTY()
    TEnumAsByte<EMaterialShadingModel> ShadingModel;

    // 표현식 노드들
    UPROPERTY()
    TArray<TObjectPtr<UMaterialExpression>> Expressions;

    // 머티리얼 출력 핀
    UPROPERTY()
    FColorMaterialInput BaseColor;
    UPROPERTY()
    FScalarMaterialInput Metallic;
    UPROPERTY()
    FScalarMaterialInput Specular;
    UPROPERTY()
    FScalarMaterialInput Roughness;
    UPROPERTY()
    FScalarMaterialInput Anisotropy;
    UPROPERTY()
    FVectorMaterialInput EmissiveColor;
    UPROPERTY()
    FScalarMaterialInput Opacity;
    UPROPERTY()
    FScalarMaterialInput OpacityMask;
    UPROPERTY()
    FVectorMaterialInput Normal;
    UPROPERTY()
    FVectorMaterialInput WorldPositionOffset;

    // 컴파일된 셰이더 맵
    TMap<FMaterialShaderMapId, FMaterialShaderMap*> ShaderMaps;
};
```

### 머티리얼 리소스

```
┌─────────────────────────────────────────────────────────────────┐
│                    FMaterialResource 구조                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  UMaterial                                                      │
│      │                                                          │
│      └──→ FMaterialResource (Feature Level별)                   │
│               │                                                 │
│               ├── FMaterialShaderMap                            │
│               │       │                                         │
│               │       ├── FMeshMaterialShaderMap (VertexFactory별)│
│               │       │       │                                 │
│               │       │       ├── TBasePassPS<Policy>           │
│               │       │       ├── TDepthOnlyPS                  │
│               │       │       ├── TShadowDepthPS                │
│               │       │       └── ...                           │
│               │       │                                         │
│               │       └── FMaterialShaderType별 셰이더들          │
│               │                                                 │
│               ├── Uniform Expressions (상수 데이터)              │
│               │       ├── ScalarParameters                      │
│               │       ├── VectorParameters                      │
│               │       └── TextureParameters                     │
│               │                                                 │
│               └── Material Properties                           │
│                       ├── BlendMode                             │
│                       ├── ShadingModel                          │
│                       └── ...                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 머티리얼 도메인

### 도메인 정의

```cpp
// 머티리얼 도메인 열거형
UENUM()
enum EMaterialDomain : int
{
    MD_Surface        UMETA(DisplayName="Surface"),       // 일반 표면
    MD_DeferredDecal  UMETA(DisplayName="Deferred Decal"), // 디퍼드 데칼
    MD_LightFunction  UMETA(DisplayName="Light Function"), // 광원 함수
    MD_Volume         UMETA(DisplayName="Volume"),        // 볼륨
    MD_PostProcess    UMETA(DisplayName="Post Process"),  // 포스트 프로세스
    MD_UI             UMETA(DisplayName="User Interface"), // UI
    MD_RuntimeVirtualTexture UMETA(DisplayName="Runtime Virtual Texture"),
};
```

### 도메인별 출력

```
┌─────────────────────────────────────────────────────────────────┐
│                    도메인별 유효 출력                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Surface 도메인:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Base Color        ✓   │  Metallic            ✓         │   │
│  │  Specular          ✓   │  Roughness           ✓         │   │
│  │  Anisotropy        ✓   │  Emissive Color      ✓         │   │
│  │  Opacity           ✓   │  Opacity Mask        ✓         │   │
│  │  Normal            ✓   │  Tangent             ✓         │   │
│  │  World Pos Offset  ✓   │  Subsurface Color    ✓         │   │
│  │  Ambient Occlusion ✓   │  Refraction          ✓         │   │
│  │  Pixel Depth Offset✓   │  Shading Model ID    ✓         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Post Process 도메인:                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Emissive Color    ✓   (최종 출력 색상)                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Light Function 도메인:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Emissive Color    ✓   (스칼라 밝기로 사용)              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Deferred Decal 도메인:                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Decal Blend Mode에 따라 선택적 출력                     │   │
│  │  - Stain: Base Color만                                  │   │
│  │  - Normal: Normal만                                     │   │
│  │  - Emissive: Emissive만                                 │   │
│  │  - 조합 가능                                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 블렌드 모드

### 블렌드 모드 타입

```cpp
// 블렌드 모드 열거형
UENUM()
enum EBlendMode : int
{
    BLEND_Opaque        UMETA(DisplayName="Opaque"),
    BLEND_Masked        UMETA(DisplayName="Masked"),
    BLEND_Translucent   UMETA(DisplayName="Translucent"),
    BLEND_Additive      UMETA(DisplayName="Additive"),
    BLEND_Modulate      UMETA(DisplayName="Modulate"),
    BLEND_AlphaComposite UMETA(DisplayName="AlphaComposite"),
    BLEND_AlphaHoldout  UMETA(DisplayName="AlphaHoldout"),
};
```

### 블렌드 모드별 특성

```
┌─────────────────────────────────────────────────────────────────┐
│                    블렌드 모드 비교                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  모드           렌더링 방식      깊이 쓰기   정렬 필요   성능    │
│  ────────────  ──────────────  ──────────  ─────────  ──────  │
│  Opaque        디퍼드           O           X          최고    │
│  Masked        디퍼드 + 클립    O           X          높음    │
│  Translucent   포워드           X           O          낮음    │
│  Additive      포워드           X           X          중간    │
│  Modulate      포워드           X           X          중간    │
│                                                                 │
│  상세:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Opaque:                                                │   │
│  │  - G-Buffer에 직접 출력                                 │   │
│  │  - 디퍼드 라이팅 적용                                   │   │
│  │  - 가장 효율적                                          │   │
│  │                                                         │   │
│  │  Masked:                                                │   │
│  │  - Opacity Mask로 픽셀 버림 (clip)                      │   │
│  │  - 알파 테스트 사용                                     │   │
│  │  - 식물, 울타리 등                                      │   │
│  │                                                         │   │
│  │  Translucent:                                           │   │
│  │  - 포워드 렌더링                                        │   │
│  │  - 뒤에서 앞으로 정렬 필요                              │   │
│  │  - 유리, 물 등                                          │   │
│  │                                                         │   │
│  │  Additive:                                              │   │
│  │  - 색상 합산 (밝아짐)                                   │   │
│  │  - 정렬 불필요 (결합법칙)                               │   │
│  │  - 파티클, 글로우                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 셰이딩 모델

### 기본 셰이딩 모델

```cpp
// 셰이딩 모델 열거형
UENUM()
enum EMaterialShadingModel : int
{
    MSM_Unlit              UMETA(DisplayName="Unlit"),
    MSM_DefaultLit         UMETA(DisplayName="Default Lit"),
    MSM_Subsurface         UMETA(DisplayName="Subsurface"),
    MSM_PreintegratedSkin  UMETA(DisplayName="Preintegrated Skin"),
    MSM_ClearCoat          UMETA(DisplayName="Clear Coat"),
    MSM_SubsurfaceProfile  UMETA(DisplayName="Subsurface Profile"),
    MSM_TwoSidedFoliage    UMETA(DisplayName="Two Sided Foliage"),
    MSM_Hair               UMETA(DisplayName="Hair"),
    MSM_Cloth              UMETA(DisplayName="Cloth"),
    MSM_Eye                UMETA(DisplayName="Eye"),
    MSM_SingleLayerWater   UMETA(DisplayName="SingleLayerWater"),
    MSM_ThinTranslucent    UMETA(DisplayName="Thin Translucent"),
    MSM_Strata             UMETA(DisplayName="Strata"),
    MSM_FromMaterialExpression UMETA(DisplayName="From Material Expression"),
};
```

### 셰이딩 모델별 G-Buffer

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이딩 모델별 G-Buffer 사용                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  DefaultLit:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GBufferA: Normal.xyz, PerObjectData                    │   │
│  │  GBufferB: Metallic, Specular, Roughness, ShadingModel  │   │
│  │  GBufferC: BaseColor.rgb, AO                            │   │
│  │  GBufferD: CustomData (선택적)                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Subsurface/SubsurfaceProfile:                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GBufferD: SubsurfaceColor 또는 ProfileID               │   │
│  │  - 피하 산란 시뮬레이션                                  │   │
│  │  - 피부, 대리석, 왁스 등                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ClearCoat:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GBufferD: ClearCoat, ClearCoatRoughness                │   │
│  │  - 두 레이어 반사                                        │   │
│  │  - 자동차 도장, 코팅 표면                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Hair:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GBufferD: Tangent 방향                                  │   │
│  │  - 비등방성 반사 (Kajiya-Kay)                           │   │
│  │  - 머리카락, 털                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Cloth:                                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  GBufferD: FuzzColor                                    │   │
│  │  - 천 특유의 미세 섬유 반사                              │   │
│  │  - Ashikhmin 셰이딩                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 머티리얼 속성

### 렌더링 속성

```cpp
// 주요 렌더링 속성
class UMaterial
{
    // 양면 렌더링
    UPROPERTY()
    uint8 TwoSided : 1;

    // 디더드 LOD 전환
    UPROPERTY()
    uint8 DitheredLODTransition : 1;

    // 와이어프레임 모드
    UPROPERTY()
    uint8 Wireframe : 1;

    // 머티리얼 사용 플래그
    UPROPERTY()
    uint8 bUsedWithSkeletalMesh : 1;
    UPROPERTY()
    uint8 bUsedWithStaticLighting : 1;
    UPROPERTY()
    uint8 bUsedWithParticleSprites : 1;
    UPROPERTY()
    uint8 bUsedWithNiagaraSprites : 1;
    UPROPERTY()
    uint8 bUsedWithNiagaraMeshParticles : 1;
    UPROPERTY()
    uint8 bUsedWithVirtualHeightfieldMesh : 1;

    // 반투명 설정
    UPROPERTY()
    TEnumAsByte<ETranslucencyLightingMode> TranslucencyLightingMode;

    // 깊이 테스트 비활성화
    UPROPERTY()
    uint8 bDisableDepthTest : 1;

    // 포그 적용
    UPROPERTY()
    uint8 bUseTranslucencyVertexFog : 1;
};
```

### 사용 플래그

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 사용 플래그                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  플래그                       효과                              │
│  ─────────────────────────   ─────────────────────────────────│
│  Used with Skeletal Mesh     스켈레탈 메시용 셰이더 컴파일       │
│  Used with Static Lighting   라이트맵 샘플링 코드 포함          │
│  Used with Particle Sprites  파티클 스프라이트 버텍스 레이아웃   │
│  Used with Landscape         랜드스케이프 레이어 블렌딩          │
│  Used with Spline Meshes     스플라인 메시 변형 지원            │
│  Used with Instanced SM      인스턴싱 지원                      │
│  Used with Morph Targets     모프 타겟 버텍스 포맷              │
│  Used with Clothing          클로스 시뮬레이션 지원              │
│  Used with Nanite            Nanite 호환 셰이더                 │
│                                                                 │
│  주의:                                                          │
│  - 플래그가 많을수록 셰이더 순열 증가                           │
│  - 불필요한 플래그 = 컴파일 시간/메모리 낭비                    │
│  - "Automatically Set Usage..." 옵션으로 자동 설정 가능         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 머티리얼 출력 핀

### 출력 핀 연결

```cpp
// 머티리얼 입력 구조체
struct FMaterialInput
{
    // 연결된 표현식
    UMaterialExpression* Expression;

    // 출력 인덱스
    int32 OutputIndex;

    // 마스크 (어떤 채널 사용)
    int32 Mask;
    int32 MaskR, MaskG, MaskB, MaskA;
};

// 색상 입력
struct FColorMaterialInput : FMaterialInput
{
    // float3 또는 float4 출력
    uint8 UseConstant : 1;
    FColor Constant;  // 상수값 (표현식 없을 때)
};

// 스칼라 입력
struct FScalarMaterialInput : FMaterialInput
{
    uint8 UseConstant : 1;
    float Constant;
};

// 벡터 입력
struct FVectorMaterialInput : FMaterialInput
{
    uint8 UseConstant : 1;
    FVector3f Constant;
};
```

### 출력 핀 목록

```
┌────────────────────────────────────────────────────────────────┐
│                    Surface 도메인 출력 핀                       │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  핀 이름                타입      기본값    설명               │
│  ───────────────────   ─────────  ────────  ────────────────  │
│  Base Color            float3     (0,0,0)   표면 색상          │
│  Metallic              float      0         금속성 (0-1)       │
│  Specular              float      0.5       반사 강도 (0-1)    │
│  Roughness             float      0.5       거칠기 (0-1)       │
│  Anisotropy            float      0         비등방성 (-1~1)    │
│  Emissive Color        float3     (0,0,0)   발광 색상          │
│  Opacity               float      1         불투명도           │
│  Opacity Mask          float      1         마스크 값          │
│  Normal                float3     (0,0,1)   노멀 벡터          │
│  Tangent               float3     (1,0,0)   탄젠트 벡터        │
│  World Position Offset float3     (0,0,0)   버텍스 오프셋     │
│  Subsurface Color      float3     (1,1,1)   SSS 색상          │
│  Custom Data 0         float4     (0,0,0,0) 커스텀 데이터      │
│  Custom Data 1         float4     (0,0,0,0) 커스텀 데이터      │
│  Ambient Occlusion     float      1         앰비언트 오클루전  │
│  Refraction            float      1         굴절률             │
│  Pixel Depth Offset    float      0         깊이 오프셋        │
│  Shading Model ID      uint       0         셰이딩 모델 선택   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 요약

머티리얼 개요 핵심:

1. **클래스 구조** - UMaterial → FMaterialResource → ShaderMap
2. **도메인** - Surface, PostProcess, LightFunction 등 용도별 분류
3. **블렌드 모드** - Opaque/Masked (디퍼드), Translucent (포워드)
4. **셰이딩 모델** - DefaultLit, Subsurface, Hair, Cloth 등 표면 특성
5. **출력 핀** - BaseColor, Metallic, Roughness 등 PBR 파라미터

머티리얼은 노드 그래프로 정의되고, HLSL로 컴파일되어 GPU에서 실행됩니다.

---

## 참고 자료

- [UE Material Properties](https://docs.unrealengine.com/5.0/en-US/material-properties/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
