# Ch.19 애니메이션 렌더링

스켈레탈 메시, 모프 타겟, 클로스 시뮬레이션의 렌더링을 분석합니다.

---

## 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                  애니메이션 렌더링 시스템                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Animation Pipeline                    │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │                                                          │   │
│  │  Animation       Skeletal         GPU              Final │   │
│  │  Evaluation  →   Skinning    →   Compute    →    Render │   │
│  │                                                          │   │
│  │  • Bone Transform  • Vertex      • Morph          • Draw │   │
│  │  • Blend Space     • Weights     • Cloth          • LOD  │   │
│  │  • State Machine   • Tangent     • Physics        • Cull │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  핵심 구성 요소:                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Skeletal     │  │ Animation    │  │ Physics      │         │
│  │ Mesh         │  │ Blueprint    │  │ Asset        │         │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤         │
│  │ • Bones      │  │ • AnimGraph  │  │ • Cloth      │         │
│  │ • Vertices   │  │ • Montage    │  │ • RigidBody  │         │
│  │ • Materials  │  │ • BlendSpace │  │ • Constraints│         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 핵심 주제

### [1. 스켈레탈 메시 렌더링](01-skeletal-mesh.md)
- 스켈레탈 메시 구조
- 본 트랜스폼 계산
- GPU 스키닝
- LOD 시스템

### [2. 애니메이션 시스템](02-animation-system.md)
- Animation Blueprint
- Blend Space
- State Machine
- 애니메이션 압축

### [3. 모프 타겟](03-morph-targets.md)
- 블렌드 셰이프 구조
- GPU 모프 타겟
- 페이셜 애니메이션
- 성능 최적화

### [4. 클로스 시뮬레이션](04-cloth-simulation.md)
- Chaos Cloth
- 컨스트레인트 시스템
- 콜리전 처리
- GPU 시뮬레이션

### [5. 애니메이션 최적화](05-animation-optimization.md)
- LOD와 컬링
- 애니메이션 버짓
- 멀티스레드 평가
- 프로파일링

---

## 렌더링 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│              Skeletal Mesh Rendering Pipeline                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Game Thread:                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Animation Evaluation                                    │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │   │
│  │  │ Update  │→ │ Blend   │→ │ IK      │→ │ Physics │    │   │
│  │  │ Anim    │  │ Poses   │  │ Solve   │  │ Blend   │    │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  Render Thread:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Skinning & Rendering                                    │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │   │
│  │  │ Upload  │→ │ GPU     │→ │ Morph   │→ │ Draw    │    │   │
│  │  │ Bones   │  │ Skin    │  │ Target  │  │ Mesh    │    │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 주요 클래스

| 클래스 | 역할 |
|--------|------|
| `USkeletalMesh` | 스켈레탈 메시 에셋 |
| `USkeletalMeshComponent` | 스켈레탈 메시 컴포넌트 |
| `UAnimInstance` | 애니메이션 인스턴스 |
| `FSkeletalMeshRenderData` | 렌더링 데이터 |
| `FSkeletalMeshObjectGPUSkin` | GPU 스키닝 오브젝트 |
| `FClothingSimulation` | 클로스 시뮬레이션 |

---

## 참고 자료

- [Skeletal Mesh Animation System](https://docs.unrealengine.com/animation/)
- [Animation Blueprint](https://docs.unrealengine.com/animation-blueprints/)
- [Cloth Simulation](https://docs.unrealengine.com/cloth/)
