# 03. GPU 시뮬레이션

Niagara GPU 시뮬레이션의 Compute Shader 구조, 데이터 레이아웃, 동기화를 분석합니다.

---

## GPU 시뮬레이션 개요

### 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU 시뮬레이션 아키텍처                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CPU (Game Thread)                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 시뮬레이션 파라미터 설정                             │   │
│  │  - 디스패치 명령 생성                                   │   │
│  │  - (시뮬레이션 자체는 안함)                             │   │
│  └────────────────────────┬────────────────────────────────┘   │
│                           │ 파라미터 업로드                     │
│                           ▼                                     │
│  GPU (Compute Shader)                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  Particle Buffer (GPU)                          │   │   │
│  │  │  ┌─────┬─────┬─────┬─────┬─────────────────┐   │   │   │
│  │  │  │  P0 │  P1 │  P2 │  P3 │ ...              │   │   │   │
│  │  │  └─────┴─────┴─────┴─────┴─────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                           │                             │   │
│  │                           ▼                             │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  Compute Shader (병렬 실행)                     │   │   │
│  │  │                                                 │   │   │
│  │  │  Thread 0 → P0 업데이트                        │   │   │
│  │  │  Thread 1 → P1 업데이트                        │   │   │
│  │  │  Thread 2 → P2 업데이트                        │   │   │
│  │  │  Thread 3 → P3 업데이트                        │   │   │
│  │  │  ...                                           │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                           │                             │   │
│  │                           ▼                             │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  Updated Particle Buffer (GPU)                  │   │   │
│  │  │  → 렌더링에서 직접 사용                         │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### GPU 시뮬레이션 장점

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU 시뮬레이션 장점                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 대량 병렬 처리                                              │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  CPU: 순차 또는 수십 코어                            │    │
│     │  GPU: 수천 코어 동시 처리                            │    │
│     │  → 수십만 파티클 실시간 가능                         │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. 메모리 대역폭                                               │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  GPU VRAM: 높은 대역폭 (수백 GB/s)                  │    │
│     │  CPU→GPU: 병목 (PCIe)                               │    │
│     │  → 데이터를 GPU에 유지하면 최적                     │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. 렌더링 통합                                                 │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  시뮬레이션 결과 → 렌더러                           │    │
│     │  데이터 복사 없음                                    │    │
│     │  → 레이턴시 감소                                     │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  4. CPU 해방                                                    │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  게임 로직에 CPU 리소스 집중                        │    │
│     │  파티클이 게임 성능에 영향 최소화                   │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 파티클 버퍼

### 데이터 레이아웃

```
┌─────────────────────────────────────────────────────────────────┐
│                    파티클 버퍼 레이아웃                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Structure of Arrays (SoA):                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Position Buffer:                                       │   │
│  │  ┌────────┬────────┬────────┬────────┬──────────┐      │   │
│  │  │ Pos 0  │ Pos 1  │ Pos 2  │ Pos 3  │ ...      │      │   │
│  │  └────────┴────────┴────────┴────────┴──────────┘      │   │
│  │                                                         │   │
│  │  Velocity Buffer:                                       │   │
│  │  ┌────────┬────────┬────────┬────────┬──────────┐      │   │
│  │  │ Vel 0  │ Vel 1  │ Vel 2  │ Vel 3  │ ...      │      │   │
│  │  └────────┴────────┴────────┴────────┴──────────┘      │   │
│  │                                                         │   │
│  │  Color Buffer:                                          │   │
│  │  ┌────────┬────────┬────────┬────────┬──────────┐      │   │
│  │  │ Col 0  │ Col 1  │ Col 2  │ Col 3  │ ...      │      │   │
│  │  └────────┴────────┴────────┴────────┴──────────┘      │   │
│  │                                                         │   │
│  │  Age Buffer:                                            │   │
│  │  ┌────────┬────────┬────────┬────────┬──────────┐      │   │
│  │  │ Age 0  │ Age 1  │ Age 2  │ Age 3  │ ...      │      │   │
│  │  └────────┴────────┴────────┴────────┴──────────┘      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  SoA 장점:                                                      │
│  - 캐시 친화적 (같은 속성 연속 접근)                           │
│  - SIMD 최적화                                                  │
│  - 속성별 독립 접근                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 버퍼 관리

```cpp
// GPU 파티클 버퍼
class FNiagaraGPUParticleBuffer
{
    // 속성별 버퍼
    TMap<FNiagaraVariableBase, FRWBuffer> AttributeBuffers;

    // 파티클 수 관리
    FRWBuffer FreeIDBuffer;        // 재활용 가능한 슬롯
    FRWBuffer AliveIDBuffer;       // 살아있는 파티클 ID
    FRWBuffer ParticleCountBuffer; // 총 파티클 수

    // 최대 파티클 수
    uint32 MaxParticleCount;

