# 모바일 렌더링 개요

모바일 GPU 아키텍처의 특성과 UE의 모바일 렌더링 파이프라인을 분석합니다.

---

## 모바일 GPU 아키텍처

### Tile-Based Rendering

```
┌─────────────────────────────────────────────────────────────────┐
│                  Tile-Based 렌더링 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  화면 분할:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ┌────┬────┬────┬────┬────┬────┬────┬────┐              │   │
│  │  │ 00 │ 01 │ 02 │ 03 │ 04 │ 05 │ 06 │ 07 │              │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │ 08 │ 09 │ 10 │ 11 │ 12 │ 13 │ 14 │ 15 │              │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │ 16 │ 17 │ 18 │ 19 │ 20 │ 21 │ 22 │ 23 │              │   │
│  │  ├────┼────┼────┼────┼────┼────┼────┼────┤              │   │
│  │  │ 24 │ 25 │ 26 │ 27 │ 28 │ 29 │ 30 │ 31 │              │   │
│  │  └────┴────┴────┴────┴────┴────┴────┴────┘              │   │
│  │                                                          │   │
│  │  타일 크기: 16×16 ~ 32×32 픽셀 (GPU 마다 다름)           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  처리 순서:                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  1. Binning Pass (전체 지오메트리)                       │   │
│  │     ┌───────────────────────────────────────────┐       │   │
│  │     │ 모든 삼각형 → 타일별 리스트 생성          │       │   │
│  │     └───────────────────────────────────────────┘       │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │  2. Rendering Pass (타일별)                              │   │
│  │     ┌───────────────────────────────────────────┐       │   │
│  │     │ Tile 0: Load → Render → Store            │       │   │
│  │     │ Tile 1: Load → Render → Store            │       │   │
│  │     │ Tile 2: Load → Render → Store            │       │   │
│  │     │ ...                                        │       │   │
│  │     └───────────────────────────────────────────┘       │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### On-Chip Memory

```cpp
// 타일 메모리 구조 (개념적)
struct TileMemory
{
    // 컬러 버퍼 (On-Chip)
    // 32×32 타일 × 4 bytes (RGBA8) = 4KB
    uint8 ColorBuffer[TILE_SIZE * TILE_SIZE * 4];

    // 깊이/스텐실 버퍼 (On-Chip)
    // 32×32 × 4 bytes (D24S8) = 4KB
    uint8 DepthStencilBuffer[TILE_SIZE * TILE_SIZE * 4];

    // MSAA 샘플 (On-Chip)
    // 4x MSAA = 4배 메모리
    uint8 MSAASamples[TILE_SIZE * TILE_SIZE * 4 * MSAA_COUNT];

    // 총 On-Chip 메모리 사용: ~32KB per tile
};

// TBDR 장점
// 1. 외부 메모리 대역폭 최소화
// 2. 타일 내 렌더링은 빠른 On-Chip 메모리 사용
// 3. MSAA가 효율적 (Resolve만 메모리 접근)
```

### Hidden Surface Removal (HSR)

```
┌─────────────────────────────────────────────────────────────────┐
│                  PowerVR HSR 기술                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  기존 방식 (Early-Z):                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Triangle A → Fragment Shader → Z-Test (Pass) → Write   │   │
│  │  Triangle B → Fragment Shader → Z-Test (Fail) → Discard │   │
│  │                    ▲                                     │   │
│  │                    │                                     │   │
│  │              낭비된 셰이딩                                │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  HSR (PowerVR):                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Binning: 모든 삼각형의 깊이 정보 수집                   │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │  HSR: 각 픽셀에서 최종 보이는 삼각형만 선택              │   │
│  │                         │                                │   │
│  │                         ▼                                │   │
│  │  Shading: 선택된 삼각형만 Fragment Shader 실행           │   │
│  │                                                          │   │
│  │  → 오버드로우 완전 제거 (이론적)                         │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  주의: Alpha Test/Discard 사용 시 HSR 무효화                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## UE 모바일 렌더러

### 렌더링 설정

```cpp
// 모바일 프로젝트 설정
// DefaultEngine.ini

[/Script/Engine.RendererSettings]
; 모바일 HDR
r.Mobile.HDR=True
r.Mobile.HDR32bpp=False

; 모바일 셰이딩 경로
r.Mobile.ShadingPath=0  ; 0=Forward

; 모바일 MSAA
r.Mobile.MSAA=4

; 모바일 섀도우
r.Mobile.Shadow.CSMShaderCulling=1
r.Mobile.Shadow.MaxCSMResolution=1024

; 모바일 피처
r.Mobile.DisableVertexFog=0
r.Mobile.AllowDitheredLODTransition=1
```

