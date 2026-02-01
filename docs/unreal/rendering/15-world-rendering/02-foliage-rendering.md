# 폴리지 렌더링

수백만 개의 식생 인스턴스를 효율적으로 렌더링하는 시스템을 분석합니다.

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                   Foliage 시스템 아키텍처                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 AInstancedFoliageActor                   │   │
│  │  • 월드당 하나의 Foliage Actor                           │   │
│  │  • 모든 폴리지 컴포넌트 관리                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              UFoliageInstancedStaticMeshComponent        │   │
│  │  ┌────────────────────────────────────────────────┐     │   │
│  │  │        Hierarchical Instanced Static Mesh       │     │   │
│  │  │                    (HISM)                        │     │   │
│  │  │  ┌─────────────────────────────────────────┐   │     │   │
│  │  │  │           Cluster Tree                  │   │     │   │
│  │  │  │  ┌─────┐                                │   │     │   │
│  │  │  │  │Root │                                │   │     │   │
│  │  │  │  └──┬──┘                                │   │     │   │
│  │  │  │     ├────────┬────────┐                 │   │     │   │
│  │  │  │  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐             │   │     │   │
│  │  │  │  │Node │  │Node │  │Node │  ...        │   │     │   │
│  │  │  │  └──┬──┘  └─────┘  └─────┘             │   │     │   │
│  │  │  │     ├────────┐                          │   │     │   │
│  │  │  │  ┌──┴──┐  ┌──┴──┐                      │   │     │   │
│  │  │  │  │Leaf │  │Leaf │  (인스턴스 그룹)      │   │     │   │
│  │  │  │  └─────┘  └─────┘                      │   │     │   │
│  │  │  └─────────────────────────────────────────┘   │     │   │
│  │  └────────────────────────────────────────────────┘     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## HISM (Hierarchical Instanced Static Mesh)

### 클러스터 트리 구조

```cpp
// HISM 컴포넌트
class UHierarchicalInstancedStaticMeshComponent : public UInstancedStaticMeshComponent
{
    // 클러스터 트리
    TArray<FClusterNode> ClusterTree;

    // 인스턴스 데이터
    TArray<FMatrix> InstanceTransforms;
    TArray<FInstancedStaticMeshInstanceData> PerInstanceSMData;

    // 클러스터 설정
    int32 DesiredInstancesPerLeaf;  // 리프당 인스턴스 수
    float MaxDrawDistance;
    float MinLODDistance;
};

// 클러스터 노드
struct FClusterNode
{
    FVector BoundMin;
    int32 FirstChild;      // 첫 자식 또는 첫 인스턴스

    FVector BoundMax;
    int32 LastChild;       // 마지막 자식 또는 마지막 인스턴스

    int32 FirstInstance;
    int32 LastInstance;
};
```

### 계층적 컬링

```
┌─────────────────────────────────────────────────────────────────┐
│                     HISM 계층적 컬링                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Root 노드 테스트                                            │
│     ┌─────────────────────────────────┐                        │
│     │           Root                   │                        │
│     │    전체 폴리지 바운드            │ ◀── Frustum 테스트     │
│     └───────────────┬─────────────────┘                        │
│                     │ (통과)                                    │
│                     ▼                                           │
│  2. 자식 노드 테스트                                            │
│     ┌─────────┐ ┌─────────┐ ┌─────────┐                        │
│     │ Node A  │ │ Node B  │ │ Node C  │                        │
│     │   ✓     │ │   ✗     │ │   ✓     │ ◀── 개별 테스트       │
│     └────┬────┘ └─────────┘ └────┬────┘                        │
│          │        (제거)          │                             │
│          ▼                        ▼                             │
│  3. 리프 노드 테스트                                            │
│     ┌────┐ ┌────┐            ┌────┐ ┌────┐                     │
│     │ ✓  │ │ ✗  │            │ ✓  │ │ ✓  │                     │
│     └────┘ └────┘            └────┘ └────┘                     │
│       │                        │       │                        │
│       ▼                        ▼       ▼                        │
│  4. 인스턴스 렌더링                                             │
│     [100개]                  [150개] [120개]                    │
│                                                                 │
│  결과: 1000개 중 370개만 렌더링 (63% 컬링)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU Instancing

### 인스턴스 버퍼

```cpp
// 인스턴스 데이터 구조
struct FInstanceStream
{
    FVector4 InstanceOrigin;           // XYZ: 위치, W: 사용자 데이터
    FVector4 InstanceTransform1;       // 회전/스케일 행 1
    FVector4 InstanceTransform2;       // 회전/스케일 행 2
    FVector4 InstanceTransform3;       // 회전/스케일 행 3
    FVector4 InstanceLightmapAndShadow; // 라이트맵 좌표
};

