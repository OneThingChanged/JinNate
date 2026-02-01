# 스테레오 렌더링

효율적인 스테레오 렌더링 기법과 구현 방식을 분석합니다.

---

## 렌더링 방식

### Multi-Pass vs Single-Pass

```
┌─────────────────────────────────────────────────────────────────┐
│                  스테레오 렌더링 방식 비교                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Multi-Pass Stereo:                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  CPU Work (2배):                                        │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │ Pass 1 (Left)                                     │  │   │
│  │  │ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐      │  │   │
│  │  │ │Visible │→│DrawCall│→│DrawCall│→│DrawCall│ ... │  │   │
│  │  │ └────────┘ └────────┘ └────────┘ └────────┘      │  │   │
│  │  │                                                   │  │   │
│  │  │ Pass 2 (Right)                                    │  │   │
│  │  │ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐      │  │   │
│  │  │ │Visible │→│DrawCall│→│DrawCall│→│DrawCall│ ... │  │   │
│  │  │ └────────┘ └────────┘ └────────┘ └────────┘      │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  │  • 호환성 최고                                           │   │
│  │  • CPU 오버헤드 2배                                      │   │
│  │  • 모든 플랫폼 지원                                      │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Instanced Stereo (Single-Pass):                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  CPU Work (1배):                                        │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │ Single Pass (Instanced)                           │  │   │
│  │  │ ┌────────┐ ┌─────────────────────────────────┐    │  │   │
│  │  │ │Visible │→│ DrawCall (Instance × 2)         │    │  │   │
│  │  │ └────────┘ └─────────────────────────────────┘    │  │   │
│  │  │                      │                             │  │   │
│  │  │            ┌─────────┴─────────┐                  │  │   │
│  │  │            ▼                   ▼                  │  │   │
│  │  │        Instance 0         Instance 1              │  │   │
│  │  │        (Left Eye)         (Right Eye)             │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  │  • CPU 오버헤드 ~1배                                     │   │
│  │  • GPU 인스턴싱 활용                                     │   │
│  │  • PC VR 권장                                           │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Instanced Stereo

### 구현 원리

```cpp
// Instanced Stereo 버텍스 셰이더
void MainVS(
    in float4 Position : POSITION,
    in uint InstanceId : SV_InstanceID,
    out float4 OutPosition : SV_POSITION,
    out uint OutEyeIndex : TEXCOORD7)
{
    // 인스턴스 ID로 눈 구분
    // Instance 0 = Left Eye
    // Instance 1 = Right Eye
    OutEyeIndex = InstanceId & 1;

    // 해당 눈의 뷰-프로젝션 매트릭스 선택
    float4x4 ViewProjection = EyeViewProjection[OutEyeIndex];

    // 월드 변환
    float4 WorldPos = mul(Position, LocalToWorld);

    // 뷰-프로젝션 변환
    OutPosition = mul(WorldPos, ViewProjection);
}

// 레이어 라우팅 (지오메트리 셰이더 또는 확장)
void RouteToLayer(inout float4 Position, uint EyeIndex)
{
    // Viewport 또는 렌더 타겟 레이어 선택
    // 왼쪽: Viewport 0 / Layer 0
    // 오른쪽: Viewport 1 / Layer 1
}
```

### 프로젝트 설정

```cpp
// Instanced Stereo 활성화
// Project Settings → Rendering → VR

// DefaultEngine.ini
[/Script/Engine.RendererSettings]
vr.InstancedStereo=True

// 요구사항:
// - DX11 Feature Level 11
// - Vulkan 1.1+
// - Shader Model 5.0+

