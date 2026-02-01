# 05. 셰이더 최적화

셰이더 성능 최적화 기법, 점유율 관리, 디버깅 방법을 분석합니다.

---

## 개요

GPU 셰이더 최적화는 렌더링 성능의 핵심입니다. 올바른 최적화 전략은 프레임 레이트를 크게 향상시킬 수 있습니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    셰이더 최적화 영역                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    ALU (연산 장치)                        │   │
│  │  - 수학 연산 최적화                                       │   │
│  │  - 정밀도 선택 (half vs float)                           │   │
│  │  - 분기 최소화                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    메모리 (대역폭)                        │   │
│  │  - 텍스처 샘플링 최적화                                   │   │
│  │  - 캐시 활용                                             │   │
│  │  - 대역폭 절약                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    점유율 (Occupancy)                    │   │
│  │  - 레지스터 사용량                                       │   │
│  │  - 공유 메모리                                           │   │
│  │  - 웨이브/워프 관리                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU 아키텍처 이해

### 웨이브/워프 (Wave/Warp)

```
┌─────────────────────────────────────────────────────────────────┐
│                    GPU 실행 모델                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GPU                                                            │
│  ├── SM/CU (Streaming Multiprocessor / Compute Unit)           │
│  │   ├── Warp/Wave 0  ─── 32/64 스레드가 동시 실행              │
│  │   ├── Warp/Wave 1                                           │
│  │   ├── Warp/Wave 2                                           │
│  │   └── ...                                                   │
│  │                                                              │
│  ├── SM/CU                                                     │
│  │   └── ...                                                   │
│  └── ...                                                       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  벤더별 웨이브 크기                                       │   │
│  │  ─────────────────────────────────────────────────────  │   │
│  │  NVIDIA (Warp):  32 스레드                               │   │
│  │  AMD (Wave):     64 스레드 (Wave32 모드: 32)             │   │
│  │  Intel:          8-32 스레드 (SIMD 폭에 따라)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  SIMT (Single Instruction, Multiple Threads):                  │
│  - 웨이브 내 모든 스레드가 동일 명령어 실행                      │
│  - 분기 시 divergence 발생 → 성능 저하                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 레지스터와 점유율

```
┌─────────────────────────────────────────────────────────────────┐
│                    점유율 (Occupancy)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  점유율 = 활성 웨이브 수 / 최대 웨이브 수                        │
│                                                                 │
│  SM당 리소스 예시 (NVIDIA Ampere):                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  최대 웨이브: 64                                         │   │
│  │  레지스터: 65,536개                                      │   │
│  │  공유 메모리: 164 KB                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  레지스터 사용량에 따른 점유율:                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  레지스터/스레드    최대 웨이브    점유율                  │   │
│  │  ─────────────    ──────────    ──────                  │   │
│  │       32              64         100%                   │   │
│  │       64              32          50%                   │   │
│  │      128              16          25%                   │   │
│  │      255               8          12.5%                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  주의: 높은 점유율 ≠ 항상 좋은 성능                              │
│  - 레지스터 압박 → 스필링 → 메모리 접근 증가                    │
│  - 최적 점유율은 셰이더 특성에 따라 다름                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## ALU 최적화

### 수학 연산 최적화

```hlsl
// ❌ 비효율적인 코드
float3 Result = normalize(A) * length(B);

// ✅ 최적화된 코드
float3 Result = A * (length(B) / length(A));  // normalize 분해

// ❌ 비효율적: pow 사용
float Light = pow(NdotL, 2.0);

// ✅ 최적화: 직접 곱셈
float Light = NdotL * NdotL;

// ❌ 비효율적: 나눗셈
float Inv = 1.0 / X;

// ✅ 최적화: rcp 사용 (근사치, 빠름)
float Inv = rcp(X);

// ❌ 비효율적: sqrt + 나눗셈
float InvLen = 1.0 / sqrt(dot(V, V));

// ✅ 최적화: rsqrt 사용
float InvLen = rsqrt(dot(V, V));
```

### 내장 함수 활용

