# 02. Niagara 아키텍처

Niagara의 System, Emitter, Module 구조와 스크립트 시스템을 분석합니다.

---

## 계층 구조

### System-Emitter-Module

```
┌─────────────────────────────────────────────────────────────────┐
│                    Niagara 계층 구조                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Niagara System (NS_Fire)                               │   │
│  │  ─────────────────────────────────────────────────────  │   │
│  │  - 최상위 에셋                                          │   │
│  │  - 여러 Emitter 포함                                    │   │
│  │  - 시스템 레벨 파라미터                                 │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  Emitter 1 (Flames)                             │   │   │
│  │  │  ───────────────────────────────────────────    │   │   │
│  │  │  ┌─────────────────────────────────────────┐   │   │   │
│  │  │  │  Emitter Spawn Modules                  │   │   │   │
│  │  │  │  └─ Initialize Emitter                  │   │   │   │
│  │  │  ├─────────────────────────────────────────┤   │   │   │
│  │  │  │  Emitter Update Modules                 │   │   │   │
│  │  │  │  └─ Emitter State                       │   │   │   │
│  │  │  ├─────────────────────────────────────────┤   │   │   │
│  │  │  │  Particle Spawn Modules                 │   │   │   │
│  │  │  │  ├─ Spawn Rate                          │   │   │   │
│  │  │  │  ├─ Initialize Position                 │   │   │   │
│  │  │  │  └─ Initialize Velocity                 │   │   │   │
│  │  │  ├─────────────────────────────────────────┤   │   │   │
│  │  │  │  Particle Update Modules                │   │   │   │
│  │  │  │  ├─ Gravity Force                       │   │   │   │
│  │  │  │  ├─ Scale Color                         │   │   │   │
│  │  │  │  └─ Solve Forces and Velocity           │   │   │   │
│  │  │  ├─────────────────────────────────────────┤   │   │   │
│  │  │  │  Render (Sprite Renderer)               │   │   │   │
│  │  │  └─────────────────────────────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                         │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │  Emitter 2 (Smoke)                              │   │   │
│  │  │  ...                                            │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Niagara System

### System 클래스

```cpp
// Niagara 시스템 에셋
class UNiagaraSystem : public UFXSystemAsset
{
public:
    // Emitter 핸들 배열
    UPROPERTY()
    TArray<FNiagaraEmitterHandle> EmitterHandles;

    // 노출된 파라미터 (외부에서 접근 가능)
    UPROPERTY()
    FNiagaraUserRedirectionParameterStore ExposedParameters;

    // 시스템 스크립트
    UPROPERTY()
    UNiagaraScript* SystemSpawnScript;
    UPROPERTY()
    UNiagaraScript* SystemUpdateScript;

    // 바운드 설정
    UPROPERTY()
    bool bFixedBounds;
    UPROPERTY()
    FBox FixedBounds;

    // 워밍업
    UPROPERTY()
    float WarmupTime;

    // 풀링
    UPROPERTY()
    uint32 PoolPrimeSize;

    // 결정론적 시뮬레이션
    UPROPERTY()
    bool bDeterminism;
    UPROPERTY()
    int32 RandomSeed;
};

// Emitter 핸들
struct FNiagaraEmitterHandle
{
    FGuid Id;                    // 고유 ID
    FName Name;                  // 표시 이름
    bool bIsEnabled;             // 활성화 여부
    UNiagaraEmitter* Instance;   // Emitter 인스턴스
};
```

### System 스크립트

```
┌─────────────────────────────────────────────────────────────────┐
│                    System 스크립트 단계                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  System Spawn:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 시스템 생성 시 한 번 실행                            │   │
│  │  - 시스템 레벨 초기화                                   │   │
│  │  - 전역 파라미터 설정                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  System Update:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  - 매 프레임 실행                                       │   │
│  │  - Emitter 전체에 영향                                  │   │
│  │  - 시스템 레벨 로직                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  실행 순서:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. System Spawn (최초 1회)                             │   │
│  │  2. System Update                                       │   │
│  │  3. Emitter Spawn/Update                                │   │
│  │  4. Particle Spawn/Update                               │   │
│  │  5. Render                                              │   │
│  │  (2-5 매 프레임 반복)                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Niagara Emitter

### Emitter 클래스