// 제한사항:
// - 일부 포스트 프로세스 호환성 이슈
// - 커스텀 셰이더 수정 필요할 수 있음
// - 디버깅 복잡도 증가
```

---

## Mobile Multi-View

### OVR_multiview 확장

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Multi-View 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  GL_OVR_multiview2 Extension:                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  버텍스 셰이더:                                          │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │ #extension GL_OVR_multiview2 : require           │  │   │
│  │  │                                                   │  │   │
│  │  │ layout(num_views = 2) in;                        │  │   │
│  │  │                                                   │  │   │
│  │  │ uniform mat4 ViewMatrix[2];                      │  │   │
│  │  │ uniform mat4 ProjectionMatrix[2];                │  │   │
│  │  │                                                   │  │   │
│  │  │ void main() {                                    │  │   │
│  │  │     int viewID = gl_ViewID_OVR;  // 0 or 1      │  │   │
│  │  │     mat4 VP = ProjectionMatrix[viewID] *         │  │   │
│  │  │              ViewMatrix[viewID];                 │  │   │
│  │  │     gl_Position = VP * worldPos;                 │  │   │
│  │  │ }                                                │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  │  프레임버퍼:                                             │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │      Texture2DArray (2 layers)                   │  │   │
│  │  │  ┌─────────────────┬─────────────────┐           │  │   │
│  │  │  │    Layer 0      │    Layer 1      │           │  │   │
│  │  │  │   (Left Eye)    │   (Right Eye)   │           │  │   │
│  │  │  └─────────────────┴─────────────────┘           │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  • 버텍스 처리 1회 (양쪽 눈 동시)                              │
│  • 하드웨어 레벨 최적화                                        │
│  • Adreno/Mali GPU에서 최적                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 설정

```cpp
// Mobile Multi-View 활성화
// Project Settings → Rendering → VR

// DefaultEngine.ini
[/Script/Engine.RendererSettings]
vr.MobileMultiView=True
vr.MobileMultiView.Direct=True

// 요구사항:
// - OpenGL ES 3.0+ with OVR_multiview2
// - Vulkan with VK_KHR_multiview
// - Quest 필수

// 호환성:
// - 대부분의 머티리얼 호환
// - 포스트 프로세스 주의 필요
// - 일부 이펙트 수정 필요
```

---

## 뷰포트 구성

### Side-by-Side vs Array Texture

```
┌─────────────────────────────────────────────────────────────────┐
│                  렌더 타겟 레이아웃                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Side-by-Side (Packed):                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │         Single Render Target                     │    │   │
│  │  │  ┌───────────────┬───────────────┐              │    │   │
│  │  │  │               │               │              │    │   │
│  │  │  │   Left Eye    │   Right Eye   │              │    │   │
│  │  │  │               │               │              │    │   │
│  │  │  └───────────────┴───────────────┘              │    │   │
│  │  │       Width×2, Height                            │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  │                                                          │   │
│  │  • 단일 렌더 타겟                                        │   │
│  │  • 뷰포트로 영역 구분                                    │   │
│  │  • 일부 효과에서 블리딩 주의                             │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Texture Array (Layered):                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌───────────────┐    ┌───────────────┐                 │   │
│  │  │   Layer 0     │    │   Layer 1     │                 │   │
│  │  │  (Left Eye)   │    │  (Right Eye)  │                 │   │
│  │  │               │    │               │                 │   │
│  │  │   Width×1     │    │   Width×1     │                 │   │
│  │  │   Height      │    │   Height      │                 │   │
│  │  └───────────────┘    └───────────────┘                 │   │
│  │                                                          │   │
│  │  • 완전히 분리된 렌더 타겟                               │   │
│  │  • Multi-View에 최적                                    │   │
│  │  • 블리딩 없음                                          │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Hidden Area Mesh

### 렌즈 외곽 최적화

```cpp
// Hidden Area Mesh
// 렌즈를 통해 보이지 않는 영역을 마스킹

class FHiddenAreaMesh
{
    // 각 눈별 마스크 메시
    FVertexBufferRHIRef LeftEyeMesh;
    FVertexBufferRHIRef RightEyeMesh;

    void GenerateMesh(const TArray<FVector2D>& HiddenVertices)
    {
        // HMD SDK에서 제공하는 숨겨진 영역 버텍스
        // 이 영역을 덮는 메시 생성

        // 렌더링 시:
        // 1. Hidden Area Mesh를 먼저 그려서 Depth에 기록
        // 2. 실제 씬 렌더링 시 이 영역은 자동으로 Early-Z 탈락
    }
};

// 적용 효과
/*
┌─────────────────────────────────────────────────────────────────┐
│                  Hidden Area Mesh 효과                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  렌더 타겟 (사각형)         실제 가시 영역 (원형/이상형)          │
│  ┌─────────────────┐       ┌─────────────────┐                 │
│  │█████████████████│       │████         ████│                 │
│  │██             ██│       │█    ╭─────╮    █│                 │
│  │█               █│       │    │     │     │                 │
│  │                 │   →   │    │     │     │                 │
│  │█               █│       │    │     │     │                 │
│  │██             ██│       │█    ╰─────╯    █│                 │
│  │█████████████████│       │████         ████│                 │
│  └─────────────────┘       └─────────────────┘                 │
│                                                                 │
│  █ = 렌더링 스킵 (10-15% 절약)                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
*/
```

