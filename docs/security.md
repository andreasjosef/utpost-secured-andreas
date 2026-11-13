# Säkerhet – Utpost

*Mall (M8). Byt ut exempelraderna mot era egna fynd. Minst tre rader ska ha ett riktigt fynd, en fix i en PR och ett test som var rött före fixen. "Gäller inte oss, för …" är också ett svar – men bara om det är sant. Listan följer OWASP Top 10 (2025).*

**Datum:** 2026-11-13
**Hotbilden i en mening:** ______ (vad är värt att skydda i Utpost, och vem är angriparen? Användarnas turer och bilder, redaktionens guider, och – när vi lanserar – kontona. Angriparen är oftast ett skript, inte en person.)

## Autentiseringen (M8)

- Lösenord: ______ (hur lagras de, med vilket schema? Var i koden?)
- Token: ______ (vad står i den, hur länge gäller den, var ligger den i klienten, vad händer vid omladdning?)
- Skyddade routes: ______ (vilka anrop kräver token, vilka kräver rollen editor, och var sitter kontrollen – i klientens router eller i API:et?)

## OWASP Top 10 – genomgång

| # | Risk | Gäller oss? | Vad vi hittade (fil, endpoint) | Vad vi gjorde (PR) | Kontroll (testet som var rött före fixen, eller curl) |
|---|---|---|---|---|---|
| A01 | Broken Access Control | ja | `PUT /api/guides/:id` (`api/src/routes/guides.ts`) hade varken inloggning eller rollkontroll och skrev `req.body` rakt in i databasen – vem som helst kunde ändra redaktionens guider | `requireUser` + `requireRole('editor')` på routen, body valideras med `guideUpdateSchema` (400 vid fel) ([PR #1](https://github.com/andreasjosef/utpost-secured-andreas/pull/1)) | testerna *PUT /api/guides/:id utan token ger 401*, *en medlem får inte ändra guider (403) – bara rollen editor* och *en redaktör kan ändra – och får en validerad guide tillbaka* i `api/src/routes/routes.test.js`; Integration [rött mot mallen](https://github.com/andreasjosef/utpost-secured-andreas/actions/runs/43422981076), [grönt efter fixen](https://github.com/andreasjosef/utpost-secured-andreas/actions/runs/43424242350) |
| A02 | Security Misconfiguration | ja | `app.use(cors())` = `Access-Control-Allow-Origin: *`; inga säkerhetsheaders från nginx och `server_tokens` på (ZAP: 10020, 10021, 10036, 10038 = FAIL-NEW); `api/Dockerfile` körde som root (Trivy DS-0002) | CORS borttagen ([PR #1](https://github.com/andreasjosef/utpost-secured-andreas/pull/1)); `client/security-headers.conf` i varje location, `server_tokens off`, `USER node` i `api/Dockerfile`, `DS-0002` för nginx-imagen undantagen med motivering i `.trivyignore` ([PR #2](https://github.com/andreasjosef/utpost-secured-andreas/pull/2)) | testet *API:et skickar ingen Access-Control-Allow-Origin – ingen annan sajt får läsa svaren* ([rött](https://github.com/andreasjosef/utpost-secured-andreas/actions/runs/43422981076) → [grönt](https://github.com/andreasjosef/utpost-secured-andreas/actions/runs/43424242350)); ZAP baseline (10038, 10021, 10020, 10036 = FAIL i `.zap/rules.tsv`); `curl -I http://localhost:3001/` visar CSP och `nosniff` |
| A03 | Software Supply Chain Failures | ja | `npm audit --omit=dev`: 8 sårbarheter (1 moderate, 6 high, 1 critical). Värst: `proxy-addr` (critical, IP-spoofing, transitiv via express, fix via `npm audit fix`). Enda major: `drizzle-orm` <0.45.2 (high, SQL-injektion via identifierare, direkt) | `npm audit fix` + `drizzle-orm` 0.45 installerat för hand, testerna gröna – 0 sårbarheter ([PR #2](https://github.com/andreasjosef/utpost-secured-andreas/pull/2)) | jobbet *Säkerhet* ([rött på npm audit](https://github.com/andreasjosef/utpost-secured-andreas/actions/runs/43425021421) → grönt); [PR #3](https://github.com/andreasjosef/utpost-secured-andreas/pull/3) med express 4.17.1 med flit gjorde *Säkerhet* rött på *Beroenden – npm audit* – stängd utan merge |
| A04 | Cryptographic Failures | | | | |
| A05 | Injection | | | | |
| A06 | Insecure Design | | | | |
| A07 | Authentication Failures | | | | |
| A08 | Software or Data Integrity Failures | | | | |
| A09 | Security Logging & Alerting Failures | | | | |
| A10 | Mishandling of Exceptional Conditions | | | | |

## Validering av indata

______ (var sitter valideringen, vilka scheman finns, vad händer vid ogiltig indata – svarskoden och formen på svaret?)

## Headers vi sätter (nginx)

Headrarna står i `client/security-headers.conf` och inkluderas i **varje** `location` i `client/nginx.conf.template` (nginx ärver inte `add_header` så fort en location har en egen, som `/assets/` med `Cache-Control`):

- `Content-Security-Policy` – bara egna skript/stilar, inga inline-skript, `frame-ancestors 'none'`, `object-src 'none'`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`

Dessutom `server_tokens off` (ingen nginx-version i `Server`) och `Cache-Control: no-store` på `/api`. HSTS sätts inte än – lokalt är det http; den hör hemma där allt är https.

## Skanning i pipelinen

Jobbet *Säkerhet* i `.github/workflows/ci.yml` kör på varje PR och på `main`, billigast först – blir ett steg rött står resten som *skipped*. Tar ungefär **5 min** på `main` (bygget av imagerna dominerar; ZAP spindlar en minut).

| Steg | Verktyg | Hittar | Rött när |
|---|---|---|---|
| Beroenden | `npm audit --omit=dev --audit-level=high` | kända sårbarheter i det som står i lockfilen (SCA) | minst en high/critical i produktionsberoendena |
| Repot | Trivy `fs` (vuln, secret, misconfig) | beroenden, hemligheter som råkat committas, Dockerfiles som kör som root | HIGH/CRITICAL som inte står i `.trivyignore` |
| Imagen | Trivy `image` på `utpost-api` | sårbarheter i det som faktiskt ligger i imagen – Alpine-paket och basimagens npm, som lockfilen aldrig ser | HIGH/CRITICAL i imagen |
| Appen | ZAP baseline (DAST) mot `localhost:3001` efter `docker compose up --build --wait` | vad servern svarar: saknade säkerhetsheaders, läckt serverversion | en regel med FAIL i `.zap/rules.tsv` (WARN gör inte jobbet rött) |

**Undantagen:** `.trivyignore` – `DS-0002` för `client/Dockerfile` (nginx:alpine startar som root för port 80 och byter själv till användaren `nginx`; omprövas med nginx-unprivileged). `.zap/rules.tsv` – vilka ZAP-regler som är FAIL, WARN eller IGNORE, med en kommentar per rad.

**Vad som var rött första gången:** npm audit (8 st, se A03), Trivy `fs` DS-0002 i `api/Dockerfile`, ZAP 10020, 10021, 10036 och 10038 (se A02).

## Kända brister (medvetet kvar)

______ (det ni valt att inte laga än, och varför. Ärlighet ger poäng: en omladdning loggar ut – refresh-token är inte byggt; bytes lämnar inte browsern; …)
