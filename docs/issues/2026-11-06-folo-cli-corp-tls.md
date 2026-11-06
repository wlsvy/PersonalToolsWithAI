# 사내 TLS 검사로 folo CLI 연결 실패

- 날짜: 2026-11-06
- 대상: `folocli`(npm, Node 24), Windows 사내 네트워크

## 증상

| 도구 | 결과 |
|---|---|
| curl | `schannel: ... CRYPT_E_NO_REVOCATION_CHECK (0x80092012)` |
| Node `fetch` (folocli) | `SELF_SIGNED_CERT_IN_CHAIN` |

`https://api.folo.is`와 `https://app.folo.is` 모두 같았습니다.

## 원인

사내 네트워크가 HTTPS를 중간에서 풀어 검사합니다. 받은 인증서의 발급자가 Folo가 아니라 사내 CA(`O=Nexon, CN=NEXON`)입니다.

- curl(schannel)은 이 인증서의 폐기 여부를 확인하지 못해 실패합니다.
- Node는 자체 CA 목록만 믿고 Windows 인증서 저장소의 사내 루트 CA는 모릅니다.

Folo 접속이 차단된 것은 아닙니다. `curl --ssl-no-revoke`로는 200이 옵니다.

## 조치

사용자 환경 변수로 Node가 Windows 인증서 저장소도 믿게 했습니다.

```powershell
[Environment]::SetEnvironmentVariable("NODE_USE_SYSTEM_CA", "1", "User")
```

- Node 기본 CA 목록에 Windows 저장소를 더하는 설정입니다. 인증서 검증을 끄는 `NODE_TLS_REJECT_UNAUTHORIZED=0`과 다릅니다.
- 브라우저가 이미 같은 저장소를 믿으므로 새로 생기는 위험은 작습니다. 이 계정의 모든 Node 프로세스에 적용됩니다.
- 범위를 더 줄이려면 사내 루트 CA만 내보내 `NODE_EXTRA_CA_CERTS=<파일>`로 지정합니다.
- 설정 후 연 터미널과 nvim에만 적용됩니다.

설정 후 `folo timeline`은 TLS 오류 없이 `UNAUTHORIZED`(로그인 전)를 돌려줬습니다.

## curl로 확인

```sh
curl --ssl-no-revoke https://api.folo.is/better-auth/get-session \
  -H "Authorization: Bearer $FOLO_TOKEN" \
  -H "Cookie: __Secure-better-auth.session_token=$FOLO_TOKEN; better-auth.session_token=$FOLO_TOKEN"
```

토큰이 유효하면 세션 정보, 없거나 틀리면 `null`이 옵니다.