// GPU 인스턴싱 Draw Call
void RenderFoliageInstances(const FMeshBatch& MeshBatch)
{
    // 인스턴스 버퍼 바인딩
    RHICmdList.SetStreamSource(
        1,  // Stream 1 = Instance Data
        InstanceBuffer,
        0   // Offset
    );

    // 인스턴스드 드로우
    RHICmdList.DrawIndexedPrimitive(
        IndexBuffer,
        0,                      // BaseVertexIndex
        0,                      // FirstInstance
        NumVertices,
        0,                      // StartIndex
        NumTriangles,
        NumInstances            // 인스턴스 수
    );
}
```

### 버텍스 셰이더

```hlsl
// 인스턴스 데이터 페칭
void GetInstanceData(
    uint InstanceId,
    out float4x4 InstanceTransform,
    out float3 InstanceOrigin)
{
    // StructuredBuffer에서 인스턴스 데이터 읽기
    FInstanceStream Instance = InstanceBuffer[InstanceId];

    InstanceOrigin = Instance.InstanceOrigin.xyz;

    // Transform 재구성
    InstanceTransform = float4x4(
        float4(Instance.InstanceTransform1.xyz, 0),
        float4(Instance.InstanceTransform2.xyz, 0),
        float4(Instance.InstanceTransform3.xyz, 0),
        float4(InstanceOrigin, 1)
    );
}

// 월드 포지션 계산
float3 TransformInstancePosition(float3 LocalPosition, uint InstanceId)
{
    float4x4 InstanceTransform;
    float3 InstanceOrigin;
    GetInstanceData(InstanceId, InstanceTransform, InstanceOrigin);

    return mul(float4(LocalPosition, 1), InstanceTransform).xyz;
}
```

---

## LOD 시스템

### 거리 기반 LOD

```
┌─────────────────────────────────────────────────────────────────┐
│                    Foliage LOD 설정                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Camera                                                         │
│    │                                                            │
│    │◀────── LOD 0 ──────▶│◀── LOD 1 ──▶│◀─ LOD 2 ─▶│◀─ Cull ─▶│
│    │                      │              │            │          │
│    0m                   50m           100m         200m        ∞ │
│                                                                 │
│  Static Mesh LOD 설정:                                          │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ LOD 0: 5000 triangles @ 0-50m                              ││
│  │ LOD 1: 1000 triangles @ 50-100m                            ││
│  │ LOD 2: 200 triangles @ 100-200m                            ││
│  │ Cull Distance: 200m                                         ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Dithered LOD Transition:                                       │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ • 부드러운 LOD 전환                                         ││
│  │ • 스크린 도어 디더링 사용                                    ││
│  │ • 전환 구간에서 두 LOD 모두 렌더링                          ││
│  └────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Cull Distance Volume

```cpp
// 거리 기반 컬링 설정
UPROPERTY(EditAnywhere, Category = "Culling")
struct FFoliageCullDistanceParams
{
    // 시작 거리 (페이드 시작)
    float StartCullDistance;

    // 끝 거리 (완전히 컬링)
    float EndCullDistance;

    // 스크린 사이즈 기반 컬링
    float MinScreenSize;

    // 그림자 거리
    float ShadowCullDistance;
};

// Cull Distance Volume
class ACullDistanceVolume : public AVolume
{
    // 사이즈별 컬링 거리
    TArray<FCullDistanceSizePair> CullDistances;

    // 바운드 사이즈 → 컬링 거리 매핑
    // Size 100 → Cull at 5000
    // Size 500 → Cull at 10000
    // Size 1000 → Cull at 20000
};
```

---

## 바람 애니메이션

### Wind 셰이더