    // 현재 활성 파티클 수 (GPU에서 관리)
    // CPU에서 직접 읽기 어려움 → Readback 필요

public:
    void Initialize(uint32 MaxCount, const TArray<FNiagaraVariableBase>& Attributes)
    {
        MaxParticleCount = MaxCount;

        // 각 속성에 대해 버퍼 생성
        for (const auto& Attr : Attributes)
        {
            uint32 Size = Attr.GetSizeInBytes() * MaxCount;
            AttributeBuffers.Add(Attr, CreateRWBuffer(Size));
        }

        // 관리 버퍼
        FreeIDBuffer = CreateRWBuffer(MaxCount * sizeof(int32));
        AliveIDBuffer = CreateRWBuffer(MaxCount * sizeof(int32));
        ParticleCountBuffer = CreateRWBuffer(sizeof(int32) * 2);
    }
};
```

---

## Compute Shader

### 시뮬레이션 셰이더

```hlsl
// Niagara GPU 시뮬레이션 셰이더 (개념적)

// 파티클 속성 버퍼 (SoA)
RWBuffer<float3> Positions;
RWBuffer<float3> Velocities;
RWBuffer<float4> Colors;
RWBuffer<float> Ages;
RWBuffer<float> Lifetimes;

// 시뮬레이션 파라미터
cbuffer SimulationParams
{
    float DeltaTime;
    float3 Gravity;
    float DragCoefficient;
    uint ParticleCount;
};

// 파티클 업데이트 커널
[numthreads(64, 1, 1)]
void UpdateParticles(uint3 DTid : SV_DispatchThreadID)
{
    uint ParticleIndex = DTid.x;

    // 범위 체크
    if (ParticleIndex >= ParticleCount)
        return;

    // 현재 상태 읽기
    float3 Position = Positions[ParticleIndex];
    float3 Velocity = Velocities[ParticleIndex];
    float Age = Ages[ParticleIndex];
    float Lifetime = Lifetimes[ParticleIndex];

    // 수명 체크
    Age += DeltaTime;
    if (Age >= Lifetime)
    {
        // 파티클 죽음 처리 (별도 버퍼에 기록)
        return;
    }

    // 힘 적용
    float3 Acceleration = Gravity;

    // 드래그
    Acceleration -= Velocity * DragCoefficient;

    // 속도 적분
    Velocity += Acceleration * DeltaTime;

    // 위치 적분
    Position += Velocity * DeltaTime;

    // 결과 쓰기
    Positions[ParticleIndex] = Position;
    Velocities[ParticleIndex] = Velocity;
    Ages[ParticleIndex] = Age;
}
```

### Spawn 셰이더

```hlsl
// 파티클 스폰 커널

RWBuffer<int> FreeIDBuffer;     // 사용 가능한 ID
RWBuffer<int> AliveCount;       // 원자적 카운터

// 스폰 파라미터
cbuffer SpawnParams
{
    uint SpawnCount;
    float3 SpawnPosition;
    float3 SpawnVelocityMin;
    float3 SpawnVelocityMax;
    float LifetimeMin;
    float LifetimeMax;
    uint RandomSeed;
};

[numthreads(64, 1, 1)]
void SpawnParticles(uint3 DTid : SV_DispatchThreadID)
{
    uint SpawnIndex = DTid.x;

    if (SpawnIndex >= SpawnCount)
        return;

    // 랜덤 시드 생성
    uint Seed = RandomSeed + SpawnIndex * 1103515245;

    // Free ID 가져오기
    int ParticleID;
    InterlockedAdd(FreeIDBuffer[0], -1, ParticleID);

    if (ParticleID < 0)
        return;  // 슬롯 없음

    // 초기값 설정
    float3 Pos = SpawnPosition;
    float3 Vel = lerp(SpawnVelocityMin, SpawnVelocityMax, Random(Seed));
    float Life = lerp(LifetimeMin, LifetimeMax, Random(Seed + 1));

    // 버퍼에 쓰기
    Positions[ParticleID] = Pos;
    Velocities[ParticleID] = Vel;
    Ages[ParticleID] = 0;
    Lifetimes[ParticleID] = Life;
    Colors[ParticleID] = float4(1, 1, 1, 1);

    // 활성 카운트 증가
    InterlockedAdd(AliveCount[0], 1);
}
```

---

## 시뮬레이션 스테이지

### 다단계 시뮬레이션

```
┌─────────────────────────────────────────────────────────────────┐
│                    시뮬레이션 스테이지                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기본 파티클 스테이지:                                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Particle Spawn → Particle Update                       │   │
│  │  (일반적인 파티클 시뮬레이션)                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  추가 시뮬레이션 스테이지:                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. 그리드 스테이지 (Grid2D/Grid3D)                     │   │
│  │     - 공간을 그리드로 분할                              │   │
│  │     - 셀 단위 연산                                      │   │
│  │     - 유체, 연기 시뮬레이션                             │   │
│  │                                                         │   │
│  │  2. 이웃 찾기 스테이지                                  │   │
│  │     - 공간 해싱                                         │   │
│  │     - 파티클 간 상호작용                                │   │
│  │     - Boid, 충돌                                        │   │
│  │                                                         │   │
│  │  3. 정렬 스테이지                                       │   │
│  │     - 깊이 정렬                                         │   │
│  │     - 렌더링 준비                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  실행 순서 예시:                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Spawn → Update → Grid Write → Grid Solve → Grid Read  │   │
│  │                 → Neighbor Grid → Collision             │   │
│  │                 → Sorting → Render                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Grid 시뮬레이션