### 모바일 렌더 패스

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Render Pass 순서                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame Start                                                    │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────┐                   │
│  │         Visibility & Culling            │                   │
│  │  • Frustum Culling                      │                   │
│  │  • Distance Culling                     │                   │
│  │  • Precomputed Visibility               │                   │
│  └────────────────┬────────────────────────┘                   │
│                   │                                             │
│                   ▼                                             │
│  ┌─────────────────────────────────────────┐                   │
│  │         Shadow Depth Pass               │                   │
│  │  • CSM Rendering (1-2 캐스케이드)       │                   │
│  │  • Modulated Shadows (선택적)           │                   │
│  └────────────────┬────────────────────────┘                   │
│                   │                                             │
│                   ▼                                             │
│  ┌─────────────────────────────────────────┐                   │
│  │         Mobile Base Pass                │                   │
│  │  • Forward Lighting                     │                   │
│  │  • Shadow Sampling                      │                   │
│  │  • 환경 반사                             │                   │
│  └────────────────┬────────────────────────┘                   │
│                   │                                             │
│                   ▼                                             │
│  ┌─────────────────────────────────────────┐                   │
│  │         Translucency Pass               │                   │
│  │  • 정렬된 반투명 오브젝트                │                   │
│  └────────────────┬────────────────────────┘                   │
│                   │                                             │
│                   ▼                                             │
│  ┌─────────────────────────────────────────┐                   │
│  │         Post Process                    │                   │
│  │  • 톤 매핑                               │                   │
│  │  • 블룸 (선택적)                         │                   │
│  │  • FXAA/TAA                             │                   │
│  └─────────────────────────────────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 렌더 타겟 관리

### FrameBuffer Fetch

```cpp
// FrameBuffer Fetch (GL_EXT_shader_framebuffer_fetch)
// 현재 픽셀의 프레임버퍼 값을 셰이더에서 직접 읽기

// GLSL 예시
#extension GL_EXT_shader_framebuffer_fetch : require

layout(location = 0) inout vec4 fragColor;

void main()
{
    // 기존 프레임버퍼 값 읽기 (메모리 접근 없음)
    vec4 existingColor = fragColor;

    // 블렌딩 직접 수행
    vec4 newColor = CalculateColor();
    fragColor = mix(existingColor, newColor, newColor.a);
}

// UE에서 활용
// - Decal 블렌딩
// - 반투명 처리
// - 커스텀 블렌드 모드
```

### Memoryless Attachments

```cpp
// Vulkan Memoryless Attachments
// On-Chip 메모리만 사용, 외부 메모리 저장 안 함

VkAttachmentDescription depthAttachment = {};
depthAttachment.format = VK_FORMAT_D24_UNORM_S8_UINT;
depthAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;  // 저장 안 함
depthAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
depthAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;

// 메모리 최적화
VkImageCreateInfo imageInfo = {};
imageInfo.usage = VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT |
                  VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;

// 메모리 할당
VkMemoryAllocateInfo allocInfo = {};
allocInfo.memoryTypeIndex = FindMemoryType(
    VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT);
```

---

## 모바일 API

### Vulkan vs OpenGL ES

```
┌─────────────────────────────────────────────────────────────────┐
│                  Vulkan vs OpenGL ES 비교                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  항목             Vulkan              OpenGL ES 3.x             │
│  ─────────────────────────────────────────────────────────────  │
│  CPU 오버헤드     낮음                높음                       │
│  멀티스레딩       네이티브 지원       제한적                     │
│  드라이버         얇음                두꺼움                     │
│  메모리 제어      명시적              암묵적                     │
│  파이프라인       사전 컴파일         런타임 컴파일             │
│  렌더패스         명시적 정의         암묵적                     │
│                                                                 │
│  UE에서 권장:                                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • Android: Vulkan 우선 (Fallback: ES 3.1)              │   │
│  │ • iOS: Metal (OpenGL ES 미지원)                        │   │
│  │ • 콘솔: 전용 API                                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Metal 특성 (iOS)

```cpp
// Metal 고유 기능
// 1. Tile Shading (iOS 11+)
@interface MTLRenderPassDescriptor
@property (nullable) MTLTileRenderPipelineDescriptor *tileDescriptor;
@end

