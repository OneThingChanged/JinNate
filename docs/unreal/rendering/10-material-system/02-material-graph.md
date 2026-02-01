# 02. 머티리얼 그래프

노드 기반 머티리얼 에디터의 구조, 표현식 타입, 연결 시스템을 분석합니다.

---

## 노드 그래프 개요

### 머티리얼 에디터 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 에디터 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                     노드 그래프                          │   │
│  │                                                         │   │
│  │   ┌──────────┐   ┌──────────┐   ┌──────────┐           │   │
│  │   │ Texture  │──→│ Multiply │──→│          │           │   │
│  │   │ Sample   │   │    ×     │   │          │           │   │
│  │   └──────────┘   └──────────┘   │          │           │   │
│  │                        ↑        │  Result  │           │   │
│  │   ┌──────────┐        │        │   Node   │           │   │
│  │   │ Constant │────────┘        │          │           │   │
│  │   │   0.5    │                 │ BaseColor│           │   │
│  │   └──────────┘                 │ Roughness│           │   │
│  │                                │ Normal   │           │   │
│  │   ┌──────────┐   ┌──────────┐ │ ...      │           │   │
│  │   │ Texture  │──→│  Normal  │─→│          │           │   │
│  │   │ Sample   │   │ Unpack   │  │          │           │   │
│  │   └──────────┘   └──────────┘  └──────────┘           │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  노드 = UMaterialExpression                                    │
│  연결 = 입력/출력 핀 링크                                       │
│  결과 = 머티리얼 출력 핀으로 연결                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 표현식 기본 클래스

```cpp
// 머티리얼 표현식 기본 클래스
class UMaterialExpression : public UObject
{
public:
    // 에디터 위치
    UPROPERTY()
    int32 MaterialExpressionEditorX;
    UPROPERTY()
    int32 MaterialExpressionEditorY;

    // 설명 텍스트
    UPROPERTY()
    FString Desc;

    // 출력 핀 이름
    TArray<FExpressionOutput> Outputs;

    // 컴파일 (HLSL 코드 생성)
    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex);

    // 미리보기 값 계산
    virtual void GetCaption(TArray<FString>& OutCaptions) const;

    // 입력 핀 정보
    virtual TArray<FExpressionInput*> GetInputs();

    // 출력 타입
    virtual uint32 GetOutputType(int32 OutputIndex);
};

// 표현식 입력
struct FExpressionInput
{
    UMaterialExpression* Expression;  // 연결된 표현식
    int32 OutputIndex;                 // 출력 핀 인덱스
    FName InputName;                   // 입력 이름
    int32 Mask;                        // 채널 마스크
    int32 MaskR, MaskG, MaskB, MaskA;
};

// 표현식 출력
struct FExpressionOutput
{
    FName OutputName;
    int32 Mask;
    int32 MaskR, MaskG, MaskB, MaskA;
};
```

---

## 표현식 타입

### 상수 표현식

```cpp
// 스칼라 상수
class UMaterialExpressionConstant : public UMaterialExpression
{
    UPROPERTY()
    float R;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->Constant(R);
    }
};

// 2D 벡터 상수
class UMaterialExpressionConstant2Vector : public UMaterialExpression
{
    UPROPERTY()
    float R;
    UPROPERTY()
    float G;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->Constant2(R, G);
    }
};

// 3D 벡터 상수
class UMaterialExpressionConstant3Vector : public UMaterialExpression
{
    UPROPERTY()
    FLinearColor Constant;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->Constant3(Constant.R, Constant.G, Constant.B);
    }
};

// 4D 벡터 상수
class UMaterialExpressionConstant4Vector : public UMaterialExpression
{
    UPROPERTY()
    FLinearColor Constant;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->Constant4(Constant.R, Constant.G, Constant.B, Constant.A);
    }
};
```

### 텍스처 표현식