```hlsl
// Simple Wind (성능 우선)
float3 SimpleWind(float3 WorldPosition, float3 ObjectPivot, float Time)
{
    // 월드 공간 노이즈
    float WindPhase = dot(WorldPosition.xy, float2(0.1, 0.1));

    // 사인파 흔들림
    float WindStrength = sin(Time * WindSpeed + WindPhase) * WindIntensity;

    // 높이에 따른 강도 (아래쪽 고정)
    float HeightFactor = saturate((WorldPosition.z - ObjectPivot.z) / ObjectHeight);

    return float3(WindStrength * HeightFactor, 0, 0);
}

// Complex Wind (품질 우선)
float3 ComplexWind(
    float3 WorldPosition,
    float3 ObjectPivot,
    float Time,
    float3 WindDirection,
    float WindSpeed,
    float WindGustStrength)
{
    float3 Offset = 0;

    // 주 바람 방향
    float MainWave = sin(Time * WindSpeed +
                         dot(WorldPosition.xy, WindDirection.xy) * 0.1);

    // 돌풍 (불규칙한 움직임)
    float GustWave = sin(Time * WindSpeed * 2.5 +
                         WorldPosition.x * 0.3) *
                     cos(Time * WindSpeed * 1.5 +
                         WorldPosition.y * 0.2);

    // 높이 기반 강도
    float HeightMask = pow(saturate(
        (WorldPosition.z - ObjectPivot.z) / ObjectHeight), 2);

    // 최종 오프셋
    Offset = WindDirection * (MainWave + GustWave * WindGustStrength) * HeightMask;

    return Offset;
}
```

### 머티리얼 구현

```
┌─────────────────────────────────────────────────────────────────┐
│                   Wind 머티리얼 그래프                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐                                               │
│  │  Time Node  │                                               │
│  └──────┬──────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────┐    ┌─────────────┐                            │
│  │  Sine Wave  │◀───│Wind Speed   │                            │
│  └──────┬──────┘    │ Parameter   │                            │
│         │           └─────────────┘                            │
│         ▼                                                       │
│  ┌─────────────────────────────────────┐                       │
│  │         Multiply                     │                       │
│  │  ┌─────────────┐  ┌─────────────┐   │                       │
│  │  │ Wind Vector │  │Height Mask  │   │                       │
│  │  └──────┬──────┘  └──────┬──────┘   │                       │
│  └─────────┼────────────────┼──────────┘                       │
│            │                │                                   │
│            └────────┬───────┘                                   │
│                     ▼                                           │
│  ┌───────────────────────────────────────────────┐             │
│  │              World Position Offset             │             │
│  └───────────────────────────────────────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Procedural Foliage

### PCG (Procedural Content Generation)

```cpp
// Procedural Foliage Spawner
class UProceduralFoliageSpawner : public UObject
{
    // 폴리지 타입 목록
    TArray<FFoliageTypeObject> FoliageTypes;

    // 시뮬레이션 설정
    int32 RandomSeed;
    float TileSize;           // 타일 크기
    int32 NumUniqueTiles;     // 고유 타일 수
    float MinimumQuadSize;    // 최소 쿼드 크기

    // 충돌 설정
    bool bCollisionWithSelf;  // 자체 충돌
    bool bCollisionWithOther; // 다른 타입과 충돌
};

// 폴리지 타입 설정
struct FFoliageType
{
    // 메시
    UStaticMesh* Mesh;

    // 분포 설정
    float Density;
    float AverageSpread;
    float SpreadVariance;

    // 스케일
    FVector ScaleMin;
    FVector ScaleMax;

    // 경사/고도 제한
    float AlignToNormalMin;
    float AlignToNormalMax;
    float GroundSlopeAngle;
    float HeightMin;
    float HeightMax;
};
```

### Grass 시스템

```
┌─────────────────────────────────────────────────────────────────┐
│                    Landscape Grass 시스템                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                Landscape Material                         │   │
│  │  ┌─────────────────────────────────────────────────┐     │   │
│  │  │         Grass Output Node                        │     │   │
│  │  │  • Grass Type 연결                               │     │   │
│  │  │  • Weight 기반 밀도                              │     │   │
│  │  └─────────────────────────────────────────────────┘     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │               Runtime Grass Generation                   │   │
│  │                                                          │   │
│  │  • 카메라 주변 실시간 생성                               │   │
│  │  • Landscape Component 기반                             │   │
│  │  • HISM으로 인스턴싱                                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Grass 렌더링                             │   │
│  │                                                          │   │
│  │  • 근거리만 렌더링 (Start/End Cull Distance)            │   │
│  │  • 그림자 거리 제한                                      │   │
│  │  • LOD 자동 적용                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Nanite Foliage

