# 클로스 시뮬레이션

Chaos Cloth, 컨스트레인트 시스템, 콜리전 처리, GPU 시뮬레이션을 분석합니다.

---

## Chaos Cloth 개요

### 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                   Chaos Cloth Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   UClothingAsset                         │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │  │ Simulation  │  │ Collision   │  │ Rendering   │      │   │
│  │  │ Mesh        │  │ Data        │  │ Data        │      │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘      │   │
│  │         │                │                │              │   │
│  │         ▼                ▼                ▼              │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │            Chaos Cloth Solver                      │  │   │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐           │  │   │
│  │  │  │Particles│  │Constraints│ │Collisions│          │  │   │
│  │  │  │ (Mass)  │  │(Springs) │  │(Bodies)  │          │  │   │
│  │  │  └─────────┘  └─────────┘  └─────────┘           │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Rendering Output                       │   │
│  │  Simulated Positions → Skinned Mesh Blend               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 클로스 에셋 설정

```cpp
// 클로스 에셋 설정
UCLASS()
class UClothingAssetCommon : public UClothingAssetBase
{
    GENERATED_BODY()

public:
    // 물리 설정
    UPROPERTY(EditAnywhere, Category = "Simulation")
    FClothConfig ClothConfig;

    // LOD 데이터
    UPROPERTY()
    TArray<FClothLODDataCommon> LodData;

    // 사용된 본 목록
    UPROPERTY()
    TArray<FName> UsedBoneNames;
};

// 클로스 물리 설정
USTRUCT()
struct FClothConfig
{
    GENERATED_BODY()

    // 질량 설정
    UPROPERTY(EditAnywhere)
    float MassPerUnitArea = 0.035f;  // g/cm²

    // 스티프니스
    UPROPERTY(EditAnywhere)
    float EdgeStiffness = 1.0f;       // 엣지 스프링

    UPROPERTY(EditAnywhere)
    float BendingStiffness = 1.0f;    // 굽힘 스프링

    UPROPERTY(EditAnywhere)
    float AreaStiffness = 1.0f;       // 면적 보존

    // 댐핑
    UPROPERTY(EditAnywhere)
    float Damping = 0.01f;

    // 중력 스케일
    UPROPERTY(EditAnywhere)
    float GravityScale = 1.0f;

    // 콜리전
    UPROPERTY(EditAnywhere)
    float CollisionThickness = 1.0f;  // cm

    UPROPERTY(EditAnywhere)
    float FrictionCoefficient = 0.8f;
};
```

---

## 컨스트레인트 시스템

### 컨스트레인트 타입

```
┌─────────────────────────────────────────────────────────────────┐
│                   Constraint Types                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Distance Constraint (거리 유지):                            │
│     ┌────────────────────────────────────────────────────┐     │
│     │      ●───────────●                                  │     │
│     │      A    d₀     B                                  │     │
│     │                                                     │     │
│     │  |AB| = d₀ 유지                                     │     │
│     │  C = (|AB| - d₀)²                                   │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  2. Bending Constraint (굽힘 제한):                             │
│     ┌────────────────────────────────────────────────────┐     │
│     │      ●───●───●                                      │     │
│     │      A   B   C                                      │     │
│     │          ↓ θ                                        │     │
│     │      ●───●───●                                      │     │
│     │                                                     │     │
│     │  인접 삼각형 간 각도 θ 유지                         │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  3. Long Range Attachment (장거리 연결):                        │
│     ┌────────────────────────────────────────────────────┐     │
│     │   Kinematic     ╌╌╌╌╌╌╌╌     Dynamic               │     │
│     │      ●══════════════════════════●                   │     │
│     │    (고정)      최대 거리      (시뮬)                │     │
│     │                                                     │     │
│     │  과도한 늘어남 방지                                 │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
│  4. Self Collision (자기 충돌):                                 │
│     ┌────────────────────────────────────────────────────┐     │
│     │      ●          ●                                   │     │
│     │       \   ✗    /                                    │     │
│     │        ●──────●                                     │     │
│     │                                                     │     │
│     │  클로스가 자기 자신을 통과하지 않음                 │     │
│     └────────────────────────────────────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### XPBD (Extended Position Based Dynamics)

```cpp
// XPBD 솔버
class FXPBDClothSolver
{
public:
    void Solve(float DeltaTime, int32 NumIterations)
    {
        float SubDt = DeltaTime / NumIterations;

        for (int32 Iter = 0; Iter < NumIterations; ++Iter)
        {
            // 외력 적용 (중력, 바람)
            ApplyExternalForces(SubDt);

            // 예측 위치 계산
            PredictPositions(SubDt);

            // 컨스트레인트 해결
            SolveConstraints(SubDt);

            // 속도 업데이트
            UpdateVelocities(SubDt);

            // 콜리전 해결
            SolveCollisions();
        }
    }

private:
    void SolveConstraints(float Dt)
    {
        // 거리 컨스트레인트
        for (const FDistanceConstraint& C : DistanceConstraints)
        {
            SolveDistanceConstraint(C, Dt);
        }

        // 굽힘 컨스트레인트
        for (const FBendingConstraint& C : BendingConstraints)
        {
            SolveBendingConstraint(C, Dt);
        }

        // Long Range Attachment
        for (const FLongRangeConstraint& C : LongRangeConstraints)
        {
            SolveLongRangeConstraint(C, Dt);
        }
    }

