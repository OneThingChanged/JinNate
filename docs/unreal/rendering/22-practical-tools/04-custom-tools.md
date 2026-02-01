# 커스텀 도구 개발

Editor Utility Widget, Commandlet, 플러그인 등 커스텀 도구 개발 방법을 분석합니다.

---

## Editor Utility Widget

```
┌─────────────────────────────────────────────────────────────────┐
│                  Editor Utility Widget                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Editor Utility Widget = 에디터 전용 UI 도구                     │
│                                                                 │
│  생성 방법:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  1. Content Browser 우클릭                               │   │
│  │  2. Editor Utilities → Editor Utility Widget             │   │
│  │  3. 부모 클래스: EditorUtilityWidget                    │   │
│  │  4. Widget Designer에서 UI 구성                         │   │
│  │  5. Graph에서 로직 작성                                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  실행 방법:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  • 에셋 우클릭 → Run Editor Utility Widget              │   │
│  │  • 또는 Window → Editor Utility Widgets 탭에서 선택     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  사용 예시:                                                     │
│  • 에셋 배치 자동화                                             │
│  • 머티리얼 일괄 수정                                           │
│  • 레벨 검증 도구                                               │
│  • 커스텀 프로파일링 UI                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Editor Utility Widget 예제

```cpp
// C++ 기반 Editor Utility Widget
UCLASS()
class UMyEditorUtilityWidget : public UEditorUtilityWidget
{
    GENERATED_BODY()

public:
    // 선택된 액터 처리
    UFUNCTION(BlueprintCallable, Category = "Utility")
    void ProcessSelectedActors()
    {
        // 에디터 선택 서브시스템
        UEditorActorSubsystem* EditorActorSubsystem =
            GEditor->GetEditorSubsystem<UEditorActorSubsystem>();

        TArray<AActor*> SelectedActors = EditorActorSubsystem->GetSelectedLevelActors();

        for (AActor* Actor : SelectedActors)
        {
            // 처리 로직
            ProcessActor(Actor);
        }
    }

    // 모든 스태틱 메시 LOD 설정
    UFUNCTION(BlueprintCallable, Category = "Utility")
    void SetupLODsForAllMeshes()
    {
        // 에셋 레지스트리에서 모든 스태틱 메시 검색
        FAssetRegistryModule& AssetRegistry =
            FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry");

        TArray<FAssetData> AllMeshes;
        AssetRegistry.Get().GetAssetsByClass(
            UStaticMesh::StaticClass()->GetFName(),
            AllMeshes
        );

        for (const FAssetData& AssetData : AllMeshes)
        {
            if (UStaticMesh* Mesh = Cast<UStaticMesh>(AssetData.GetAsset()))
            {
                SetupLOD(Mesh);
            }
        }
    }

private:
    void ProcessActor(AActor* Actor);
    void SetupLOD(UStaticMesh* Mesh);
};

// Blueprint에서 호출 가능한 에디터 전용 함수
UFUNCTION(BlueprintCallable, Category = "Editor", meta = (CallInEditor = "true"))
void MyEditorOnlyFunction()
{
    // 에디터에서만 실행되는 코드
}
```

---

## Editor Utility Blueprint

```
┌─────────────────────────────────────────────────────────────────┐
│                Editor Utility Blueprint                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Actor-based 에디터 도구:                                       │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  생성:                                                   │   │
│  │  Content Browser → Editor Utilities →                    │   │
│  │  Editor Utility Blueprint (부모: EditorUtilityActor)    │   │
│  │                                                          │   │
│  │  특징:                                                   │   │
│  │  • 레벨에 배치 가능                                      │   │
│  │  • Construction Script 활용                              │   │
│  │  • 에디터 이벤트 바인딩                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Action Asset:                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Content Browser → Editor Utilities →                    │   │
│  │  Editor Utility Blueprint (부모: ActorActionUtility)    │   │
│  │                                                          │   │
│  │  액터 우클릭 메뉴에 액션 추가                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 액터 액션 유틸리티

