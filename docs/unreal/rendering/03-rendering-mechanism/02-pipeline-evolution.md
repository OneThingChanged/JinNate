# 02. 메시 드로잉 파이프라인 진화

> DrawingPolicy에서 FMeshDrawCommand로의 아키텍처 변화

---

## 목차

1. [UE4.22 이전 아키텍처](#1-ue422-이전-아키텍처)
2. [UE4.22+ 아키텍처](#2-ue422-아키텍처)
3. [변화의 이유](#3-변화의-이유)
4. [주요 개선사항](#4-주요-개선사항)

---

## 1. UE4.22 이전 아키텍처 {#1-ue422-이전-아키텍처}

### 1.1 DrawingPolicy 기반

![이전 파이프라인](../images/ch03/1617944-20210319203846059-346871767.jpg)
*UE4.22 이전 메시 드로잉 파이프라인*

```
FMeshBatch ──→ FDrawingPolicy ──→ RHI Commands
                     │
                     └─→ 매 프레임 재생성
```

### 1.2 문제점

| 문제점 | 설명 |
|--------|------|
| **캐싱 불가** | 드로우 명령을 매 프레임 재생성 |
| **재정렬 어려움** | 명령 생성과 실행이 결합 |
| **GPU Driven 어려움** | 중간 표현 부재 |
| **병렬화 제한** | DrawingPolicy 상태 의존 |

---

## 2. UE4.22+ 아키텍처 {#2-ue422-아키텍처}

### 2.1 FMeshDrawCommand 도입

![새 파이프라인](../images/ch03/1617944-20210319203908808-1155568886.jpg)
*UE4.22+ 메시 드로잉 파이프라인*

```
FMeshBatch ──→ FMeshDrawCommand ──→ RHI Commands
                     │
                     └─→ 캐싱 가능!
```

### 2.2 새로운 흐름

```cpp
// 1. FMeshBatch 수집
void GatherDynamicMeshElements(...)
{
    Proxy->GetDynamicMeshElements(Views, Collector);
}

// 2. FMeshDrawCommand 생성
void FMeshPassProcessor::AddMeshBatch(const FMeshBatch& Batch)
{
    FMeshDrawCommand DrawCommand;
    BuildMeshDrawCommand(Batch, DrawCommand);
    DrawList.Add(DrawCommand);
}

// 3. 정렬 및 제출
void SubmitMeshDrawCommands(TArray<FMeshDrawCommand>& Commands)
{
    Commands.Sort(FCompareFMeshDrawCommands());

    for (const FMeshDrawCommand& Command : Commands)
    {
        Command.SubmitDraw(RHICmdList);
    }
}
```

---

## 3. 변화의 이유 {#3-변화의-이유}

### 3.1 하드웨어 트렌드

- **GPU 성능 증가**: CPU가 병목
- **멀티코어 CPU**: 병렬 명령 생성 필요
- **레이트레이싱**: 새로운 렌더링 패러다임

### 3.2 소프트웨어 요구사항

- **정적 메시 캐싱**: 대부분의 오브젝트는 정적
- **동적 인스턴싱**: 유사 오브젝트 자동 배칭
- **GPU Scene**: GPU 측 프리미티브 데이터

---

## 4. 주요 개선사항 {#4-주요-개선사항}

### 4.1 성능 향상

| 기능 | 설명 | 효과 |
|------|------|------|
| **정적 메시 캐싱** | 로드 시 명령 사전 생성 | CPU 사용률 감소 |
| **PSO 캐싱** | 파이프라인 상태 재사용 | 상태 변경 감소 |
| **동적 인스턴싱** | 유사 명령 자동 병합 | 드로우 콜 감소 |
| **병렬 명령 생성** | 멀티스레드 처리 | 프레임 시간 감소 |

### 4.2 결과

![최적화](../images/ch03/1617944-20210319204219614-13890387.png)
*Fortnite 테스트: DepthPass와 BasePass 드로우 콜 대폭 감소*

---

## 다음 문서

[03. 가시성과 수집](03-scene-visibility.md)에서 컬링 시스템을 살펴봅니다.