---

## Late Latching

### 마지막 순간 업데이트

```cpp
// Late Latching 구현
// 렌더링 직전에 최신 HMD 포즈 적용

class FLateLatchingSystem
{
    void UpdateLateLatching(FRHICommandList& RHICmdList)
    {
        // 1. GPU 타임라인에서 최신 포즈 요청
        FXRTrackingSystem* XRSystem = GEngine->XRSystem.Get();

        FQuat CurrentOrientation;
        FVector CurrentPosition;

        // 가장 최신 포즈 가져오기
        XRSystem->GetCurrentPose(
            IXRTrackingSystem::HMDDeviceId,
            CurrentOrientation,
            CurrentPosition);

        // 2. 뷰 매트릭스 업데이트 (GPU에서)
        FMatrix NewViewMatrix = CalculateViewMatrix(
            CurrentPosition, CurrentOrientation);

        // 3. 상수 버퍼 업데이트
        UpdateViewUniformBuffer(RHICmdList, NewViewMatrix);
    }
};

// 효과:
// - 추가 5-10ms 지연 감소
// - 더 정확한 헤드 트래킹
// - Judder 감소
```

---

## 스테레오 레이어

### Compositor Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                  스테레오 레이어 구조                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  레이어 스택 (컴포지터):                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────┐  ← Overlay    │   │
│  │  │         UI Layer (Quad)             │    (앞)       │   │
│  │  └─────────────────────────────────────┘                │   │
│  │                    ▼                                     │   │
│  │  ┌─────────────────────────────────────┐  ← Eye Buffer │   │
│  │  │         3D Scene                     │    (메인)     │   │
│  │  └─────────────────────────────────────┘                │   │
│  │                    ▼                                     │   │
│  │  ┌─────────────────────────────────────┐  ← Underlay   │   │
│  │  │         Skybox Layer                 │    (뒤)       │   │
│  │  └─────────────────────────────────────┘                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  레이어 타입:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Quad:     평면 레이어 (UI, 비디오)                       │   │
│  │ Cylinder: 곡면 레이어 (파노라마 UI)                      │   │
│  │ Cube:     큐브맵 레이어 (스카이박스)                     │   │
│  │ Equirect: 360도 비디오                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  장점:                                                          │
│  • 해상도 손실 없음 (네이티브 해상도)                           │
│  • 렌즈 왜곡 후 샘플링 (선명)                                   │
│  • ATW 적용 가능                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### UE 스테레오 레이어 컴포넌트

```cpp
// 스테레오 레이어 사용
UPROPERTY(EditAnywhere)
UStereoLayerComponent* UILayer;

void SetupStereoLayer()
{
    UILayer = NewObject<UStereoLayerComponent>(this);

    // 레이어 타입
    UILayer->SetLayerType(EStereoLayerType::Quad);

    // 크기 및 위치
    UILayer->SetQuadSize(FVector2D(100, 100));  // cm
    UILayer->SetRelativeLocation(FVector(200, 0, 0));  // 2m 앞

    // 텍스처
    UILayer->SetTexture(UIRenderTarget);

    // 우선순위 (높을수록 앞)
    UILayer->SetPriority(100);

    // 양쪽 눈에 표시
    UILayer->bSupportsDepth = false;
    UILayer->bLiveTexture = true;
}
```

---

## 다음 단계

- [VR 최적화](03-vr-optimization.md)에서 VR 특화 최적화 기법을 학습합니다.
