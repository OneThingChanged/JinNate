# 04. FMeshBatch와 FMeshPassProcessor

> 메시 데이터 구조와 패스별 처리

---

## 목차

1. [FMeshBatch 구조](#1-fmeshbatch-구조)
2. [FMeshBatchElement](#2-fmeshbatchelement)
3. [FMeshPassProcessor](#3-fmeshpassprocessor)
4. [EMeshPass 타입](#4-emeshpass-타입)

---

## 1. FMeshBatch 구조 {#1-fmeshbatch-구조}

### 1.1 개요

![FMeshBatch 구조](../images/ch03/1617944-20210319204038916-909213164.jpg)
*FMeshBatch 내부 구조*

```cpp
struct FMeshBatch
{
    // 메시 요소 배열 (LOD 세그먼트 등)
    TArray<FMeshBatchElement, TInlineAllocator<1>> Elements;

    // 공유 리소스
    const FVertexFactory* VertexFactory;
    const FMaterialRenderProxy* MaterialRenderProxy;

    // 프리미티브 타입
    uint32 Type : PT_NumBits;  // PT_TriangleList, PT_LineList 등

    // 패스별 플래그
    uint32 CastShadow : 1;
    uint32 bUseForMaterial : 1;
    uint32 bUseForDepthPass : 1;
    uint32 bUseAsOccluder : 1;
    uint32 bWireframe : 1;

    // LOD
    int8 LODIndex;
    uint8 SegmentIndex;
};
```

---

## 2. FMeshBatchElement {#2-fmeshbatchelement}

### 2.1 구조

```cpp
struct FMeshBatchElement
{
    // 인덱스 버퍼
    const FIndexBuffer* IndexBuffer;
    uint32 FirstIndex;
    uint32 NumPrimitives;

    // 버텍스 범위
    uint32 MinVertexIndex;
    uint32 MaxVertexIndex;

    // 인스턴싱
    uint32 NumInstances;
    uint32 BaseVertexIndex;

    // 프리미티브 유니폼 버퍼
    FRHIUniformBuffer* PrimitiveUniformBuffer;

    // 프리미티브 ID (GPU Scene용)
    uint32 PrimitiveIdMode;
};
```

---

## 3. FMeshPassProcessor {#3-fmeshpassprocessor}

### 3.1 역할

![MeshPassProcessor](../images/ch03/1617944-20210319204048965-266989101.jpg)
*FMeshPassProcessor 처리 과정*

```cpp
class FMeshPassProcessor
{
public:
    // 메시 배치 추가
    virtual void AddMeshBatch(
        const FMeshBatch& Batch,
        uint64 BatchElementMask,
        const FPrimitiveSceneProxy* Proxy,
        const FMaterialRenderProxy* MaterialProxy) = 0;

protected:
    // 드로우 명령 빌드
    void BuildMeshDrawCommand(
        const FMeshBatch& Batch,
        const FMaterial& Material,
        FMeshDrawCommand& OutCommand);

    // 셰이더 선택
    void GetShaders(
        const FMaterial& Material,
        const FVertexFactory* VertexFactory,
        TShaderRef<FShader>& VertexShader,
        TShaderRef<FShader>& PixelShader);
};
```

### 3.2 패스별 프로세서

```cpp
// BasePass 프로세서
class FBasePassMeshProcessor : public FMeshPassProcessor
{
    virtual void AddMeshBatch(...) override
    {
        // BasePass용 셰이더 설정
        // G-Buffer 출력 설정
    }
};

// DepthPass 프로세서
class FDepthPassMeshProcessor : public FMeshPassProcessor
{
    virtual void AddMeshBatch(...) override
    {
        // 뎁스 전용 셰이더
        // 컬러 출력 없음
    }
};
```

---

## 4. EMeshPass 타입 {#4-emeshpass-타입}

### 4.1 패스 목록

| 카테고리 | 패스들 |
|----------|--------|
| **기본** | DepthPass, BasePass, SkyPass |
| **그림자** | CSMShadowDepth |
| **반투명** | Translucency (Standard, AfterDOF, All) |
| **특수** | CustomDepth, Velocity, Distortion |

```cpp
namespace EMeshPass
{
    enum Type
    {
        DepthPass,
        BasePass,
        CSMShadowDepth,
        Translucency,
        TranslucencyAfterDOF,
        TranslucencyAll,
        CustomDepth,
        VirtualTexture,
        LightmapDensity,
        EditorSelection,
        Num
    };
}
```

---

## 다음 문서

[05. DrawCommand와 최적화](05-draw-commands-optimization.md)에서 FMeshDrawCommand와 캐싱을 살펴봅니다.
