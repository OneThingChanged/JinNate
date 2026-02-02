# 05. 머티리얼 개발

> 원문: [剖析虚幻渲染体系（09）- 材质体系](https://www.cnblogs.com/timlly/p/15109132.html)

머티리얼 노드 확장, 커스텀 노드 개발, 템플릿 확장, 본편 총결을 다룹니다.

---

## 9.5 머티리얼 개발

### 9.5.1 머티리얼 디버깅

머티리얼 디버깅에 유용한 콘솔 명령과 도구들입니다.

![머티리얼 디버깅](../images/ch10/1617944-20210806160655783-730781986.jpg)

#### 콘솔 명령

| 명령 | 설명 |
|------|------|
| `r.ShaderDevelopmentMode 1` | 셰이더 개발 모드 활성화 (상세 오류 출력) |
| `recompileshaders changed` | 변경된 셰이더만 재컴파일 |
| `recompileshaders material [name]` | 특정 머티리얼 재컴파일 |
| `recompileshaders all` | 모든 셰이더 재컴파일 |
| `r.DumpShaderDebugInfo 1` | 셰이더 디버그 정보 덤프 |
| `r.MaterialQualityLevel [0-2]` | 머티리얼 품질 레벨 변경 |

#### 셰이더 개발 모드

```cpp
// 셰이더 개발 모드 활성화 시:
// - 상세한 컴파일 오류 메시지
// - 셰이더 소스 코드 덤프
// - HLSL 중간 코드 출력
// - 컴파일 시간 프로파일링

// 콘솔에서:
r.ShaderDevelopmentMode 1

// C++에서:
static const auto CVarShaderDevelopmentMode =
    IConsoleManager::Get().FindTConsoleVariableDataInt(TEXT("r.ShaderDevelopmentMode"));
bool bShaderDevelopmentMode = CVarShaderDevelopmentMode && CVarShaderDevelopmentMode->GetValueOnAnyThread() != 0;
```

#### 머티리얼 통계

머티리얼 에디터의 Stats 창에서 확인 가능한 정보:

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 통계 정보                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【셰이더 명령어 수】                                            │
│    • Vertex Shader Instructions: XX                             │
│    • Pixel Shader Instructions: XX                              │
│                                                                 │
│  【텍스처 샘플러】                                               │
│    • Texture Samplers: X / 16                                   │
│    • Virtual Texture Samplers: X                                │
│                                                                 │
│  【머티리얼 속성】                                               │
│    • Interpolators: X                                           │
│    • Texture Lookups (Vertex): X                                │
│    • Texture Lookups (Pixel): X                                 │
│                                                                 │
│  【컴파일 시간】                                                 │
│    • Compile Time: X.XXs                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.5.2 머티리얼 노드 추가

새로운 머티리얼 표현식 노드를 추가하는 방법입니다.

![커스텀 노드 개발](../images/ch10/1617944-20210806160703361-409103979.jpg)

#### 기본 구조

```cpp
// 1. UMaterialExpression 서브클래스 생성
// MyProject/Source/MyProject/Private/Materials/MaterialExpressionMyCustomNode.h

#pragma once

#include "CoreMinimal.h"
#include "Materials/MaterialExpression.h"
#include "MaterialExpressionMyCustomNode.generated.h"

UCLASS(collapsecategories, hidecategories=Object)
class MYPROJECT_API UMaterialExpressionMyCustomNode : public UMaterialExpression
{
    GENERATED_UCLASS_BODY()

    // 입력 핀 A
    UPROPERTY()
    FExpressionInput A;

    // 입력 핀 B
    UPROPERTY()
    FExpressionInput B;

    // 프로퍼티: 기본 스케일 값
    UPROPERTY(EditAnywhere, Category = MaterialExpressionMyCustomNode)
    float DefaultScale = 1.0f;

public:
    // 컴파일 구현
    virtual int32 Compile(
        class FMaterialCompiler* Compiler,
        int32 OutputIndex
    ) override;

    // 에디터 표시명
    virtual void GetCaption(TArray<FString>& OutCaptions) const override;

    // 출력 타입
    virtual EMaterialValueType GetOutputType(int32 OutputIndex) override
    {
        return MCT_Float3;
    }

#if WITH_EDITOR
    // 입력 핀 정보
    virtual uint32 GetInputType(int32 InputIndex) override;
    virtual FName GetInputName(int32 InputIndex) const override;
#endif
};
```

#### 구현 파일

```cpp
// MyProject/Source/MyProject/Private/Materials/MaterialExpressionMyCustomNode.cpp

#include "Materials/MaterialExpressionMyCustomNode.h"
#include "MaterialCompiler.h"

UMaterialExpressionMyCustomNode::UMaterialExpressionMyCustomNode(
    const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer)
{
    // 에디터에서 표시될 카테고리
    struct FConstructorStatics
    {
        FText NAME_Custom;
        FConstructorStatics()
            : NAME_Custom(LOCTEXT("Custom", "Custom"))
        {}
    };
    static FConstructorStatics ConstructorStatics;

#if WITH_EDITORONLY_DATA
    MenuCategories.Add(ConstructorStatics.NAME_Custom);
#endif
}

int32 UMaterialExpressionMyCustomNode::Compile(
    FMaterialCompiler* Compiler,
    int32 OutputIndex)
{
    // A 입력 컴파일 (연결 안 되면 0)
    int32 ACode = A.GetTracedInput().Expression ?
        A.Compile(Compiler) :
        Compiler->Constant3(0, 0, 0);

    // B 입력 컴파일 (연결 안 되면 1)
    int32 BCode = B.GetTracedInput().Expression ?
        B.Compile(Compiler) :
        Compiler->Constant(1.0f);

    // 스케일 상수
    int32 ScaleCode = Compiler->Constant(DefaultScale);

    // 커스텀 연산: (A * B) * Scale
    int32 MulAB = Compiler->Mul(ACode, BCode);
    int32 Result = Compiler->Mul(MulAB, ScaleCode);

    return Result;
}

void UMaterialExpressionMyCustomNode::GetCaption(
    TArray<FString>& OutCaptions) const
{
    OutCaptions.Add(TEXT("My Custom Node"));
}

#if WITH_EDITOR
uint32 UMaterialExpressionMyCustomNode::GetInputType(int32 InputIndex)
{
    switch (InputIndex)
    {
    case 0: return MCT_Float3;  // A: Vector3
    case 1: return MCT_Float;   // B: Scalar
    default: return MCT_Unknown;
    }
}

FName UMaterialExpressionMyCustomNode::GetInputName(int32 InputIndex) const
{
    switch (InputIndex)
    {
    case 0: return TEXT("Color");
    case 1: return TEXT("Intensity");
    default: return NAME_None;
    }
}
#endif
```

---

### 9.5.3 커스텀 노드 확장

머티리얼 에디터의 Custom 노드를 사용하여 HLSL 코드를 직접 작성할 수 있습니다.

![Custom 노드](../images/ch10/1617944-20210806160711668-650030441.jpg)

#### Custom 노드 사용법

```
┌─────────────────────────────────────────────────────────────────┐
│                    Custom 노드 활용                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【머티리얼 에디터에서】                                         │
│                                                                 │
│  1. Custom 노드 추가 (우클릭 → Custom)                          │
│                                                                 │
│  2. Details 패널에서 설정:                                       │
│                                                                 │
│     Code:                                                        │
│     ┌─────────────────────────────────────────────────────┐     │
│     │ return saturate(dot(Normal, LightDir));             │     │
│     └─────────────────────────────────────────────────────┘     │
│                                                                 │
│     Output Type: CMOT_Float1                                    │
│                                                                 │
│  3. Inputs 배열에서 입력 핀 추가:                                │
│                                                                 │
│     [0] Name: Normal,   Type: Float3                            │
│     [1] Name: LightDir, Type: Float3                            │
│                                                                 │
│  4. Description: "N dot L 계산"                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Custom 노드 예시

**Fresnel 효과:**
```hlsl
// Code:
float NdotV = saturate(dot(Normal, CameraVector));
return pow(1.0 - NdotV, Exponent);

// Inputs:
// - Normal (Float3)
// - CameraVector (Float3)
// - Exponent (Float1)

// Output Type: CMOT_Float1
```

**Triplanar Mapping:**
```hlsl
// Code:
float3 blending = abs(Normal);
blending = normalize(max(blending, 0.00001));
blending /= (blending.x + blending.y + blending.z);

float4 xaxis = Texture2DSample(Tex, TexSampler, WorldPos.yz * Scale);
float4 yaxis = Texture2DSample(Tex, TexSampler, WorldPos.xz * Scale);
float4 zaxis = Texture2DSample(Tex, TexSampler, WorldPos.xy * Scale);

return xaxis * blending.x + yaxis * blending.y + zaxis * blending.z;

// Inputs:
// - Tex (Texture2D)
// - Normal (Float3)
// - WorldPos (Float3)
// - Scale (Float1)

// Output Type: CMOT_Float4
```

#### Include 파일 사용

Custom 노드에서 엔진 셰이더 함수를 사용할 수 있습니다:

```hlsl
// Include File Paths 설정:
// /Engine/Private/Common.ush

// Code에서 사용:
float3 result = TransformLocalToWorld(LocalPos);
return result;
```

---

### 9.5.4 머티리얼 템플릿 확장

`MaterialTemplate.ush`를 확장하여 새로운 기능을 추가하는 방법입니다.

![템플릿 확장](../images/ch10/1617944-20210806160718619-1742963402.jpg)

```
┌─────────────────────────────────────────────────────────────────┐
│                    템플릿 확장 흐름                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Engine/Shaders/Private/MaterialTemplate.ush 분석            │
│      │                                                          │
│      ▼                                                          │
│  2. 새로운 출력 핀 정의                                          │
│      │                                                          │
│      │   // MaterialTemplate.ush에 추가                         │
│      │   float3 MyCustomOutput;                                 │
│      │   %MY_CUSTOM_OUTPUT%                                      │
│      │                                                          │
│      ▼                                                          │
│  3. FHLSLMaterialTranslator에 처리 로직 추가                    │
│      │                                                          │
│      │   // HLSLMaterialTranslator.cpp                          │
│      │   case MP_MyCustomOutput:                                │
│      │       return Compiler->MyCustomOutput(...);              │
│      │                                                          │
│      ▼                                                          │
│  4. UMaterial에 새 속성 추가                                     │
│      │                                                          │
│      │   // Material.h                                          │
│      │   FColorMaterialInput MyCustomOutput;                    │
│      │                                                          │
│      ▼                                                          │
│  5. 머티리얼 에디터 UI 업데이트                                  │
│      │                                                          │
│      │   // MaterialEditor.cpp                                  │
│      │   AddInputPin(MP_MyCustomOutput, ...);                   │
│      │                                                          │
│      ▼                                                          │
│  6. 패스 셰이더에서 새 출력 사용                                 │
│      │                                                          │
│      │   // BasePassPixelShader.usf                             │
│      │   float3 customValue = GetMaterialMyCustomOutput(...);   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

### 9.5.5 머티리얼 최적화

머티리얼 성능 최적화를 위한 가이드라인입니다.

![머티리얼 최적화](../images/ch10/1617944-20210806160727756-1334230521.jpg)

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 최적화 가이드라인                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【명령어 수 최적화】                                            │
│                                                                 │
│  • 불필요한 노드 제거                                            │
│  • 상수 폴딩 활용 (Constant 노드 사용)                           │
│  • 복잡한 수학 대신 LUT(Lookup Table) 텍스처 사용               │
│                                                                 │
│  【텍스처 최적화】                                               │
│                                                                 │
│  • 텍스처 샘플러 수 최소화 (최대 16개)                          │
│  • 텍스처 패킹 (RGB 채널에 여러 데이터 저장)                    │
│  • 적절한 밉맵 사용                                              │
│  • Virtual Texture 활용                                         │
│                                                                 │
│  【인스턴스 활용】                                               │
│                                                                 │
│  • 마스터 머티리얼 + 인스턴스 구조                              │
│  • 정적 스위치로 불필요한 기능 제거                             │
│  • 파라미터 컬렉션으로 글로벌 파라미터 공유                     │
│                                                                 │
│  【품질 레벨 분기】                                              │
│                                                                 │
│  • Quality Switch 노드 활용                                     │
│  • 플랫폼별 최적화된 경로 제공                                   │
│  • 모바일용 단순화된 버전 제작                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 최적화 체크리스트

| 항목 | 권장 값 | 설명 |
|------|---------|------|
| Pixel Shader Instructions | < 200 | 픽셀 셰이더 명령어 수 |
| Texture Samplers | < 8 | 텍스처 샘플러 수 |
| Texture Lookups | < 10 | 텍스처 조회 수 |
| Interpolators | < 12 | 버텍스-픽셀 보간 변수 |

---

## 9.6 본편 총결

### 핵심 정리

![머티리얼 시스템 총정리](../images/ch10/1617944-20210806160737351-1351689524.jpg)

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 시스템 핵심 정리                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【클래스 계층】                                                 │
│                                                                 │
│  게임 스레드:                                                    │
│    UMaterialInterface                                            │
│        ├── UMaterial (마스터 머티리얼)                          │
│        │       └── DefaultMaterialInstance (FMaterialRenderProxy)│
│        │       └── MaterialResources[] (FMaterialResource)      │
│        │                                                        │
│        └── UMaterialInstance (파라미터 인스턴스)                │
│                ├── UMaterialInstanceConstant                    │
│                └── UMaterialInstanceDynamic                     │
│                └── Resource (FMaterialInstanceResource)         │
│                                                                 │
│  렌더 스레드:                                                    │
│    FMaterialRenderProxy                                          │
│        ├── FDefaultMaterialInstance                             │
│        └── FMaterialInstanceResource                            │
│                                                                 │
│    FMaterial                                                     │
│        └── FMaterialResource                                    │
│                └── GameThreadShaderMap                          │
│                └── RenderingThreadShaderMap                     │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【데이터 흐름】                                                 │
│                                                                 │
│  1. 에디터: 노드 그래프 편집 (UMaterialExpression 배열)         │
│      │                                                          │
│      ▼                                                          │
│  2. 컴파일: UMaterialExpression → FHLSLMaterialTranslator       │
│      │                                                          │
│      ▼                                                          │
│  3. 코드 생성: 노드별 Compile() → HLSL 코드 청크                │
│      │                                                          │
│      ▼                                                          │
│  4. 템플릿 삽입: MaterialTemplate.ush에 코드 삽입               │
│      │                                                          │
│      ▼                                                          │
│  5. 셰이더 컴파일: 패스별 셰이더 컴파일 (VS/PS/CS)              │
│      │                                                          │
│      ▼                                                          │
│  6. 캐싱: FMaterialShaderMap에 저장                              │
│      │                                                          │
│      ▼                                                          │
│  7. 렌더링: ShaderMap에서 셰이더 바인딩                          │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【설계 원칙】                                                   │
│                                                                 │
│  • 게임/렌더 스레드 분리로 멀티스레드 안전성 확보                 │
│  • 인스턴스 체계로 재컴파일 없이 파라미터 변경                   │
│  • 표현식 기반 컴파일로 노드 그래프를 HLSL로 변환                │
│  • 템플릿 시스템으로 일관된 셰이더 구조 유지                     │
│  • 폴백 메커니즘으로 렌더링 안정성 보장                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 학습 포인트

1. **UMaterial vs UMaterialInstance**
   - UMaterial: 마스터 머티리얼, 노드 그래프 포함, 셰이더 컴파일 필요
   - UMaterialInstance: 파라미터 오버라이드, 셰이더 재사용

2. **FMaterialRenderProxy**
   - 게임 스레드 → 렌더 스레드 데이터 전달
   - Uniform Expression 캐시 관리
   - 폴백 메커니즘 제공

3. **FMaterial/FMaterialResource**
   - 렌더링에 필요한 모든 데이터 관리
   - 듀얼 ShaderMap (GameThread/RenderingThread)
   - 셰이더 캐싱 및 접근 제공

4. **컴파일 흐름**
   - UMaterialExpression.Compile() → FMaterialCompiler 메서드 호출
   - FHLSLMaterialTranslator가 HLSL 코드 생성
   - MaterialTemplate.ush에 삽입 → 패스별 셰이더 컴파일

5. **ShaderMap**
   - FMaterialShaderMap: 컴파일된 셰이더 저장소
   - 패스별, VertexFactory별 셰이더 관리
   - 캐싱으로 재컴파일 최소화

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/15109132.html)
- [UE 머티리얼 문서](https://docs.unrealengine.com/5.0/en-US/unreal-engine-materials/)
- [UE 셰이더 개발 문서](https://docs.unrealengine.com/5.0/en-US/shader-development-in-unreal-engine/)
