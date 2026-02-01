# 03. 씬 가시성 및 수집

> 프러스텀 컬링, 오클루전 컬링, 동적 메시 요소 수집

---

## 목차

1. [가시성 계산 개요](#1-가시성-계산-개요)
2. [프러스텀 컬링](#2-프러스텀-컬링)
3. [오클루전 컬링](#3-오클루전-컬링)
4. [동적 메시 요소 수집](#4-동적-메시-요소-수집)
5. [Relevance 계산](#5-relevance-계산)

---

## 1. 가시성 계산 개요 {#1-가시성-계산-개요}

### 1.1 컬링 파이프라인

```
모든 프리미티브
      │
      ▼ 프러스텀 컬링
┌─────────────┐
│  뷰 내 객체 │
└──────┬──────┘
       │
       ▼ 오클루전 컬링
┌─────────────┐
│ 가려지지 않은│
│    객체     │
└──────┬──────┘
       │
       ▼ LOD 선택
┌─────────────┐
│최종 가시 객체│
└─────────────┘
```

### 1.2 InitViews 단계

```cpp
void FSceneRenderer::InitViews(FRHICommandListImmediate& RHICmdList)
{
    // 1. 뷰 설정
    SetupViewFrustum();

    // 2. 프러스텀 컬링
    ComputeViewVisibility(RHICmdList);

    // 3. 오클루전 컬링 (HZB 기반)
    if (bUseHZBOcclusion)
    {
        OcclusionCull(RHICmdList);
    }

    // 4. Relevance 계산
    ComputeRelevance();

    // 5. 동적 메시 요소 수집
    GatherDynamicMeshElements();
}
```

---

## 2. 프러스텀 컬링 {#2-프러스텀-컬링}

### 2.1 뷰 프러스텀

```cpp
// 6개 평면으로 정의
struct FConvexVolume
{
    TArray<FPlane> Planes;  // Near, Far, Left, Right, Top, Bottom

    bool IntersectBox(const FVector& Origin, const FVector& Extent) const
    {
        for (const FPlane& Plane : Planes)
        {
            float Dist = Plane.PlaneDot(Origin);
            float ProjRadius = Extent.X * FMath::Abs(Plane.X) +
                               Extent.Y * FMath::Abs(Plane.Y) +
                               Extent.Z * FMath::Abs(Plane.Z);

            if (Dist > ProjRadius)
            {
                return false;  // 완전히 외부
            }
        }
        return true;  // 교차 또는 내부
    }
};
```

### 2.2 병렬 프러스텀 컬링

```cpp
void FSceneRenderer::ComputeViewVisibility(...)
{
    ParallelFor(Scene->Primitives.Num(), [&](int32 Index)
    {
        FPrimitiveSceneInfo* Primitive = Scene->Primitives[Index];

        // 프러스텀 테스트
        if (View.ViewFrustum.IntersectBox(
            Primitive->Proxy->GetBounds().Origin,
            Primitive->Proxy->GetBounds().BoxExtent))
        {
            View.PrimitiveVisibilityMap[Index] = true;
        }
    });
}
```

---

## 3. 오클루전 컬링 {#3-오클루전-컬링}

### 3.1 Hierarchical-Z (HZB) 오클루전

```
┌─────────────────────────────────────────┐
│          HZB 오클루전 컬링               │
├─────────────────────────────────────────┤
│                                         │
│  1. 이전 프레임 뎁스로 HZB 밉맵 생성     │
│                                         │
│  2. 각 오브젝트의 바운딩 박스를           │
│     스크린 공간으로 투영                 │
│                                         │
│  3. 적절한 HZB 밉 레벨에서               │
│     가려짐 여부 테스트                   │
│                                         │
└─────────────────────────────────────────┘
```

---

## 4. 동적 메시 요소 수집 {#4-동적-메시-요소-수집}

### 4.1 GatherDynamicMeshElements

![가시성 수집](../images/ch03/1617944-20210319203940982-1545653618.png)
*동적 메시 요소 수집 과정*

```cpp
void FSceneRenderer::GatherDynamicMeshElements(
    TArray<FViewInfo>& InViews,
    const FScene* InScene,
    FMeshElementCollector& Collector)
{
    for (int32 PrimitiveIndex = 0; PrimitiveIndex < NumPrimitives; ++PrimitiveIndex)
    {
        // 가시적인 프리미티브만
        if (View.PrimitiveVisibilityMap[PrimitiveIndex])
        {
            FPrimitiveSceneInfo* PrimitiveSceneInfo = InScene->Primitives[PrimitiveIndex];

            // 프록시에서 메시 요소 수집
            PrimitiveSceneInfo->Proxy->GetDynamicMeshElements(
                InViews,
                ViewFamily,
                VisibilityMap,
                Collector);
        }
    }
}
```

---

## 5. Relevance 계산 {#5-relevance-계산}

### 5.1 FMeshBatch Relevance

![Relevance 계산](../images/ch03/1617944-20210319204017205-991200520.png)
*메시 배치 Relevance 계산*

```cpp
struct FMeshBatchRelevance
{
    uint32 bUseForMaterial : 1;      // 머티리얼 패스
    uint32 bUseForDepthPass : 1;     // 뎁스 패스
    uint32 bCastShadow : 1;          // 그림자 캐스팅
    uint32 bUseAsOccluder : 1;       // 오클루더로 사용
    uint32 bVelocityRelevance : 1;   // 속도 버퍼
};
```

---

## 다음 문서

[04. MeshBatch와 Processor](04-mesh-batch-processor.md)에서 FMeshBatch와 FMeshPassProcessor를 살펴봅니다.
