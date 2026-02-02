# Ch.11 RDG (Render Dependency Graph)

> 원문: [剖析虚幻渲染体系（11）- RDG](https://www.cnblogs.com/timlly/p/15217090.html)

UE4.22에서 도입된 렌더링 서브시스템으로, 유향 비순환 그래프(DAG) 기반의 스케줄링 시스템입니다.

---

## 11.1 본편 개요

**RDG (Rendering Dependency Graph)**는 전체 프레임 렌더링 파이프라인의 최적화를 위한 시스템입니다. 현대 그래픽 API(DirectX 12, Vulkan, Metal 2)의 기능을 활용하여 자동 비동기 컴퓨트 스케줄링, 효율적 메모리 관리, 배리어 관리 최적화를 제공합니다.

기존의 레거시 API(DirectX 11, OpenGL)에서는 드라이버가 캐시 플러시, 메모리 관리, 레이아웃 전환 등을 휴리스틱하게 처리했지만, 현대 API에서는 이러한 책임이 애플리케이션으로 이전되었습니다. RDG는 이러한 현대 API의 기능을 최대한 활용하여 전체 프레임 수준의 최적화를 수행합니다.

이 개념은 언리얼 엔진만의 것이 아닙니다. EA의 Frostbite 엔진이 2017년 GDC에서 발표한 **Frame Graph**가 유사한 기술을 먼저 구현했으며, 언리얼의 RDG는 이와 동등한 기능을 언리얼 아키텍처에 맞게 구현한 것입니다.

![RDG 의존성 그래프](../images/ch11/1617944-20201026110615588-1410809244.png)

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 실행 흐름                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Pass 수집   │ → │  Pass 컴파일 │ → │  Pass 실행   │         │
│  │   Phase     │    │    Phase    │    │    Phase    │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│        │                  │                  │                  │
│        ▼                  ▼                  ▼                  │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │ AddPass()   │    │ 의존성 분석  │    │ Lambda 실행  │         │
│  │ 리소스 생성  │    │ 배리어 처리  │    │ 리소스 해제  │         │
│  │ 상태 기록    │    │ Pass 컬링   │    │ 정리        │         │
│  └─────────────┘    └─────────────┘    └─────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 특징

RDG는 GPU 명령을 즉시 실행하지 않고, Lambda 기반의 렌더링 Pass를 수집합니다. 모든 Pass가 수집된 후 의존성을 분석하고 최적화된 순서로 실행합니다.

![RDG 클래스 구조](../images/ch11/1617944-20210125210618582-154442848.png)

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 핵심 원칙                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 【지연 실행 (Deferred Execution)】                           │
│     • Pass는 AddPass() 호출 시 즉시 실행되지 않음                │
│     • 모든 Pass 수집 후 Compile → Execute 순서로 진행            │
│                                                                 │
│  2. 【자동 리소스 관리】                                         │
│     • CreateTexture/CreateBuffer는 디스크립터만 기록             │
│     • 실제 할당은 필요할 때 수행                                 │
│     • 참조가 없으면 자동 해제                                    │
│                                                                 │
│  3. 【의존성 기반 스케줄링】                                      │
│     • Pass 간 실행 순서는 보장되지 않음                          │
│     • 오직 데이터 의존성만 보존됨                                │
│     • 출력에 영향 없는 Pass는 자동 컬링                          │
│                                                                 │
│  4. 【Pass 범위 내 접근】                                        │
│     • 리소스 접근은 Pass Lambda 내에서만 가능                    │
│     • Pass 파라미터에 선언된 리소스만 사용 가능                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 장점

| 기능 | 설명 |
|------|------|
| **자동 생명주기 관리** | 리소스가 사용될 때 할당되고 참조가 없으면 해제됨 |
| **메모리 앨리어싱** | 생명주기가 겹치지 않는 리소스는 동일 메모리 공유 |
| **배리어 최적화** | 중복 상태 전환 자동 제거, 배치 처리 |
| **Pass 컬링** | 출력에 영향 없는 Pass 자동 제거 |
| **Pass 병합** | 동일 렌더 타겟의 래스터 Pass를 단일 RenderPass로 병합 |
| **비동기 컴퓨트** | Graphics와 AsyncCompute 간 자동 동기화 |

---

## 주요 클래스

![RDG 내부 구조](../images/ch11/1617944-20210125210628739-2098335058.png)

```
┌─────────────────────────────────────────────────────────────────┐
│                    RDG 클래스 계층 구조                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  FRDGBuilder (그래프 빌더)                                       │
│  ├── CreateTexture() / CreateBuffer()     - 리소스 생성         │
│  ├── CreateSRV() / CreateUAV()            - 뷰 생성             │
│  ├── RegisterExternalTexture/Buffer()     - 외부 리소스 등록    │
│  ├── AddPass()                            - Pass 추가           │
│  ├── QueueTextureExtraction()             - 리소스 추출 예약    │
│  └── Execute()                            - 그래프 실행         │
│                                                                 │
│  FRDGResource (리소스 기반 클래스)                               │
│  ├── FRDGTexture                                                │
│  │   ├── FRDGTextureDesc                  - 텍스처 디스크립터   │
│  │   └── FRDGPooledTexture                - 풀링된 텍스처       │
│  └── FRDGBuffer                                                 │
│      ├── FRDGBufferDesc                   - 버퍼 디스크립터     │
│      └── FRDGPooledBuffer                 - 풀링된 버퍼         │
│                                                                 │
│  FRDGPass (Pass 기반 클래스)                                     │
│  ├── TRDGLambdaPass                       - Lambda 실행 Pass    │
│  └── FRDGSentinelPass                     - 경계 표시 Pass      │
│                                                                 │
│  FRDGAllocator                                                  │
│  └── MemStack 기반 메모리 관리                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 기본 사용 패턴

```cpp
void RenderMyFeature(FRHICommandListImmediate& RHICmdList, const FViewInfo& View)
{
    // 1. RDG Builder 생성
    FRDGBuilder GraphBuilder(RHICmdList, RDG_EVENT_NAME("MyFeature"));

    // 2. 리소스 생성
    FRDGTextureDesc RTDesc = FRDGTextureDesc::Create2D(
        View.ViewRect.Size(),
        PF_FloatRGBA,
        FClearValueBinding::Black,
        TexCreate_RenderTargetable | TexCreate_ShaderResource
    );
    FRDGTextureRef OutputTexture = GraphBuilder.CreateTexture(RTDesc, TEXT("MyOutput"));

    // 3. Pass 추가
    FMyPassParameters* Parameters = GraphBuilder.AllocParameters<FMyPassParameters>();
    Parameters->OutputTexture = GraphBuilder.CreateUAV(OutputTexture);

    GraphBuilder.AddPass(
        RDG_EVENT_NAME("MyPass"),
        Parameters,
        ERDGPassFlags::Compute,
        [Parameters](FRHICommandList& RHICmdList)
        {
            // 렌더링 코드
        }
    );

    // 4. 결과 추출 (필요시)
    TRefCountPtr<IPooledRenderTarget> ExtractedRT;
    GraphBuilder.QueueTextureExtraction(OutputTexture, &ExtractedRT);

    // 5. 실행
    GraphBuilder.Execute();
}
```

---

## 문서 구성

| 문서 | 내용 |
|------|------|
| [RDG 개요](01-rdg-overview.md) | RDG 소개, 배경, 현대 그래픽 API와의 관계, Frame Graph |
| [RDG 기초](02-rdg-fundamentals.md) | 열거형, 리소스 타입, Pass 클래스, FRDGBuilder |
| [RDG 메커니즘](03-rdg-mechanisms.md) | AddPass, Compile, Execute 상세 분석, 배리어 처리 |
| [RDG 개발](04-rdg-development.md) | 리소스 생성, Pass 추가, 실제 사용법, 전체 예제 |
| [RDG 디버깅](05-rdg-debugging.md) | 즉시 실행 모드, 콘솔 변수, 문제 해결, 총결 |

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/15217090.html)
- [UE 공식 문서 - RDG](https://docs.unrealengine.com/5.0/en-US/render-dependency-graph-in-unreal-engine/)
- [GDC 2017 - FrameGraph: Extensible Rendering Architecture in Frostbite](https://www.gdcvault.com/play/1024612/FrameGraph-Extensible-Rendering-Architecture-in)
