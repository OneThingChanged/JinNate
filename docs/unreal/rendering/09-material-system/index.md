# Ch.09 머티리얼 시스템

> 원문: [剖析虚幻渲染体系（09）- 材质体系](https://www.cnblogs.com/timlly/p/15109132.html)

머티리얼(Material)은 UE 렌더링 체계에서 매우 중요한 기초 시스템으로, 머티리얼 블루프린트, 렌더링 상태, 기하학적 속성 등 다양한 데이터를 포함합니다.

---

## 9.1 본편 개요

본 장에서는 UE 머티리얼 시스템을 표면부터 저수준까지 체계적으로 분석합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 시스템 학습 경로                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  9.2 머티리얼 기초                                               │
│      ├── 9.2.1 UMaterial                                        │
│      ├── 9.2.2 UMaterialInstance                                │
│      ├── 9.2.3 FMaterialRenderProxy                             │
│      ├── 9.2.4 FMaterial, FMaterialResource                     │
│      └── 9.2.5 머티리얼 총람                                     │
│                                                                 │
│  9.3 머티리얼 메커니즘                                           │
│      ├── 9.3.1 머티리얼 렌더링                                   │
│      └── 9.3.2 머티리얼 컴파일                                   │
│                                                                 │
│  9.4 머티리얼 개발                                               │
│                                                                 │
│  9.5 본편 총결                                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 목차

| 문서 | 주제 | 핵심 내용 |
|------|------|----------|
| [01](01-material-basics.md) | 머티리얼 기초 (상) | UMaterial, UMaterialInstance, FMaterialRenderProxy |
| [02](02-material-classes.md) | 머티리얼 기초 (하) | FMaterial, FMaterialResource, 클래스 총람 |
| [03](03-material-rendering.md) | 머티리얼 렌더링 | 데이터 초기화, ShaderMap 전달, 렌더링 흐름 |
| [04](04-material-compilation.md) | 머티리얼 컴파일 | UMaterialExpression, HLSL 변환, 컴파일 흐름 |
| [05](05-material-development.md) | 머티리얼 개발 | 노드 확장, 템플릿 확장, 총결 |

---

## 클래스 계층 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                    머티리얼 클래스 계층                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  【게임 스레드】                                                 │
│                                                                 │
│  UMaterialInterface (추상 인터페이스)                            │
│      │                                                          │
│      ├── UMaterial (자산 파일, 마스터 머티리얼)                   │
│      │                                                          │
│      └── UMaterialInstance (파라미터 인스턴스)                   │
│              │                                                  │
│              ├── UMaterialInstanceConstant (정적, 에디터)        │
│              │                                                  │
│              └── UMaterialInstanceDynamic (동적, 런타임)         │
│                                                                 │
│  ─────────────────────────────────────────────────────────────  │
│                                                                 │
│  【렌더 스레드】                                                 │
│                                                                 │
│  FMaterialRenderProxy (렌더 프록시)                              │
│      │                                                          │
│      ├── FDefaultMaterialInstance (UMaterial용)                 │
│      │                                                          │
│      └── FMaterialInstanceResource (UMaterialInstance용)        │
│                                                                 │
│  FMaterial (추상) → FMaterialResource (구현)                     │
│      │                                                          │
│      └── ShaderMap, 파라미터, 속성 등 렌더링 데이터 관리          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 설계 의도

머티리얼 시스템이 게임 스레드(UMaterialInterface)와 렌더 스레드(FMaterial, FMaterialRenderProxy)로 분리된 이유:

1. **멀티스레드 안전성**: 두 스레드가 독립적으로 데이터 접근
2. **렌더링 성능**: 렌더 스레드가 ShaderMap을 자유롭게 관리
3. **데이터 분리**: 게임 로직과 렌더링 로직의 명확한 경계

---

## 참고 자료

- [원문 시리즈 (중국어)](https://www.cnblogs.com/timlly/p/15109132.html)