    void SolveDistanceConstraint(const FDistanceConstraint& C, float Dt)
    {
        FVector& P1 = Positions[C.Index1];
        FVector& P2 = Positions[C.Index2];
        float W1 = InverseMasses[C.Index1];
        float W2 = InverseMasses[C.Index2];

        FVector Delta = P2 - P1;
        float Distance = Delta.Size();
        float Error = Distance - C.RestLength;

        if (FMath::Abs(Error) < KINDA_SMALL_NUMBER)
            return;

        FVector Gradient = Delta / Distance;

        // XPBD 컴플라이언스
        float Alpha = C.Compliance / (Dt * Dt);
        float Lambda = -Error / (W1 + W2 + Alpha);

        // 위치 보정
        P1 -= Gradient * Lambda * W1;
        P2 += Gradient * Lambda * W2;
    }
};
```

---

## 콜리전 처리

### 콜리전 프리미티브

```
┌─────────────────────────────────────────────────────────────────┐
│                   Collision Primitives                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Capsule (캐릭터 본):                                           │
│  ┌────────────────────────────────────────────────────────┐    │
│  │       ╭───╮                                             │    │
│  │       │   │  ← 반지름 r                                 │    │
│  │       │   │                                             │    │
│  │       │   │  ← 높이 h                                   │    │
│  │       │   │                                             │    │
│  │       ╰───╯                                             │    │
│  │                                                         │    │
│  │  사용: 팔, 다리, 몸통                                   │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Sphere (관절):                                                 │
│  ┌────────────────────────────────────────────────────────┐    │
│  │        ╭─────╮                                          │    │
│  │       (       )  ← 반지름 r                             │    │
│  │        ╰─────╯                                          │    │
│  │                                                         │    │
│  │  사용: 어깨, 엉덩이, 무릎                               │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
│  Convex Hull (복잡한 형태):                                     │
│  ┌────────────────────────────────────────────────────────┐    │
│  │       ╱▔▔▔╲                                             │    │
│  │      ╱     ╲                                            │    │
│  │     ╱       ╲                                           │    │
│  │     ╲       ╱                                           │    │
│  │      ╲_____╱                                            │    │
│  │                                                         │    │
│  │  사용: 무기, 백팩 등                                    │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 콜리전 해결