```hlsl
// GPU에 최적화된 내장 함수들
saturate(x)      // clamp(x, 0, 1) 대신 사용 - 무료
lerp(a, b, t)    // a + t * (b - a) 대신 사용
mad(a, b, c)     // a * b + c - FMA 명령어 활용
fma(a, b, c)     // 정밀한 fused multiply-add
min3(a, b, c)    // min(min(a, b), c) 대신
max3(a, b, c)    // max(max(a, b), c) 대신
rcp(x)           // 1.0 / x의 빠른 근사
rsqrt(x)         // 1.0 / sqrt(x)의 빠른 근사

// 조건부 선택
// ❌ 비효율적
float Result;
if (Condition)
    Result = A;
else
    Result = B;

// ✅ 효율적 (분기 없음)
float Result = Condition ? A : B;

// ✅ 더 효율적 (명시적 select)
float Result = lerp(B, A, Condition);
```

### 정밀도 선택

```hlsl
// 정밀도 타입
// float  (32-bit): 기본, 정확한 계산 필요시
// half   (16-bit): 충분한 경우 2배 처리량
// min16float:      최소 16-bit (플랫폼 의존)

// ✅ half 사용 권장 케이스
half3 Color;           // 색상 (0-1 범위)
half2 UV;              // 텍스처 좌표
half3 Normal;          // 정규화된 노멀
half Roughness;        // 머티리얼 파라미터

// ❌ float 필요 케이스
float3 WorldPosition;  // 월드 좌표 (정밀도 필요)
float Depth;           // 깊이 값
float2 ScreenUV;       // 정밀한 스크린 좌표

// 모바일/콘솔 최적화
#if MOBILE_PLATFORM
    #define PRECISION half
#else
    #define PRECISION float
#endif

PRECISION3 ComputeLighting(PRECISION3 Normal, PRECISION3 LightDir)
{
    PRECISION NdotL = saturate(dot(Normal, LightDir));
    return NdotL;
}
```

---

## 분기 최적화

### 분기 비용

```
┌─────────────────────────────────────────────────────────────────┐
│                    분기 (Branch) 비용                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Uniform Branch (모든 스레드가 같은 경로):                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  if (UniformValue > 0)  // 상수 버퍼 값 등               │   │
│  │      DoSomething();     // 비용: 거의 없음               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Divergent Branch (스레드마다 다른 경로):                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  if (PixelValue > 0.5)  // 픽셀마다 다름                 │   │
│  │      DoA();             // 양쪽 모두 실행!               │   │
│  │  else                                                   │   │
│  │      DoB();             // 비용: 양쪽 합산               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Divergence 시각화:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Wave (32 스레드):  TTTTTTTTTTTTTTTTFFFFFFFFFFFFFFFFFF  │   │
│  │                                                         │   │
│  │  if (Condition)                                         │   │
│  │      A();  ← T 스레드만 실행, F 스레드는 대기             │   │
│  │  else                                                   │   │
│  │      B();  ← F 스레드만 실행, T 스레드는 대기             │   │
│  │                                                         │   │
│  │  총 비용 = A() 비용 + B() 비용 (둘 다 실행됨)            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 분기 최적화 기법

```hlsl
// ❌ Divergent branch
void ProcessPixel(float Value)
{
    if (Value > Threshold)
    {
        // 복잡한 계산 A
        ExpensiveCalculationA();
    }
    else
    {
        // 복잡한 계산 B
        ExpensiveCalculationB();
    }
}

// ✅ 최적화 1: Branchless 연산
float Result = lerp(ResultB, ResultA, Value > Threshold);

// ✅ 최적화 2: Early-out (가능한 경우)
[branch]  // 힌트: 실제 분기 생성
if (EarlyOutCondition)
{
    return DefaultValue;  // 대부분 여기서 종료
}
// 나머지 복잡한 계산

// ✅ 최적화 3: Flatten (분기 제거)
[flatten]  // 힌트: 양쪽 모두 계산 후 선택
if (Condition)
    Result = A;
else
    Result = B;

// ✅ 최적화 4: 순열로 분기 제거
#if USE_FEATURE_A
    FeatureA();
#else
    FeatureB();
#endif
```

### Wave Intrinsics 활용

```hlsl
// Wave 레벨 최적화 (SM 6.0+)

// Wave 내 모든 스레드가 같은 조건인지 확인
if (WaveActiveAllTrue(Condition))
{
    // 모든 스레드가 true → uniform branch
    DoExpensiveWork();
}

// Wave 내 어떤 스레드라도 조건 만족하는지
if (WaveActiveAnyTrue(NeedsProcessing))
{
    // 하나라도 처리 필요
    Process();
}

// Wave 내 값 공유 (broadcast)
float FirstValue = WaveReadLaneFirst(MyValue);

// Wave 내 reduction
float Sum = WaveActiveSum(LocalValue);
float Max = WaveActiveMax(LocalValue);