```cpp
// 액터 컨텍스트 메뉴에 추가되는 액션
UCLASS()
class UMyActorActionUtility : public UActorActionUtility
{
    GENERATED_BODY()

public:
    // 선택된 액터에서 실행 가능한 액션
    UFUNCTION(CallInEditor, Category = "MyTools")
    void AlignActorsToGround()
    {
        // 선택된 액터들을 바닥에 정렬
        UEditorActorSubsystem* EditorSubsystem =
            GEditor->GetEditorSubsystem<UEditorActorSubsystem>();

        TArray<AActor*> Actors = EditorSubsystem->GetSelectedLevelActors();

        for (AActor* Actor : Actors)
        {
            FVector Location = Actor->GetActorLocation();

            FHitResult Hit;
            FVector TraceStart = Location + FVector(0, 0, 100);
            FVector TraceEnd = Location - FVector(0, 0, 10000);

            if (Actor->GetWorld()->LineTraceSingleByChannel(
                Hit, TraceStart, TraceEnd, ECC_WorldStatic))
            {
                Actor->SetActorLocation(Hit.ImpactPoint);
            }
        }
    }

    UFUNCTION(CallInEditor, Category = "MyTools")
    void RandomizeRotation()
    {
        UEditorActorSubsystem* EditorSubsystem =
            GEditor->GetEditorSubsystem<UEditorActorSubsystem>();

        for (AActor* Actor : EditorSubsystem->GetSelectedLevelActors())
        {
            FRotator RandomRotation(0, FMath::RandRange(0.0f, 360.0f), 0);
            Actor->SetActorRotation(RandomRotation);
        }
    }
};
```

---

## Commandlet

```
┌─────────────────────────────────────────────────────────────────┐
│                       Commandlet                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Commandlet = 명령줄에서 실행하는 에디터 태스크                  │
│                                                                 │
│  실행 방법:                                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  UnrealEditor.exe ProjectName -run=MyCommandlet [Args]  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  사용 예시:                                                     │
│  • 에셋 검증/변환                                               │
│  • 빌드 자동화                                                  │
│  • 데이터 마이그레이션                                          │
│  • CI/CD 파이프라인                                             │
│                                                                 │
│  내장 Commandlet:                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ResavePackages      패키지 재저장                       │   │
│  │  FixupRedirects      리디렉터 수정                       │   │
│  │  DumpAssetRegistry   에셋 레지스트리 덤프               │   │
│  │  GenerateDistillFileset 배포 파일셋 생성               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Commandlet 구현

```cpp
// 커스텀 Commandlet
UCLASS()
class UValidateAssetsCommandlet : public UCommandlet
{
    GENERATED_BODY()

public:
    UValidateAssetsCommandlet()
    {
        LogToConsole = true;
    }

    virtual int32 Main(const FString& Params) override
    {
        UE_LOG(LogTemp, Log, TEXT("=== Asset Validation Started ==="));

        // 파라미터 파싱
        TArray<FString> Tokens;
        TArray<FString> Switches;
        ParseCommandLine(*Params, Tokens, Switches);

        // 에셋 레지스트리 로드
        FAssetRegistryModule& AssetRegistry =
            FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry");

        // 텍스처 검증
        TArray<FAssetData> Textures;
        AssetRegistry.Get().GetAssetsByClass(
            UTexture2D::StaticClass()->GetFName(), Textures
        );

        int32 ErrorCount = 0;
        for (const FAssetData& Asset : Textures)
        {
            if (!ValidateTexture(Asset))
            {
                ErrorCount++;
            }
        }

        UE_LOG(LogTemp, Log, TEXT("=== Validation Complete: %d Errors ==="), ErrorCount);

        return ErrorCount > 0 ? 1 : 0;  // 실패/성공 반환
    }

private:
    bool ValidateTexture(const FAssetData& AssetData)
    {
        UTexture2D* Texture = Cast<UTexture2D>(AssetData.GetAsset());
        if (!Texture) return true;

        // 4K 이상 텍스처 경고
        if (Texture->GetSizeX() > 4096 || Texture->GetSizeY() > 4096)
        {
            UE_LOG(LogTemp, Warning, TEXT("Large texture: %s (%dx%d)"),
                *AssetData.AssetName.ToString(),
                Texture->GetSizeX(),
                Texture->GetSizeY());
            return false;
        }

        return true;
    }
};

// 실행: UnrealEditor.exe MyProject -run=ValidateAssets
```

---

## 플러그인 개발

```
┌─────────────────────────────────────────────────────────────────┐
│                   Plugin Development                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  플러그인 구조:                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Plugins/                                                │   │
│  │  └── MyPlugin/                                          │   │
│  │      ├── MyPlugin.uplugin                               │   │
│  │      ├── Source/                                        │   │
│  │      │   └── MyPlugin/                                  │   │
│  │      │       ├── MyPlugin.Build.cs                      │   │
│  │      │       ├── Public/                                │   │
│  │      │       │   └── MyPlugin.h                         │   │
│  │      │       └── Private/                               │   │
│  │      │           └── MyPlugin.cpp                       │   │
│  │      ├── Content/                                       │   │
│  │      └── Resources/                                     │   │
│  │          └── Icon128.png                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  플러그인 타입:                                                 │
│  • Runtime: 게임에서 사용                                       │
│  • Editor: 에디터에서만 사용                                    │
│  • Developer: 개발 중에만 사용                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 플러그인 모듈