// 2. Imageblocks (On-Chip 메모리 직접 접근)
struct Imageblock {
    half4 color [[color(0)]];
    float depth [[depth]];
};

kernel void tileShader(imageblock<Imageblock> data,
                       uint2 tid [[thread_position_in_threadgroup]])
{
    // On-Chip 메모리에서 직접 읽기/쓰기
    Imageblock pixel = data.read(tid);
    pixel.color = ProcessColor(pixel.color);
    data.write(pixel, tid);
}

// 3. Argument Buffers (리소스 간접 접근)
struct MaterialData {
    texture2d<float> albedo;
    texture2d<float> normal;
    sampler texSampler;
};
```

---

## Scalability

### 디바이스 프로파일

```cpp
// DeviceProfiles.ini

[Android_Low]
+CVars=r.Mobile.MSAA=0
+CVars=r.Mobile.HDR=0
+CVars=r.Shadow.MaxResolution=512
+CVars=r.PostProcessAAQuality=0
+CVars=foliage.DensityScale=0.4

[Android_Mid]
+CVars=r.Mobile.MSAA=2
+CVars=r.Mobile.HDR=1
+CVars=r.Shadow.MaxResolution=1024
+CVars=r.PostProcessAAQuality=3
+CVars=foliage.DensityScale=0.7

[Android_High]
+CVars=r.Mobile.MSAA=4
+CVars=r.Mobile.HDR=1
+CVars=r.Shadow.MaxResolution=2048
+CVars=r.PostProcessAAQuality=4
+CVars=foliage.DensityScale=1.0

// 런타임 프로파일 선택
void SelectDeviceProfile()
{
    FString GPUFamily = FPlatformMisc::GetGPUFamily();

    if (GPUFamily.Contains("Adreno 6") ||
        GPUFamily.Contains("Mali-G7"))
    {
        UDeviceProfileManager::Get().SetActiveProfile("Android_High");
    }
    else if (GPUFamily.Contains("Adreno 5") ||
             GPUFamily.Contains("Mali-G5"))
    {
        UDeviceProfileManager::Get().SetActiveProfile("Android_Mid");
    }
    else
    {
        UDeviceProfileManager::Get().SetActiveProfile("Android_Low");
    }
}
```

---

## 모바일 특수 기능

### Mobile Deferred

```
┌─────────────────────────────────────────────────────────────────┐
│                  Mobile Deferred (제한적)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Forward와의 차이:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                          │   │
│  │  Mobile Deferred (r.Mobile.ShadingPath=1)               │   │
│  │                                                          │   │
│  │  Pass 1: G-Buffer                                       │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │ • Albedo + Specular (RGBA8)                     │   │   │
│  │  │ • Normal + Roughness (RGBA8)                    │   │   │
│  │  │ • Depth (D24)                                   │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                         │                               │   │
│  │                         ▼                               │   │
│  │  Pass 2: Lighting (FrameBuffer Fetch 사용)             │   │
│  │  ┌─────────────────────────────────────────────────┐   │   │
│  │  │ • On-Chip G-Buffer 읽기                         │   │   │
│  │  │ • 라이팅 계산                                    │   │   │
│  │  │ • 직접 출력                                      │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  요구사항:                                                       │
│  • GL_EXT_shader_framebuffer_fetch                             │
│  • 또는 Vulkan Subpass                                         │
│  • 또는 Metal Tile Shading                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 디버깅

### 모바일 렌더링 디버그

```cpp
// 콘솔 명령어
r.Mobile.Debug.ShowGBuffer    // G-Buffer 시각화
r.Mobile.Debug.ShowOverdraw   // 오버드로우 시각화
r.Mobile.ShowMaterialComplexity  // 머티리얼 복잡도

// Stat 명령어
stat GPU                      // GPU 타이밍
stat RHI                      // RHI 통계
stat SceneRendering           // 렌더링 통계
stat MobileSceneRendering     // 모바일 특화 통계

// GPU 프로파일러
r.GPUCrashDebugging 1         // GPU 크래시 디버깅
r.GPUCrashDump 1              // GPU 덤프 활성화
```

---

## 다음 단계

- [모바일 셰이더](02-mobile-shaders.md)에서 ES3.1 셰이더 최적화를 학습합니다.