// Lane 인덱스
uint LaneIndex = WaveGetLaneIndex();
```

---

## 메모리 최적화

### 텍스처 샘플링

```
┌─────────────────────────────────────────────────────────────────┐
│                    텍스처 샘플링 비용                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  샘플링 타입별 비용:                                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  타입                    상대 비용    설명               │   │
│  │  ─────────────────────  ──────────  ─────────────────  │   │
│  │  Load (point, no mip)       1x      가장 빠름           │   │
│  │  Sample (bilinear)          2x      필터링 비용         │   │
│  │  Sample (trilinear)         4x      밉맵 블렌딩         │   │
│  │  Sample (aniso 2x)          8x      비등방성 필터링     │   │
│  │  Sample (aniso 16x)        32x      고품질 필터링       │   │
│  │  SampleGrad                 +α      수동 미분           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  캐시 효율:                                                     │
│  - 인접 픽셀은 인접 텍셀 접근 → 캐시 히트                       │
│  - 무작위 접근 → 캐시 미스 → 레이턴시 증가                      │
│  - 밉맵 사용 → 캐시 효율 증가                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 텍스처 최적화 기법

```hlsl
// ❌ 비효율적: 반복 샘플링
float4 Color1 = Texture.Sample(Sampler, UV + Offset1);
float4 Color2 = Texture.Sample(Sampler, UV + Offset2);
float4 Color3 = Texture.Sample(Sampler, UV + Offset3);
float4 Color4 = Texture.Sample(Sampler, UV + Offset4);

// ✅ 최적화: Gather 사용 (2x2 텍셀을 한번에)
float4 RedChannel = Texture.GatherRed(Sampler, UV);
// RedChannel.x = (u, v+1), .y = (u+1, v+1)
// RedChannel.z = (u+1, v), .w = (u, v)

// ❌ 비효율적: 각 채널 별도 텍스처
float R = TextureR.Sample(Sampler, UV).r;
float G = TextureG.Sample(Sampler, UV).r;
float B = TextureB.Sample(Sampler, UV).r;

// ✅ 최적화: 채널 패킹
float3 RGB = TexturePacked.Sample(Sampler, UV).rgb;

// ✅ 밉맵 레벨 명시 (Compute Shader에서)
float4 Color = Texture.SampleLevel(Sampler, UV, MipLevel);

// ✅ 로드 사용 (필터링 불필요시)
int2 Coord = int2(UV * TextureSize);
float4 Color = Texture.Load(int3(Coord, 0));
```

### 메모리 접근 패턴

```hlsl
// ❌ 비효율적: 불규칙 접근
for (int i = 0; i < Count; i++)
{
    float Value = Buffer[RandomIndex[i]];  // 캐시 미스
}

// ✅ 최적화: 순차 접근
for (int i = 0; i < Count; i++)
{
    float Value = Buffer[BaseIndex + i];  // 캐시 히트
}

// ❌ 비효율적: AoS (Array of Structures)
struct Particle
{
    float3 Position;
    float3 Velocity;
    float Life;
};
StructuredBuffer<Particle> Particles;
float3 Pos = Particles[id].Position;

// ✅ 최적화: SoA (Structure of Arrays)
Buffer<float3> Positions;
Buffer<float3> Velocities;
Buffer<float> Lives;
float3 Pos = Positions[id];  // 연속 메모리 접근
```

---

## Compute Shader 최적화

### 스레드 그룹 설정

```hlsl
// 스레드 그룹 크기 결정
// - Wave 크기의 배수 (32 또는 64)
// - 공유 메모리 사용량 고려
// - 점유율 최적화

// ✅ 일반적인 선택
[numthreads(256, 1, 1)]  // 1D 작업 (후처리 등)
[numthreads(8, 8, 1)]    // 2D 작업 (이미지 처리)
[numthreads(4, 4, 4)]    // 3D 작업 (볼륨 처리)

// 디스패치 계산
uint3 GroupCount;
GroupCount.x = (TextureWidth + 7) / 8;   // 올림
GroupCount.y = (TextureHeight + 7) / 8;
GroupCount.z = 1;
```

### 공유 메모리 (LDS/Shared Memory)