```cpp
// 텍스처 샘플
class UMaterialExpressionTextureSample : public UMaterialExpressionTextureBase
{
    UPROPERTY()
    FExpressionInput Coordinates;  // UV 입력

    UPROPERTY()
    TEnumAsByte<ESamplerSourceMode> SamplerSource;

    UPROPERTY()
    TEnumAsByte<ETextureMipValueMode> MipValueMode;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        // UV 좌표 컴파일
        int32 CoordIndex = Coordinates.Expression ?
            Coordinates.Compile(Compiler) :
            Compiler->TextureCoordinate(0, false, false);

        // 텍스처 샘플 컴파일
        int32 TextureIndex = Compiler->Texture(Texture, SamplerType);

        return Compiler->TextureSample(TextureIndex, CoordIndex, ...);
    }
};

// 텍스처 좌표
class UMaterialExpressionTextureCoordinate : public UMaterialExpression
{
    UPROPERTY()
    int32 CoordinateIndex;  // UV 채널 (0-7)

    UPROPERTY()
    float UTiling;  // U 타일링

    UPROPERTY()
    float VTiling;  // V 타일링

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->TextureCoordinate(CoordinateIndex, false, false);
    }
};
```

### 수학 표현식

```
┌─────────────────────────────────────────────────────────────────┐
│                    주요 수학 표현식                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기본 연산:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Add          A + B                                     │   │
│  │  Subtract     A - B                                     │   │
│  │  Multiply     A × B                                     │   │
│  │  Divide       A / B                                     │   │
│  │  Power        pow(A, B)                                 │   │
│  │  SquareRoot   sqrt(A)                                   │   │
│  │  Abs          abs(A)                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  삼각 함수:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Sine         sin(A)                                    │   │
│  │  Cosine       cos(A)                                    │   │
│  │  Tangent      tan(A)                                    │   │
│  │  Arcsine      asin(A)                                   │   │
│  │  Arccosine    acos(A)                                   │   │
│  │  Arctangent   atan(A)                                   │   │
│  │  Arctangent2  atan2(A, B)                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  벡터 연산:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Dot          dot(A, B)                                 │   │
│  │  Cross        cross(A, B)                               │   │
│  │  Normalize    normalize(A)                              │   │
│  │  Length       length(A)                                 │   │
│  │  Distance     distance(A, B)                            │   │
│  │  Reflect      reflect(V, N)                             │   │
│  │  Transform    transform(V, Matrix)                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  보간/클램프:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Lerp         lerp(A, B, Alpha)                         │   │
│  │  Clamp        clamp(Value, Min, Max)                    │   │
│  │  Saturate     saturate(A)  // clamp(0, 1)               │   │
│  │  Smoothstep   smoothstep(Min, Max, Value)               │   │
│  │  Step         step(Edge, Value)                         │   │
│  │  Min          min(A, B)                                 │   │
│  │  Max          max(A, B)                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 수학 표현식 구현

```cpp
// Add 표현식
class UMaterialExpressionAdd : public UMaterialExpression
{
    UPROPERTY()
    FExpressionInput A;

    UPROPERTY()
    FExpressionInput B;

    UPROPERTY()
    float ConstA;  // A 미연결시 상수

    UPROPERTY()
    float ConstB;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        int32 AIndex = A.Expression ?
            A.Compile(Compiler) :
            Compiler->Constant(ConstA);

        int32 BIndex = B.Expression ?
            B.Compile(Compiler) :
            Compiler->Constant(ConstB);

        return Compiler->Add(AIndex, BIndex);
    }
};

// Lerp 표현식
class UMaterialExpressionLinearInterpolate : public UMaterialExpression
{
    UPROPERTY()
    FExpressionInput A;
    UPROPERTY()
    FExpressionInput B;
    UPROPERTY()
    FExpressionInput Alpha;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        int32 AIndex = A.Compile(Compiler);
        int32 BIndex = B.Compile(Compiler);
        int32 AlphaIndex = Alpha.Compile(Compiler);

        return Compiler->Lerp(AIndex, BIndex, AlphaIndex);
    }
};
```

---

## 유틸리티 표현식

### 파라미터 표현식

```cpp
// 스칼라 파라미터
class UMaterialExpressionScalarParameter : public UMaterialExpressionParameter
{
    UPROPERTY()
    float DefaultValue;

    UPROPERTY()
    bool bUseCustomPrimitiveData;

    UPROPERTY()
    uint8 PrimitiveDataIndex;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->ScalarParameter(ParameterName, DefaultValue);
    }
};

// 벡터 파라미터
class UMaterialExpressionVectorParameter : public UMaterialExpressionParameter
{
    UPROPERTY()
    FLinearColor DefaultValue;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->VectorParameter(ParameterName, DefaultValue);
    }
};

