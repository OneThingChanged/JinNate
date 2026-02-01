# Ch.13 렌더링 확장 및 커스터마이징

Unreal Engine 렌더링 시스템을 확장하고 커스터마이징하는 방법을 다룹니다.

---

## 개요

UE 렌더링 시스템은 확장 가능한 아키텍처로 설계되어 있습니다. 커스텀 렌더 패스, 셰이더, 플러그인을 통해 고유한 렌더링 기능을 구현할 수 있습니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   렌더링 확장 아키텍처                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    확장 포인트                             │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │                                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │  │
│  │  │ Custom      │  │  Custom     │  │  Custom     │       │  │
│  │  │ Passes      │  │  Shaders    │  │  Materials  │       │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │  │
│  │         │                │                │               │  │
│  │         ▼                ▼                ▼               │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │              Render Dependency Graph                 │ │  │
│  │  │                      (RDG)                          │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  │                          │                               │  │
│  │                          ▼                               │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │                    RHI Layer                        │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  │                          │                               │  │
│  │                          ▼                               │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │               Graphics API (D3D12/VK/Metal)         │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  │                                                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 문서 구성

| 문서 | 주제 | 핵심 내용 |
|------|------|----------|
| [01](01-custom-passes.md) | 커스텀 렌더 패스 | SceneViewExtension, 패스 삽입, 후처리 |
| [02](02-render-dependency-graph.md) | RDG 활용 | 리소스 관리, 패스 의존성, 최적화 |
| [03](03-plugin-development.md) | 렌더링 플러그인 | 모듈 구조, 셰이더 통합, 배포 |
| [04](04-shader-development.md) | 셰이더 개발 | USF 작성, 파라미터, 디버깅 |
| [05](05-advanced-techniques.md) | 고급 기법 | Compute, 비동기, 멀티패스 |

---

## 확장 방법 개요

### 1. SceneViewExtension

가장 간단한 확장 방법으로, 기존 파이프라인에 패스를 삽입합니다.

```cpp
class FMyViewExtension : public FSceneViewExtensionBase
{
public:
    virtual void SetupViewFamily(FSceneViewFamily& ViewFamily) override;
    virtual void PreRenderView_RenderThread(...) override;
    virtual void PostRenderBasePass_RenderThread(...) override;
};
```

### 2. 커스텀 렌더 패스

RDG를 사용하여 완전한 커스텀 패스를 구현합니다.

```cpp
void AddMyCustomPass(FRDGBuilder& GraphBuilder, ...)
{
    FRDGTextureRef OutputTexture = GraphBuilder.CreateTexture(...);

    auto* PassParameters = GraphBuilder.AllocParameters<FMyPassParameters>();
    PassParameters->Output = GraphBuilder.CreateUAV(OutputTexture);

    GraphBuilder.AddPass(
        RDG_EVENT_NAME("MyCustomPass"),
        PassParameters,
        ERDGPassFlags::Compute,
        [PassParameters](FRHIComputeCommandList& RHICmdList)
        {
            // 렌더링 로직
        });
}
```

### 3. 커스텀 셰이더

Global Shader나 Material Shader를 작성하여 확장합니다.

```cpp
// C++ 바인딩
class FMyGlobalShader : public FGlobalShader
{
    DECLARE_GLOBAL_SHADER(FMyGlobalShader);
    SHADER_USE_PARAMETER_STRUCT(FMyGlobalShader, FGlobalShader);

    BEGIN_SHADER_PARAMETER_STRUCT(FParameters, )
        SHADER_PARAMETER_TEXTURE(Texture2D, InputTexture)
        SHADER_PARAMETER_UAV(RWTexture2D<float4>, OutputTexture)
    END_SHADER_PARAMETER_STRUCT()
};
```

---

## 확장 유형별 사용 사례

```
┌─────────────────────────────────────────────────────────────────┐
│                    확장 유형 선택 가이드                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  사용 사례                          권장 방법                   │
│  ────────────────────────────────  ──────────────────────────  │
│  포스트 프로세스 효과 추가          SceneViewExtension          │
│  새로운 렌더 패스 삽입              RDG Custom Pass             │
│  G-Buffer 데이터 활용               Deferred Decal / Custom     │
│  GPU 계산 (시뮬레이션 등)           Compute Shader              │
│  머티리얼 기반 효과                 Custom Material Expression  │
│  전체 파이프라인 변경               Renderer 수정 (고급)        │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  복잡도:                                                        │
│                                                                 │
│  낮음 ──────────────────────────────────────────────▶ 높음     │
│  │                                                        │     │
│  Material    View        RDG Pass    Global      Renderer │     │
│  Expression  Extension              Shader      Modify    │     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 시작하기

### 필수 모듈 의존성

```cpp
// MyPlugin.Build.cs
PublicDependencyModuleNames.AddRange(new string[]
{
    "Core",
    "CoreUObject",
    "Engine",
    "RenderCore",
    "Renderer",
    "RHI",
    "Projects"
});
```

### 기본 프로젝트 구조

```
MyRenderingPlugin/
├── Source/
│   ├── MyPlugin.Build.cs
│   ├── Private/
│   │   ├── MyPlugin.cpp
│   │   ├── MyViewExtension.cpp
│   │   └── MyShaders.cpp
│   ├── Public/
│   │   ├── MyPlugin.h
│   │   └── MyViewExtension.h
│   └── Shaders/
│       └── Private/
│           └── MyShader.usf
└── MyPlugin.uplugin
```

---

## 주의사항

### 스레드 안전성

```cpp
// 렌더 스레드에서만 실행
ENQUEUE_RENDER_COMMAND(MyCommand)(
    [this](FRHICommandListImmediate& RHICmdList)
    {
        // 렌더 스레드 코드
    });

// 게임 스레드에서 렌더 데이터 접근 금지
check(IsInRenderingThread());
```

### 프레임 지연

```
┌─────────────────────────────────────────────────────────────────┐
│                     프레임 파이프라이닝                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frame N        Frame N+1       Frame N+2                       │
│  ┌─────────┐   ┌─────────┐    ┌─────────┐                      │
│  │ Game    │──▶│ Game    │───▶│ Game    │                      │
│  └────┬────┘   └────┬────┘    └────┬────┘                      │
│       │             │              │                            │
│       │   ┌─────────┘              │                            │
│       │   │                        │                            │
│       ▼   ▼                        ▼                            │
│       ┌─────────┐   ┌─────────┐   ┌─────────┐                  │
│       │ Render  │──▶│ Render  │──▶│ Render  │                  │
│       └─────────┘   └─────────┘   └─────────┘                  │
│                                                                 │
│  주의: 게임 스레드 데이터는 1-2 프레임 지연되어 렌더링됨        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 참고 자료

- [Unreal Engine Rendering Overview](https://docs.unrealengine.com/rendering-overview/)
- [RDG Documentation](https://docs.unrealengine.com/render-dependency-graph/)
- [Shader Development](https://docs.unrealengine.com/shader-development/)