```hlsl
// 공유 메모리 선언
groupshared float SharedData[256];
groupshared float2 TileData[8][8];

[numthreads(8, 8, 1)]
void CSMain(
    uint3 GroupId : SV_GroupID,
    uint3 GroupThreadId : SV_GroupThreadID,
    uint GroupIndex : SV_GroupIndex,
    uint3 DispatchThreadId : SV_DispatchThreadID
)
{
    // 1. 전역 메모리에서 공유 메모리로 로드
    SharedData[GroupIndex] = GlobalBuffer[DispatchThreadId.x];

    // 2. 동기화 (모든 스레드가 로드 완료 대기)
    GroupMemoryBarrierWithGroupSync();

    // 3. 공유 메모리에서 계산
    float Sum = 0;
    for (int i = 0; i < 256; i++)
    {
        Sum += SharedData[i];
    }

    // 4. 결과 쓰기
    if (GroupIndex == 0)
    {
        OutputBuffer[GroupId.x] = Sum;
    }
}
```

### Compute Shader 최적화 팁

```hlsl
// ✅ Bank Conflict 회피
// 공유 메모리는 32개 뱅크로 나뉨
// 같은 뱅크 동시 접근 시 직렬화

// ❌ Bank conflict
groupshared float Data[256];
float Value = Data[ThreadId * 32];  // 모든 스레드가 같은 뱅크

// ✅ Conflict-free
float Value = Data[ThreadId];  // 각 스레드 다른 뱅크

// ✅ 패딩으로 해결
groupshared float Data[256 + 32];  // 패딩 추가

// ✅ Atomic 최소화
// ❌ 느림
InterlockedAdd(GlobalCounter, 1);

// ✅ 빠름: Wave 레벨에서 먼저 합산
uint WaveSum = WaveActiveCountBits(true);
if (WaveGetLaneIndex() == 0)
{
    InterlockedAdd(GlobalCounter, WaveSum);
}

// ✅ Indirect Dispatch
// 이전 패스 결과에 따라 디스패치 크기 결정
Buffer<uint3> IndirectArgs;
DispatchIndirect(Shader, IndirectArgs, 0);
```

---

## 디버깅 도구

### RenderDoc 사용

```
┌─────────────────────────────────────────────────────────────────┐
│                    RenderDoc 활용                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  캡처 방법:                                                     │
│  1. RenderDoc 실행                                             │
│  2. UE 프로젝트를 RenderDoc으로 실행                            │
│  3. F12 또는 PrintScreen으로 프레임 캡처                        │
│                                                                 │
│  분석 기능:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Event Browser    - Draw call 목록                       │   │
│  │  Pipeline State   - 셰이더, 블렌드 상태 등                │   │
│  │  Texture Viewer   - 렌더 타겟 확인                        │   │
│  │  Mesh Viewer      - 버텍스 데이터                         │   │
│  │  Shader Viewer    - HLSL/SPIRV 디버깅                    │   │
│  │  Performance      - 타이밍 분석                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  셰이더 디버깅:                                                 │
│  - 픽셀 클릭 → Debug → 스텝 실행                               │
│  - 변수 값 확인                                                │
│  - 레지스터 상태                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 내장 디버깅

```cpp
// 셰이더 디버그 출력 (개발 빌드)
#if SHADER_DEBUG
    // 디버그 색상 출력
    OutColor = float4(DebugValue, 0, 0, 1);

    // 숫자 시각화
    OutColor = frac(Value);  // 0-1 반복으로 값 확인

    // 조건 시각화
    OutColor = Condition ? float4(0,1,0,1) : float4(1,0,0,1);
#endif

// 콘솔 명령어
// r.ShaderCompiler.Debug=1          셰이더 컴파일 로그
// r.Shaders.Optimize=0              최적화 비활성화 (디버깅용)
// r.DumpShaderDebugInfo=1           셰이더 중간 파일 덤프
// r.ShaderDevelopmentMode=1         개발 모드
```

### GPU 프로파일링

```cpp
// UE GPU 프로파일링 마커
SCOPED_GPU_STAT(RHICmdList, MyPass);

// 상세 프로파일링
SCOPED_DRAW_EVENT(RHICmdList, MyDetailedPass);

// 콘솔에서 확인
// stat gpu                     GPU 통계
// profilegpu                   GPU 프로파일러
// r.GPUBusyWait=1             GPU 타이밍 정확도 향상
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    성능 분석 체크리스트                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  병목 식별:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  □ GPU 시간이 긴 패스 확인                               │   │
│  │  □ Draw call 수 확인                                     │   │
│  │  □ 오버드로 확인 (Shader Complexity 뷰)                  │   │
│  │  □ 텍스처 해상도/포맷 확인                               │   │
│  │  □ 셰이더 순열 수 확인                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  최적화 체크:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  □ 불필요한 분기 제거                                    │   │
│  │  □ half 정밀도 활용                                      │   │
│  │  □ 텍스처 샘플 수 최소화                                 │   │
│  │  □ ALU와 메모리 균형                                     │   │
│  │  □ Wave intrinsics 활용                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 플랫폼별 최적화

