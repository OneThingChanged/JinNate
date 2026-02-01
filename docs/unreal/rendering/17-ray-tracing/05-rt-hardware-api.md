# RT 하드웨어와 API

DXR, RTX 하드웨어를 설명합니다.

---

## DXR (DirectX Raytracing)

```
┌─────────────────────────────────────────────────────────────────┐
│                    DXR 셰이더 타입                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Ray Generation Shader                                       │
│     • 광선 생성 진입점                                         │
│     • DispatchRays()로 실행                                    │
│                                                                 │
│  2. Intersection Shader (선택적)                                │
│     • 커스텀 지오메트리 교차 테스트                            │
│     • 절차적 지오메트리용                                      │
│                                                                 │
│  3. Any-Hit Shader (선택적)                                     │
│     • 모든 교차점에서 호출                                     │
│     • Alpha Test 용도                                          │
│                                                                 │
│  4. Closest-Hit Shader                                          │
│     • 가장 가까운 교차점에서 호출                              │
│     • 셰이딩 계산                                              │
│                                                                 │
│  5. Miss Shader                                                 │
│     • 교차 없을 때 호출                                        │
│     • 스카이박스 등                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### DXR 코드 예시

```hlsl
// Ray Generation Shader
[shader("raygeneration")]
void RayGen()
{
    uint2 launchIndex = DispatchRaysIndex().xy;
    uint2 launchDim = DispatchRaysDimensions().xy;

    // 광선 설정
    RayDesc ray;
    ray.Origin = CameraPosition;
    ray.Direction = CalculateRayDirection(launchIndex, launchDim);
    ray.TMin = 0.001;
    ray.TMax = 10000.0;

    // 광선 추적
    RayPayload payload;
    TraceRay(
        AccelerationStructure,
        RAY_FLAG_NONE,
        0xFF,
        0,  // Hit Group Index
        1,  // Hit Group Count
        0,  // Miss Shader Index
        ray,
        payload
    );

    // 결과 저장
    OutputTexture[launchIndex] = payload.color;
}

// Closest Hit Shader
[shader("closesthit")]
void ClosestHit(inout RayPayload payload, BuiltInTriangleIntersectionAttributes attr)
{
    // 히트 정보로 셰이딩
    float3 hitPosition = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    float3 normal = ComputeNormal(attr);

    payload.color = CalculateLighting(hitPosition, normal);
}
```

---

## RT Core 하드웨어

```
┌─────────────────────────────────────────────────────────────────┐
│                    NVIDIA RT Core                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  SM (Streaming Multiprocessor)                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │   CUDA Cores    │   RT Core    │   Tensor Core         │   │
│  │   ┌───────┐     │  ┌───────┐   │   ┌───────┐          │   │
│  │   │ ■ ■ ■ │     │  │  RT   │   │   │Tensor │          │   │
│  │   │ ■ ■ ■ │     │  │       │   │   │       │          │   │
│  │   │ ■ ■ ■ │     │  │       │   │   │       │          │   │
│  │   └───────┘     │  └───────┘   │   └───────┘          │   │
│  │                 │              │                        │   │
│  │   일반 셰이더   │  BVH 순회    │   AI/DLSS             │   │
│  │   연산          │  교차 테스트 │                        │   │
│  │                 │              │                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  RT Core 역할:                                                  │
│  • 하드웨어 BVH 순회                                           │
│  • 하드웨어 Ray-Box 교차 테스트                                │
│  • 하드웨어 Ray-Triangle 교차 테스트                           │
│  • CUDA Core 해방 → 셰이딩에 집중                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## UE에서의 RT 사용

```cpp
// RT 활성화
r.RayTracing=1
r.RayTracing.Shadows=1
r.RayTracing.AmbientOcclusion=1
r.RayTracing.Reflections=1
r.RayTracing.GlobalIllumination=1

// 품질 설정
r.RayTracing.Reflections.MaxRoughness=0.6
r.RayTracing.Shadows.MaxBounces=1
```

---

## 참고 자료

- [DXR Specification](https://microsoft.github.io/DirectX-Specs/d3d/Raytracing.html)
- [NVIDIA RTX](https://developer.nvidia.com/rtx)
- [Ray Tracing Gems](https://www.realtimerendering.com/raytracinggems/)
- [원본 문서 (timlly)](https://www.cnblogs.com/timlly/p/16687324.html)