```cpp
// 클로스 콜리전 처리
void FClothCollisionResolver::ResolveCollisions(
    TArray<FVector>& Positions,
    const TArray<FClothCollisionPrimitive>& Primitives)
{
    for (int32 ParticleIdx = 0; ParticleIdx < Positions.Num(); ++ParticleIdx)
    {
        FVector& Position = Positions[ParticleIdx];

        for (const FClothCollisionPrimitive& Prim : Primitives)
        {
            switch (Prim.Type)
            {
            case EClothCollisionType::Sphere:
                ResolveSphereCollision(Position, Prim);
                break;

            case EClothCollisionType::Capsule:
                ResolveCapsuleCollision(Position, Prim);
                break;

            case EClothCollisionType::Convex:
                ResolveConvexCollision(Position, Prim);
                break;
            }
        }
    }
}

void ResolveSphereCollision(FVector& Position,
                            const FClothCollisionPrimitive& Sphere)
{
    FVector ToParticle = Position - Sphere.Center;
    float Distance = ToParticle.Size();
    float Penetration = Sphere.Radius + CollisionThickness - Distance;

    if (Penetration > 0)
    {
        // 충돌 해결 - 표면 밖으로 밀어냄
        FVector Normal = ToParticle / Distance;
        Position += Normal * Penetration;
    }
}

void ResolveCapsuleCollision(FVector& Position,
                             const FClothCollisionPrimitive& Capsule)
{
    // 캡슐 축에서 가장 가까운 점 찾기
    FVector ClosestPoint = FMath::ClosestPointOnSegment(
        Position, Capsule.Start, Capsule.End);

    FVector ToParticle = Position - ClosestPoint;
    float Distance = ToParticle.Size();
    float Penetration = Capsule.Radius + CollisionThickness - Distance;

    if (Penetration > 0)
    {
        FVector Normal = ToParticle / Distance;
        Position += Normal * Penetration;
    }
}
```

---

## GPU 클로스 시뮬레이션

### GPU 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│                   GPU Cloth Pipeline                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Compute Shader 기반 시뮬레이션:                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Pass 1: External Forces                                 │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │  velocity += gravity * dt                        │    │   │
│  │  │  velocity += wind_force * dt                     │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                          ↓                               │   │
│  │  Pass 2: Predict Positions                               │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │  predicted_pos = pos + velocity * dt             │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                          ↓                               │   │
│  │  Pass 3: Solve Constraints (반복)                        │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │  for each constraint:                            │    │   │
│  │  │    apply_correction(particles)                   │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                          ↓                               │   │
│  │  Pass 4: Collision Detection & Response                  │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │  resolve_collisions(predicted_pos, colliders)    │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                          ↓                               │   │
│  │  Pass 5: Update Velocities                               │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │  velocity = (predicted_pos - pos) / dt           │    │   │
│  │  │  pos = predicted_pos                             │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 컴퓨트 셰이더 구현

```hlsl
// GPU 클로스 컴퓨트 셰이더
RWStructuredBuffer<float3> Positions;
RWStructuredBuffer<float3> Velocities;
RWStructuredBuffer<float3> PredictedPositions;
StructuredBuffer<FDistanceConstraint> DistanceConstraints;
StructuredBuffer<FCapsuleCollider> Colliders;

cbuffer ClothParams
{
    float DeltaTime;
    float3 Gravity;
    float3 WindForce;
    float Damping;
    int NumIterations;
};

// Pass 1 & 2: 외력 및 예측
[numthreads(64, 1, 1)]
void PredictPositionsCS(uint3 DTid : SV_DispatchThreadID)
{
    uint Idx = DTid.x;

    // 외력 적용
    float3 Velocity = Velocities[Idx];
    Velocity += Gravity * DeltaTime;
    Velocity += WindForce * DeltaTime;
    Velocity *= (1.0 - Damping);

    // 예측 위치
    PredictedPositions[Idx] = Positions[Idx] + Velocity * DeltaTime;
    Velocities[Idx] = Velocity;
}

// Pass 3: 거리 컨스트레인트 해결
[numthreads(64, 1, 1)]
void SolveDistanceConstraintsCS(uint3 DTid : SV_DispatchThreadID)
{
    uint ConstraintIdx = DTid.x;
    FDistanceConstraint C = DistanceConstraints[ConstraintIdx];

    float3 P1 = PredictedPositions[C.Index1];
    float3 P2 = PredictedPositions[C.Index2];

    float3 Delta = P2 - P1;
    float Distance = length(Delta);
    float Error = Distance - C.RestLength;

    if (abs(Error) < 0.0001)
        return;

    float3 Gradient = Delta / Distance;
    float W1 = C.InvMass1;
    float W2 = C.InvMass2;

    float Lambda = -Error / (W1 + W2);

    // Atomic 연산으로 위치 수정
    InterlockedAddFloat(PredictedPositions[C.Index1], -Gradient * Lambda * W1);
    InterlockedAddFloat(PredictedPositions[C.Index2],  Gradient * Lambda * W2);
}

// Pass 4: 콜리전 해결
[numthreads(64, 1, 1)]
void SolveCollisionsCS(uint3 DTid : SV_DispatchThreadID)
{
    uint Idx = DTid.x;
    float3 Pos = PredictedPositions[Idx];

    // 모든 콜라이더에 대해
    for (uint i = 0; i < NumColliders; ++i)
    {
        FCapsuleCollider Cap = Colliders[i];

        // 캡슐과의 거리 계산
        float3 ClosestPoint = ClosestPointOnSegment(Pos, Cap.Start, Cap.End);
        float3 ToParticle = Pos - ClosestPoint;
        float Dist = length(ToParticle);

        float Penetration = Cap.Radius + CollisionThickness - Dist;
        if (Penetration > 0)
        {
            float3 Normal = ToParticle / Dist;
            Pos += Normal * Penetration;
        }
    }

    PredictedPositions[Idx] = Pos;
}
```