### 모바일 최적화

```hlsl
// 모바일 특화 최적화

// ✅ Tile-based 렌더링 활용
// - 렌더 타겟 전환 최소화
// - On-chip 메모리 활용

// ✅ 정밀도 적극 활용
half4 MainPS() : SV_Target
{
    half3 Color = InputTexture.Sample(Sampler, UV).rgb;
    half3 Normal = NormalMap.Sample(Sampler, UV).rgb * 2.0h - 1.0h;

    // half 연산
    half NdotL = saturate(dot(Normal, LightDir));

    return half4(Color * NdotL, 1.0h);
}

// ✅ 복잡한 수학 함수 피하기
// pow, sin, cos 대신 LUT 또는 근사

// ❌ 비효율적
float Fresnel = pow(1 - NdotV, 5);

// ✅ Schlick 근사
half Fresnel = exp2((-5.55473h * NdotV - 6.98316h) * NdotV);

// ✅ Discard 최소화 (Tile 효율 저하)
#if !MOBILE_PLATFORM
    clip(Alpha - 0.5);  // 모바일에서는 피하기
#endif
```

### 콘솔 최적화

```hlsl
// 콘솔 특화 기능

// PS5/Xbox Series: Primitive Shader
// - Mesh Shader 지원
// - 더 유연한 지오메트리 처리

// Wave32 모드 (AMD RDNA)
#if WAVE32_MODE
    // 32 스레드 웨이브로 동작
    // 레지스터 효율 증가
#endif

// Async Compute 활용
// - 그래픽스와 컴퓨트 병렬 실행
// - 리소스 배리어 관리 주의
```

---

## 일반적인 최적화 실수

```
┌─────────────────────────────────────────────────────────────────┐
│                    피해야 할 패턴                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 과도한 정규화                                               │
│     ❌ normalize(normalize(V))                                  │
│     ✅ normalize(V)                                             │
│                                                                 │
│  2. 불필요한 행렬 연산                                          │
│     ❌ mul(mul(WorldMatrix, ViewMatrix), ProjMatrix)           │
│     ✅ mul(WorldViewProjMatrix, Position)  // 미리 합성        │
│                                                                 │
│  3. 런타임에 상수 계산                                          │
│     ❌ float Pi = acos(-1.0);                                  │
│     ✅ static const float Pi = 3.14159;                        │
│                                                                 │
│  4. 과도한 텍스처 의존                                          │
│     ❌ 모든 것을 텍스처로 (노이즈, 그라디언트 등)               │
│     ✅ 수학적 생성 가능한 것은 계산으로                         │
│                                                                 │
│  5. 무시되는 채널 샘플링                                        │
│     ❌ float R = Texture.Sample(S, UV).r; // 나머지 버림        │
│     ✅ 채널 패킹으로 여러 데이터 저장                           │
│                                                                 │
│  6. 동적 분기에서 텍스처 샘플링                                  │
│     ❌ if (x > 0) Color = Tex.Sample(...);  // Gradient 문제   │
│     ✅ 분기 밖에서 샘플링 후 조건부 사용                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 요약

셰이더 최적화 핵심:

1. **GPU 아키텍처 이해** - 웨이브/워프, 점유율, 메모리 계층
2. **ALU 최적화** - 내장 함수, 정밀도, MAD 활용
3. **분기 관리** - Divergence 최소화, Wave intrinsics 활용
4. **메모리 효율** - 캐시 친화적 접근, 텍스처 최적화
5. **Compute 최적화** - 스레드 그룹, 공유 메모리, 동기화
6. **디버깅** - RenderDoc, GPU 프로파일러, 체계적 분석

최적화는 측정 기반으로 진행해야 합니다. 추측하지 말고 프로파일링하세요.

---

## 참고 자료

- [GPU Gems 시리즈](https://developer.nvidia.com/gpugems)
- [AMD GPUOpen](https://gpuopen.com/)
- [RenderDoc 문서](https://renderdoc.org/docs/)
- [UE 셰이더 최적화 가이드](https://docs.unrealengine.com/5.0/en-US/shader-optimization-guidelines-for-unreal-engine/)
