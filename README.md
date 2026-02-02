# 나태한진태 블로그 작업 가이드

## 개요

이 폴더는 Claude를 활용한 블로그 콘텐츠 생성 작업의 지침과 기록을 보관합니다.

## 파일 구조

```
blog/
├── CLAUDE.md          # Claude 작업 지침서 (핵심)
├── README.md          # 이 파일
└── PROGRESS.md        # 진행 상황 기록
```

## 빠른 시작

### 새 챕터 생성 요청
```
Ch.20 진행해줘
```

### 여러 챕터 연속 생성
```
20, 21, 22 챕터 진행해줘
```

### Git 커밋 및 푸시
```
커밋하고 푸시해줘
```

## 주요 명령어

| 요청 | 설명 |
|------|------|
| `XX챕터` 또는 `XX ㄱ` | 해당 챕터 생성 |
| `푸시해줘` | git commit & push |
| `목차 몇까지?` | 현재 진행 상황 확인 |

## 환경 설정

### 토큰 제한 늘리기 (선택)
```powershell
$env:CLAUDE_CODE_MAX_OUTPUT_TOKENS = 64000
claude
```

### MkDocs 로컬 서버
```bash
mkdocs serve
```

## 관련 경로

- 블로그 루트: `G:\AI\CLI\Claude\`
- 문서 폴더: `G:\AI\CLI\Claude\docs\`
- 렌더링 시리즈: `G:\AI\CLI\Claude\docs\unreal\rendering\`
- 설정 파일: `G:\AI\CLI\Claude\mkdocs.yml`