```cpp
// Niagara Emitter
class UNiagaraEmitter : public UObject
{
public:
    // 시뮬레이션 타겟
    UPROPERTY()
    ENiagaraSimTarget SimTarget;  // CPU 또는 GPU

    // 결정론 설정
    UPROPERTY()
    bool bDeterminism;
    UPROPERTY()
    bool bInterpolatedSpawning;

    // 수명 모드
    UPROPERTY()
    ENiagaraEmitterLifeCycleMode LifeCycleMode;

    // 스크립트 (컴파일된 모듈 스택)
    UPROPERTY()
    UNiagaraScript* EmitterSpawnScript;
    UPROPERTY()
    UNiagaraScript* EmitterUpdateScript;
    UPROPERTY()
    UNiagaraScript* ParticleSpawnScript;
    UPROPERTY()
    UNiagaraScript* ParticleUpdateScript;

    // 렌더러
    UPROPERTY()
    TArray<UNiagaraRendererProperties*> RendererProperties;

    // 이벤트 핸들러
    UPROPERTY()
    TArray<FNiagaraEventScriptProperties> EventHandlerScriptProps;

    // 시뮬레이션 스테이지
    UPROPERTY()
    TArray<UNiagaraSimulationStageBase*> SimulationStages;

    // 파티클 속성 정의
    UPROPERTY()
    TArray<FNiagaraVariable> ParticleAttributes;
};

// 시뮬레이션 타겟
enum class ENiagaraSimTarget : uint8
{
    CPUSim,    // CPU 시뮬레이션
    GPUComputeSim  // GPU Compute 시뮬레이션
};
```

### Emitter 스크립트 단계

```
┌─────────────────────────────────────────────────────────────────┐
│                    Emitter 스크립트 단계                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Emitter Properties                                          │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  - Sim Target (CPU/GPU)                             │    │
│     │  - Local Space / World Space                        │    │
│     │  - 결정론 설정                                       │    │
│     │  - 바운딩 모드                                       │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  2. Emitter Spawn                                               │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  - Emitter 초기화                                    │    │
│     │  - 한 번만 실행                                      │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. Emitter Update                                              │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  - 매 프레임 실행 (파티클 전)                        │    │
│     │  - Spawn Rate 결정                                   │    │
│     │  - Emitter 상태 관리                                 │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  4. Particle Spawn                                              │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  - 새 파티클 생성 시                                 │    │
│     │  - 초기 위치, 속도, 색상 등                          │    │
│     │  - Spawn된 파티클에만 적용                           │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  5. Particle Update                                             │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  - 매 프레임 모든 파티클에                           │    │
│     │  - 물리, 색상, 크기 업데이트                         │    │
│     │  - 수명 체크, Kill 조건                              │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  6. Render                                                      │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  - 시각화 설정                                       │    │
│     │  - Sprite, Mesh, Ribbon 등                          │    │
│     │  - 머티리얼, 정렬 등                                 │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module 시스템

### Module 구조

```cpp
// Niagara 모듈은 스크립트로 구성
// 에디터에서 노드 그래프로 편집

// 모듈 입력/출력
struct FNiagaraVariable
{
    FNiagaraTypeDefinition TypeDefinition;  // 타입 (float, vector 등)
    FName Name;                              // 변수명
    TArray<uint8> Data;                      // 데이터
};

// 주요 모듈 카테고리
/*
Spawn:
- Spawn Rate
- Spawn Burst Instantaneous
- Spawn Per Unit

Initialize:
- Initialize Particle
- Set (Position, Velocity, Color, etc.)
- Shape Location (Sphere, Cone, Mesh, etc.)

Update:
- Add Velocity
- Gravity Force
- Drag
- Curl Noise Force
- Scale Color/Size over Life
- Solve Forces and Velocity

Kill:
- Kill Particles in Volume
- Kill Particles by Lifetime

Event:
- Generate Event
- Receive Event
*/
```

### 내장 모듈 예시

```
┌─────────────────────────────────────────────────────────────────┐
│                    주요 내장 모듈                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Spawn 모듈:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Spawn Rate                                             │   │
│  │  - Rate: 초당 생성 파티클 수                            │   │
│  │                                                         │   │
│  │  Spawn Burst Instantaneous                              │   │
│  │  - Spawn Count: 한 번에 생성할 수                       │   │
│  │  - Spawn Time: 생성 시점                                │   │
│  │                                                         │   │
│  │  Spawn Per Unit                                         │   │
│  │  - 이동 거리당 생성 (트레일 효과)                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Initialize 모듈:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Initialize Particle                                    │   │
│  │  - Lifetime, Color, Size 등 기본값                      │   │
│  │                                                         │   │
│  │  Shape Location                                         │   │
│  │  - Sphere/Box/Cylinder/Cone/Torus/Mesh Surface         │   │
│  │  - 초기 위치 분포                                       │   │
│  │                                                         │   │
│  │  Add Velocity                                           │   │
│  │  - 방향, 속도 범위 설정                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Update 모듈:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Gravity Force                                          │   │
│  │  - 중력 방향, 세기                                      │   │
│  │                                                         │   │
│  │  Drag                                                   │   │
│  │  - 공기 저항 계수                                       │   │
│  │                                                         │   │
│  │  Curl Noise Force                                       │   │
│  │  - 노이즈 기반 힘 (연기, 불 효과)                       │   │
│  │                                                         │   │
│  │  Scale Color/Size                                       │   │
│  │  - 수명에 따른 변화 커브                                │   │
│  │                                                         │   │
│  │  Solve Forces and Velocity                              │   │
│  │  - 힘 → 가속도 → 속도 → 위치 적분                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 파라미터 시스템

### 파라미터 네임스페이스

