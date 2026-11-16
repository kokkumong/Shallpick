# 카카오 로그인 + Supabase 설정

앱 흐름: 카카오톡(없으면 카카오계정 웹) 로그인 → 카카오 **id_token** 발급 → Supabase Auth 에 id_token 으로 로그인 → 첫 로그인이면 `public.profiles` 행 자동 생성.

## 1. Kakao Developers

1. [콘솔](https://developers.kakao.com/console/app) 에서 앱 생성
2. **[앱] > [플랫폼 키] > [네이티브 앱 키]**: iOS 번들 ID `com.kokkumong.Shallpick` 등록
3. **[카카오 로그인] > [사용 설정]**: 상태 ON
4. **[카카오 로그인] > [OpenID Connect]**: 상태 ON ← 꼭 켜야 id_token 이 나옵니다
5. **[카카오 로그인] > [동의항목]**: 닉네임, 프로필 사진 설정 (이메일은 비즈 앱 전환 후 가능)
6. **[앱] > [플랫폼 키] > [REST API 키] > [클라이언트 시크릿]**: 코드 생성 → 활성화 ON → 저장
7. **[앱] > [플랫폼 키]** 에서 `네이티브 앱 키`, `REST API 키` 복사

## 2. Supabase

1. [supabase.com](https://supabase.com/dashboard) 에서 프로젝트 생성
2. **SQL Editor** 에서 `supabase/migrations/` 의 파일을 이름 순서대로 실행
   - `20261116000000_create_profiles.sql` (프로필)
   - `20261116010000_create_folders.sql` (폴더 / 초대 코드)
   - `20261116020000_my_folders.sql` (메인 화면 폴더 목록)
   - `20261116030000_create_messages.sql` (폴더 채팅 + Realtime)
   (Supabase CLI 를 쓰면 `supabase link` 후 `supabase db push`)
3. **Authentication > Sign In / Providers > Kakao** 활성화
   - **REST API Key (Client ID)**: `REST_API_키,네이티브_앱_키` ← 쉼표로 두 개 입력
     iOS SDK 로 받은 id_token 의 `aud` 는 네이티브 앱 키라서, 이걸 빼면 `Unacceptable audience in id_token` 오류가 납니다.
   - **Client Secret Code**: 1-6 에서 만든 값
   - **Allow users without an email**: ON (이메일 동의항목을 안 받는 경우)
4. Kakao Developers **카카오 로그인 > Redirect URI** 에 Supabase 화면에 표시된 Callback URL 추가
   (웹 OAuth 용. 지금 앱 흐름에서는 쓰이지 않지만 provider 저장 시 필요)

## 3. 앱 키 넣기

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig` 에 값을 채웁니다. 이 파일은 git 에 올라가지 않습니다.

- `KAKAO_NATIVE_APP_KEY`: 네이티브 앱 키
- `SUPABASE_URL`: `https:/$()/<project-ref>.supabase.co` (xcconfig 에서 `//` 는 주석이라 이렇게 씁니다)
- `SUPABASE_KEY`: Project Settings > API Keys 의 publishable key (또는 legacy anon key)

값을 바꾼 뒤에는 Xcode 에서 Clean Build (⇧⌘K) 후 실행하세요.

## 자주 나는 에러

| 에러 문구 | 원인 / 해결 |
|---|---|
| `[misconfigured] IOS bundleId validation failed` | 카카오 콘솔 [플랫폼 키] > [네이티브 앱 키] 의 iOS 번들 ID 가 `com.kokkumong.Shallpick` 과 다름 |
| `Unacceptable audience in id_token: [...]` | Supabase Kakao 설정의 REST API Key 칸에 네이티브 앱 키가 빠짐 → `REST키,네이티브키` |
| `카카오 ID 토큰을 받지 못했어요` | 카카오 콘솔 OpenID Connect 가 OFF |
| `앱 키가 설정되지 않았어요` | `Config/Secrets.xcconfig` 비어 있음 / URL 을 `https://` 로 적음 (`https:/$()/` 로) |

## 참고

- supabase-swift 2.55.x 에는 `signInWithIdToken` 의 `.kakao` provider 가 아직 없어서
  `SupabaseKakaoSignIn` 에서 Auth REST API(`/auth/v1/token?grant_type=id_token`)를 직접 호출합니다.
  SDK 에 `.kakao` 가 릴리스되면 `client.auth.signInWithIdToken` 으로 바꾸면 됩니다.
- 시뮬레이터에는 카카오톡이 없으므로 카카오계정(웹) 로그인으로 진행됩니다.