// 텍스처 파라미터
class UMaterialExpressionTextureObjectParameter : public UMaterialExpressionTextureSampleParameter
{
    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->TextureParameter(ParameterName, Texture);
    }
};
```

### 시간/애니메이션 표현식

```
┌─────────────────────────────────────────────────────────────────┐
│                    시간 관련 표현식                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Time:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  레벨 로드 후 경과 시간 (초)                             │   │
│  │  Period로 루핑 가능                                      │   │
│  │  애니메이션, 펄싱 효과                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Panner:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UV 좌표를 시간에 따라 이동                              │   │
│  │  흐르는 물, 컨베이어 벨트                                │   │
│  │  Output = UV + Time * Speed                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Rotator:                                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UV 좌표를 중심점 기준 회전                              │   │
│  │  회전하는 로고, 나침반                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Sine/Cosine with Period:                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  sin(Time * 2π / Period)                                │   │
│  │  펄싱, 호흡 효과                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 월드 표현식

```cpp
// 월드 위치
class UMaterialExpressionWorldPosition : public UMaterialExpression
{
    UPROPERTY()
    TEnumAsByte<EWorldPositionIncludedOffsets> WorldPositionShaderOffset;

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->WorldPosition(WorldPositionShaderOffset);
    }
};

// 픽셀 노멀 월드
class UMaterialExpressionPixelNormalWS : public UMaterialExpression
{
    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->PixelNormalWS();
    }
};

// 카메라 방향
class UMaterialExpressionCameraVectorWS : public UMaterialExpression
{
    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->CameraVector();
    }
};

// 버텍스 노멀 월드
class UMaterialExpressionVertexNormalWS : public UMaterialExpression
{
    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        return Compiler->VertexNormal();
    }
};
```

---

## 커스텀 표현식

### Custom 노드

```cpp
// Custom HLSL 코드 노드
class UMaterialExpressionCustom : public UMaterialExpression
{
    UPROPERTY()
    FString Code;  // 사용자 정의 HLSL 코드

    UPROPERTY()
    TEnumAsByte<ECustomMaterialOutputType> OutputType;

    UPROPERTY()
    FString Description;

    UPROPERTY()
    TArray<FCustomInput> Inputs;  // 커스텀 입력

    UPROPERTY()
    TArray<FCustomOutput> AdditionalOutputs;  // 추가 출력

    UPROPERTY()
    TArray<FCustomDefine> AdditionalDefines;  // 전처리기 정의

    UPROPERTY()
    TArray<FString> IncludeFilePaths;  // 포함할 셰이더 파일

    virtual int32 Compile(FMaterialCompiler* Compiler, int32 OutputIndex) override
    {
        // 입력들 컴파일
        TArray<int32> CompiledInputs;
        for (const FCustomInput& Input : Inputs)
        {
            CompiledInputs.Add(Input.Input.Compile(Compiler));
        }

        // 커스텀 코드 컴파일
        return Compiler->CustomExpression(this, OutputIndex, CompiledInputs);
    }
};
```

### Custom 노드 예시

```hlsl
// Custom 노드 코드 예시

// 1. 간단한 계산
return A * B + C;

// 2. 조건문
if (Mask > 0.5)
    return ColorA;
else
    return ColorB;

// 3. 복잡한 함수
float3 BlendOverlay(float3 Base, float3 Blend)
{
    float3 Result;
    Result.r = Base.r < 0.5 ? (2.0 * Base.r * Blend.r) : (1.0 - 2.0 * (1.0 - Base.r) * (1.0 - Blend.r));
    Result.g = Base.g < 0.5 ? (2.0 * Base.g * Blend.g) : (1.0 - 2.0 * (1.0 - Base.g) * (1.0 - Blend.g));
    Result.b = Base.b < 0.5 ? (2.0 * Base.b * Blend.b) : (1.0 - 2.0 * (1.0 - Base.b) * (1.0 - Blend.b));
    return Result;
}
return BlendOverlay(Base, Blend);

// 4. 외부 함수 호출 (Include 필요)
// IncludeFilePaths: "/Engine/Private/MyFunctions.ush"
return MyCustomFunction(Input1, Input2);
```

---

## 머티리얼 함수