```
┌─────────────────────────────────────────────────────────────────┐
│                    파라미터 네임스페이스                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Engine:           엔진 제공 읽기 전용                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Engine.DeltaTime                                       │   │
│  │  Engine.Time                                            │   │
│  │  Engine.Owner.Position                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  System:           시스템 레벨                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  System.Age                                             │   │
│  │  System.LoopCount                                       │   │
│  │  System.ExecutionState                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Emitter:          Emitter 레벨                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Emitter.Age                                            │   │
│  │  Emitter.SpawnRate                                      │   │
│  │  Emitter.LoopCount                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Particles:        파티클 레벨                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Particles.Position                                     │   │
│  │  Particles.Velocity                                     │   │
│  │  Particles.Color                                        │   │
│  │  Particles.Age                                          │   │
│  │  Particles.Lifetime                                     │   │
│  │  Particles.NormalizedAge                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  User:             사용자 노출 파라미터                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  User.SpawnRate (블루프린트에서 설정)                   │   │
│  │  User.Color                                             │   │
│  │  User.Size                                              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### User 파라미터 사용

```cpp
// 블루프린트/C++에서 파라미터 설정
void SetNiagaraParameters(UNiagaraComponent* NiagaraComp)
{
    // 스칼라 파라미터
    NiagaraComp->SetVariableFloat(FName("User.SpawnRate"), 100.0f);

    // 벡터 파라미터
    NiagaraComp->SetVariableVec3(FName("User.Direction"), FVector(0, 0, 1));

    // 색상 파라미터
    NiagaraComp->SetVariableLinearColor(FName("User.Color"), FLinearColor::Red);

    // 오브젝트 파라미터
    NiagaraComp->SetVariableActor(FName("User.TargetActor"), TargetActor);
}

// 파라미터 읽기
float GetSpawnRate(UNiagaraComponent* NiagaraComp)
{
    float Value;
    if (NiagaraComp->GetVariableFloat(FName("User.SpawnRate"), Value))
    {
        return Value;
    }
    return 0.0f;
}
```

---

## 데이터 인터페이스

### 데이터 인터페이스란?

```
┌─────────────────────────────────────────────────────────────────┐
│                    데이터 인터페이스                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  정의: 외부 데이터에 접근하기 위한 표준 인터페이스              │
│                                                                 │
│  주요 데이터 인터페이스:                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Static Mesh                                            │   │
│  │  - 메시 표면에서 스폰                                   │   │
│  │  - 버텍스 위치/노멀/UV 접근                             │   │
│  │                                                         │   │
│  │  Skeletal Mesh                                          │   │
│  │  - 스켈레탈 메시 본/소켓에서 스폰                       │   │
│  │  - 애니메이션과 동기화                                  │   │
│  │                                                         │   │
│  │  Texture                                                │   │
│  │  - 텍스처 샘플링                                        │   │
│  │  - 2D/3D/Cube                                           │   │
│  │                                                         │   │
│  │  Collision Query                                        │   │
│  │  - 씬 충돌 검사                                         │   │
│  │  - 레이캐스트, 스윕                                     │   │
│  │                                                         │   │
│  │  Audio                                                  │   │
│  │  - 오디오 스펙트럼                                      │   │
│  │  - 음악 반응 이펙트                                     │   │
│  │                                                         │   │
│  │  Spline                                                 │   │
│  │  - 스플라인 경로 따라가기                               │   │
│  │                                                         │   │
│  │  Camera Query                                           │   │
│  │  - 카메라 정보 접근                                     │   │
│  │  - 거리 기반 LOD                                        │   │
│  │                                                         │   │
│  │  Grid2D/3D                                              │   │
│  │  - 그리드 기반 시뮬레이션                               │   │
│  │  - 유체, 연기 등                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 데이터 인터페이스 사용

```cpp
// 스태틱 메시 DI 예시
// 모듈에서 메시 표면 위치 얻기
/*
Input: Static Mesh DI, Random Triangle Index
Output: Position, Normal, Tangent, UV

Sample Mesh Surface Position
├── Get Triangle (Random)
├── Get Barycentric Coords (Random)
└── Interpolate Vertex Attributes
*/

// Collision DI 예시
// 파티클이 표면에 충돌하는지 검사
/*
Perform Collision Query
├── Ray Start: Previous Position
├── Ray End: Current Position
├── Returns: Hit Position, Normal, Distance
└── On Hit: Bounce or Kill
*/
```

---

## 요약

Niagara 아키텍처 핵심:

1. **System** - 최상위 컨테이너, 여러 Emitter 관리
2. **Emitter** - 파티클 그룹, CPU/GPU 시뮬레이션 선택
3. **Module** - 개별 동작 단위, 스택으로 조합
4. **Parameter** - 네임스페이스로 구분, User 파라미터 노출
5. **Data Interface** - 외부 데이터 접근 (메시, 텍스처, 충돌 등)

모듈러 설계로 재사용성과 확장성이 뛰어납니다.

---

## 참고 자료

- [Niagara Key Concepts](https://docs.unrealengine.com/5.0/en-US/niagara-key-concepts/)
- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/13512787.html)