```hlsl
// Grid3D 시뮬레이션 예시 (유체)

RWTexture3D<float4> VelocityGrid;     // 속도장
RWTexture3D<float> DensityGrid;       // 밀도장
RWTexture3D<float> PressureGrid;      // 압력장

// 밀도 추가 (파티클 → 그리드)
[numthreads(8, 8, 8)]
void WriteDensityToGrid(uint3 DTid : SV_DispatchThreadID)
{
    // 그리드 셀에 파티클 밀도 누적
    // Trilinear 보간 사용
}

// 압력 솔버 (야코비 반복)
[numthreads(8, 8, 8)]
void SolvePressure(uint3 DTid : SV_DispatchThreadID)
{
    uint3 Coord = DTid;

    // 이웃 셀
    float Left   = PressureGrid[Coord + int3(-1, 0, 0)];
    float Right  = PressureGrid[Coord + int3(1, 0, 0)];
    float Down   = PressureGrid[Coord + int3(0, -1, 0)];
    float Up     = PressureGrid[Coord + int3(0, 1, 0)];
    float Back   = PressureGrid[Coord + int3(0, 0, -1)];
    float Front  = PressureGrid[Coord + int3(0, 0, 1)];

    float Divergence = /* 속도 발산 계산 */;

    // 야코비 반복
    float NewPressure = (Left + Right + Down + Up + Back + Front - Divergence) / 6.0;

    PressureGrid[Coord] = NewPressure;
}

// 속도 투영 (비압축성)
[numthreads(8, 8, 8)]
void ProjectVelocity(uint3 DTid : SV_DispatchThreadID)
{
    // 압력 구배 빼기
    float3 Vel = VelocityGrid[DTid].xyz;
    float3 PressureGrad = /* 압력 구배 계산 */;

    Vel -= PressureGrad;
    VelocityGrid[DTid] = float4(Vel, 0);
}
```

---

## 동기화

### GPU-CPU 동기화

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU-CPU 동기화                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  문제: GPU 데이터를 CPU에서 읽어야 할 때                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 파티클 수 (컬링용)                                   │   │
│  │  - 바운딩 박스 (가시성용)                               │   │
│  │  - 이벤트 데이터                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Readback 방법:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Frame N:                                               │   │
│  │  1. GPU 시뮬레이션                                      │   │
│  │  2. 결과를 Readback 버퍼에 복사                        │   │
│  │                                                         │   │
│  │  Frame N+1 or N+2:                                      │   │
│  │  3. Readback 버퍼 맵핑                                  │   │
│  │  4. CPU에서 데이터 읽기                                 │   │
│  │                                                         │   │
│  │  → 1-2 프레임 지연 발생                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최소화 전략:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 가능하면 GPU에서 모든 것 처리                        │   │
│  │  - Indirect Draw로 파티클 수 GPU 관리                   │   │
│  │  - 바운드는 보수적으로 설정                             │   │
│  │  - 이벤트는 최소화                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Indirect Dispatch/Draw

```cpp
// Indirect Dispatch - GPU가 스레드 수 결정
struct FDispatchIndirectArgs
{
    uint32 ThreadGroupCountX;
    uint32 ThreadGroupCountY;
    uint32 ThreadGroupCountZ;
};

// 파티클 수에 따라 자동 조절
// CPU에서 파티클 수 몰라도 됨

// 셰이더에서 Indirect Args 설정
RWBuffer<uint> DispatchArgs;
RWBuffer<uint> ParticleCount;

[numthreads(1, 1, 1)]
void SetupDispatch()
{
    uint Count = ParticleCount[0];
    uint ThreadGroupCount = (Count + 63) / 64;

    DispatchArgs[0] = ThreadGroupCount;
    DispatchArgs[1] = 1;
    DispatchArgs[2] = 1;
}

// CPU에서 Indirect Dispatch 호출
void DispatchSimulation(FRHICommandList& RHICmdList)
{
    RHICmdList.DispatchIndirectComputeShader(
        SimulationShader,
        DispatchArgsBuffer,
        0  // Offset
    );
}
```

---

## 요약

GPU 시뮬레이션 핵심:

1. **Compute Shader** - 파티클 병렬 처리
2. **SoA 레이아웃** - 캐시 친화적 데이터 구조
3. **버퍼 관리** - Free/Alive ID, 원자적 연산
4. **시뮬레이션 스테이지** - 다단계 처리, Grid 시뮬레이션
5. **동기화** - Readback 최소화, Indirect Dispatch

GPU 시뮬레이션으로 수십만 파티클을 실시간 처리할 수 있습니다.

---

## 참고 자료

- [Niagara GPU Simulation](https://docs.unrealengine.com/5.0/en-US/niagara-simulation-framework/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