```cpp
// MyPlugin.h
#pragma once

#include "Modules/ModuleManager.h"

class FMyPluginModule : public IModuleInterface
{
public:
    virtual void StartupModule() override;
    virtual void ShutdownModule() override;

private:
    void RegisterMenuExtensions();
    void UnregisterMenuExtensions();

    TSharedPtr<FExtender> MenuExtender;
};

// MyPlugin.cpp
#include "MyPlugin.h"
#include "LevelEditor.h"

#define LOCTEXT_NAMESPACE "FMyPluginModule"

void FMyPluginModule::StartupModule()
{
    UE_LOG(LogTemp, Log, TEXT("MyPlugin Started"));

    // 메뉴 확장 등록
    RegisterMenuExtensions();
}

void FMyPluginModule::ShutdownModule()
{
    UnregisterMenuExtensions();
}

void FMyPluginModule::RegisterMenuExtensions()
{
    // 레벨 에디터 메뉴에 항목 추가
    FLevelEditorModule& LevelEditorModule =
        FModuleManager::LoadModuleChecked<FLevelEditorModule>("LevelEditor");

    MenuExtender = MakeShareable(new FExtender());
    MenuExtender->AddMenuExtension(
        "WindowLayout",
        EExtensionHook::After,
        nullptr,
        FMenuExtensionDelegate::CreateLambda([](FMenuBuilder& MenuBuilder)
        {
            MenuBuilder.AddMenuEntry(
                LOCTEXT("MyToolLabel", "My Tool"),
                LOCTEXT("MyToolTooltip", "Opens My Tool"),
                FSlateIcon(),
                FUIAction(FExecuteAction::CreateLambda([]()
                {
                    // 도구 열기 로직
                }))
            );
        })
    );

    LevelEditorModule.GetMenuExtensibilityManager()->AddExtender(MenuExtender);
}

IMPLEMENT_MODULE(FMyPluginModule, MyPlugin)

#undef LOCTEXT_NAMESPACE
```

### uplugin 파일

```json
{
    "FileVersion": 3,
    "Version": 1,
    "VersionName": "1.0",
    "FriendlyName": "My Plugin",
    "Description": "A custom plugin for rendering tools",
    "Category": "Rendering",
    "CreatedBy": "Developer",
    "CreatedByURL": "",
    "DocsURL": "",
    "MarketplaceURL": "",
    "SupportURL": "",
    "CanContainContent": true,
    "IsBetaVersion": false,
    "IsExperimentalVersion": false,
    "Installed": false,
    "Modules": [
        {
            "Name": "MyPlugin",
            "Type": "Editor",
            "LoadingPhase": "Default"
        }
    ]
}
```

---

## Blutility (Blueprint Utility)

```cpp
// Blueprint에서 호출 가능한 에디터 함수
UFUNCTION(BlueprintCallable, Category = "EditorTools",
    meta = (CallInEditor = "true"))
static void BatchProcessMaterials()
{
    // 모든 머티리얼 가져오기
    FAssetRegistryModule& AssetRegistry =
        FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry");

    TArray<FAssetData> Materials;
    AssetRegistry.Get().GetAssetsByClass(
        UMaterial::StaticClass()->GetFName(), Materials
    );

    for (const FAssetData& AssetData : Materials)
    {
        if (UMaterial* Material = Cast<UMaterial>(AssetData.GetAsset()))
        {
            // 머티리얼 처리
            Material->TwoSided = false;
            Material->PostEditChange();
            Material->MarkPackageDirty();
        }
    }

    UE_LOG(LogTemp, Log, TEXT("Processed %d materials"), Materials.Num());
}

// Asset Action으로 사용 (에셋 우클릭 메뉴)
UFUNCTION(BlueprintCallable, Category = "AssetTools",
    meta = (CallInEditor = "true"))
static void ProcessSelectedAssets()
{
    // Content Browser에서 선택된 에셋 가져오기
    TArray<FAssetData> SelectedAssets;
    GEditor->GetContentBrowserSelections(SelectedAssets);

    for (const FAssetData& Asset : SelectedAssets)
    {
        UE_LOG(LogTemp, Log, TEXT("Selected: %s"), *Asset.AssetName.ToString());
    }
}
```

---

## 주요 클래스 요약

| 클래스 | 용도 |
|--------|------|
| `UEditorUtilityWidget` | UI 기반 에디터 도구 |
| `UActorActionUtility` | 액터 컨텍스트 메뉴 액션 |
| `UCommandlet` | 명령줄 태스크 |
| `IModuleInterface` | 플러그인 모듈 |
| `UEditorActorSubsystem` | 에디터 액터 조작 |

---

## 참고 자료

- [Editor Utility Widgets](https://docs.unrealengine.com/editor-utility-widgets/)
- [Commandlets](https://docs.unrealengine.com/commandlets/)
- [Plugin Development](https://docs.unrealengine.com/plugin-development/)