### 머티리얼 함수 개념

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 함수                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  머티리얼 함수 = 재사용 가능한 노드 그래프 조각                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  MF_BlendOverlay (머티리얼 함수)                        │   │
│  │                                                         │   │
│  │  ┌──────────┐                      ┌──────────┐        │   │
│  │  │ Input:   │→ [복잡한 노드 그래프] →│ Output:  │        │   │
│  │  │ Base     │                      │ Result   │        │   │
│  │  │ Blend    │                      │          │        │   │
│  │  └──────────┘                      └──────────┘        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  사용:                                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  머티리얼 A                                             │   │
│  │  [Texture] ─→ ┌──────────────┐                          │   │
│  │              │MF_BlendOverlay│→ [BaseColor]             │   │
│  │  [Color]  ─→ └──────────────┘                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  - 코드 재사용                                                  │
│  - 복잡한 로직 캡슐화                                           │
│  - 유지보수 용이                                                │
│  - 업데이트시 모든 사용처에 반영                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 머티리얼 함수 클래스

```cpp
// 머티리얼 함수
class UMaterialFunction : public UObject
{
    UPROPERTY()
    FString Description;

    UPROPERTY()
    TArray<TObjectPtr<UMaterialExpression>> FunctionExpressions;

    // 입력 표현식들
    TArray<UMaterialExpressionFunctionInput*> GetInputs() const;

    // 출력 표현식들
    TArray<UMaterialExpressionFunctionOutput*> GetOutputs() const;

    // 라이브러리 노출 여부
    UPROPERTY()
    uint8 bExposeToLibrary : 1;
};

// 함수 입력 표현식
class UMaterialExpressionFunctionInput : public UMaterialExpression
{
    UPROPERTY()
    FName InputName;

    UPROPERTY()
    FString Description;

    UPROPERTY()
    TEnumAsByte<EFunctionInputType> InputType;

    UPROPERTY()
    FExpressionInput Preview;  // 미리보기용 기본값
};

// 함수 출력 표현식
class UMaterialExpressionFunctionOutput : public UMaterialExpression
{
    UPROPERTY()
    FName OutputName;

    UPROPERTY()
    FString Description;

    UPROPERTY()
    FExpressionInput A;  // 출력할 값
};
```

---

## 노드 연결 시스템

### 타입 호환성

```
┌─────────────────────────────────────────────────────────────────┐
│                    출력 타입과 연결 규칙                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  출력 타입:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  MCT_Float1 (Scalar)  : 단일 값                         │   │
│  │  MCT_Float2           : 2D 벡터                         │   │
│  │  MCT_Float3           : 3D 벡터                         │   │
│  │  MCT_Float4           : 4D 벡터                         │   │
│  │  MCT_Texture2D        : 2D 텍스처                       │   │
│  │  MCT_TextureCube      : 큐브맵                          │   │
│  │  MCT_StaticBool       : 정적 불리언                     │   │
│  │  MCT_MaterialAttributes : 머티리얼 속성 집합            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  자동 변환:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Float1 → Float2/3/4 : 복제 (x → xxx 또는 xxxx)         │   │
│  │  Float4 → Float3     : .rgb 추출                        │   │
│  │  Float3 → Float4     : .rgb1 (알파 = 1)                 │   │
│  │  Float2/3/4 → Float1 : 불가 (명시적 마스크 필요)        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Component Mask:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [Float4] → [ComponentMask: RG] → [Float2]              │   │
│  │  특정 채널만 추출                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Append:                                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [Float2] + [Float1] → [Append] → [Float3]              │   │
│  │  채널 합치기                                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 요약

머티리얼 그래프 핵심:

1. **표현식** - UMaterialExpression 기반 노드 시스템
2. **상수/파라미터** - Constant, ScalarParameter, VectorParameter
3. **텍스처** - TextureSample, TextureCoordinate, 텍스처 오브젝트
4. **수학** - Add, Multiply, Lerp, 삼각함수, 벡터 연산
5. **커스텀** - Custom HLSL 노드, 머티리얼 함수

노드 그래프는 Compile()을 통해 HLSL 코드로 변환됩니다.

---

## 참고 자료

- [UE Material Expressions](https://docs.unrealengine.com/5.0/en-US/material-expression-reference/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