### UE5 Nanite 폴리지

```cpp
// Nanite 폴리지 설정
UPROPERTY(EditAnywhere, Category = "Nanite")
struct FNaniteFoliageSettings
{
    // Nanite 활성화
    bool bEnableNanite;

    // Fallback 메시 (Nanite 미지원 시)
    UStaticMesh* FallbackMesh;

    // WPO (World Position Offset) 비활성화 필요
    // Nanite는 WPO 미지원
};
```

### Nanite vs 기존 폴리지

```
┌─────────────────────────────────────────────────────────────────┐
│               Nanite Foliage vs Traditional Foliage              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Traditional (HISM)              Nanite Foliage                 │
│  ┌─────────────────┐            ┌─────────────────┐            │
│  │ • LOD 수동 설정  │            │ • 자동 LOD      │            │
│  │ • Draw Call 비용│            │ • GPU Driven    │            │
│  │ • WPO 지원      │            │ • WPO 미지원    │            │
│  │ • 인스턴싱 최적화│            │ • 지오메트리 최적화│           │
│  └─────────────────┘            └─────────────────┘            │
│                                                                 │
│  적합한 경우:                    적합한 경우:                    │
│  • 바람 애니메이션 필요           • 고폴리 폴리지               │
│  • 동적 변형 필요                 • 정적 폴리지                  │
│  • 저사양 플랫폼                  • 고사양 PC/콘솔               │
│                                                                 │
│  트레이드오프:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Nanite 폴리지 = 바람 없음 but 무제한 디테일            │   │
│  │  HISM 폴리지 = 바람 있음 but LOD 관리 필요              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 최적화 기법

### 성능 체크리스트

```
┌─────────────────────────────────────────────────────────────────┐
│                  Foliage 최적화 체크리스트                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  메시 최적화                                                    │
│  □ 적절한 폴리곤 수 (LOD 0: 1000-5000 tris)                    │
│  □ LOD 설정 (최소 3단계)                                       │
│  □ Impostor LOD 검토 (원거리)                                  │
│                                                                 │
│  인스턴싱 최적화                                                 │
│  □ 동일 메시 그룹화                                             │
│  □ HISM 클러스터 크기 조정                                     │
│  □ 과도한 인스턴스 타입 피하기                                  │
│                                                                 │
│  컬링 최적화                                                    │
│  □ 적절한 Cull Distance 설정                                   │
│  □ Screen Size 기반 컬링                                       │
│  □ Shadow 거리 제한                                            │
│                                                                 │
│  머티리얼 최적화                                                 │
│  □ 텍스처 아틀라스 사용                                        │
│  □ 복잡한 셰이더 피하기                                        │
│  □ 인스턴스별 랜덤 값 활용                                     │
│                                                                 │
│  밀도 최적화                                                    │
│  □ 필요한 곳에만 배치                                          │
│  □ 레이어별 밀도 조절                                          │
│  □ Scalability 설정                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Scalability 설정

```cpp
// Engine Scalability Groups
[FoliageQuality@0]  // Low
foliage.DensityScale=0.4
foliage.MinLOD=2
grass.DensityScale=0.2

[FoliageQuality@1]  // Medium
foliage.DensityScale=0.6
foliage.MinLOD=1
grass.DensityScale=0.5

[FoliageQuality@2]  // High
foliage.DensityScale=0.8
foliage.MinLOD=0
grass.DensityScale=0.8

[FoliageQuality@3]  // Epic
foliage.DensityScale=1.0
foliage.MinLOD=0
grass.DensityScale=1.0
```

---

## 다음 단계

- [레벨 스트리밍](03-level-streaming.md)에서 동적 콘텐츠 로딩을 학습합니다.