---

## 렌더링 통합

### 스키닝 블렌딩

```
┌─────────────────────────────────────────────────────────────────┐
│              Cloth-Skinning Blending                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  블렌딩 마스크:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │     ┌─────────────────────┐                             │   │
│  │     │     Fixed (0.0)     │  ← 스키닝만 사용            │   │
│  │     ├─────────────────────┤                             │   │
│  │     │   Blend (0.0-1.0)   │  ← 점진적 전환              │   │
│  │     ├─────────────────────┤                             │   │
│  │     │   Simulated (1.0)   │  ← 시뮬레이션만 사용        │   │
│  │     │                     │                             │   │
│  │     │     (천 영역)       │                             │   │
│  │     │                     │                             │   │
│  │     └─────────────────────┘                             │   │
│  │                                                          │   │
│  │  FinalPos = lerp(SkinnedPos, SimulatedPos, BlendWeight) │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 렌더링 코드

```cpp
// 클로스 렌더링 데이터 업데이트
void FSkeletalMeshObjectGPUSkin::UpdateClothSimulData(
    FRHICommandListImmediate& RHICmdList)
{
    if (!bClothSimulationEnabled)
        return;

    // 시뮬레이션 결과 가져오기
    const TArray<FVector>& SimPositions = ClothSimulation->GetSimulatedPositions();
    const TArray<FVector>& SimNormals = ClothSimulation->GetSimulatedNormals();

    // GPU 버퍼 업데이트
    void* Data = RHILockBuffer(ClothSimulBuffer, 0,
        SimPositions.Num() * sizeof(FClothSimulVertex), RLM_WriteOnly);

    FClothSimulVertex* Vertices = (FClothSimulVertex*)Data;
    for (int32 i = 0; i < SimPositions.Num(); ++i)
    {
        Vertices[i].Position = SimPositions[i];
        Vertices[i].Normal = SimNormals[i];
    }

    RHIUnlockBuffer(ClothSimulBuffer);
}

// 버텍스 셰이더에서 블렌딩
float3 GetClothBlendedPosition(
    float3 SkinnedPosition,
    float3 ClothPosition,
    float BlendWeight)
{
    return lerp(SkinnedPosition, ClothPosition, BlendWeight);
}
```

---

## 참고 자료

- [Chaos Cloth Documentation](https://docs.unrealengine.com/chaos-cloth/)
- [Position Based Dynamics](https://matthias-research.github.io/pages/publications/posBasedDyn.pdf)
- [XPBD Paper](https://mmacklin.com/xpbd.pdf)
- [Cloth Simulation Tutorial](https://docs.unrealengine.com/cloth-simulation/)
