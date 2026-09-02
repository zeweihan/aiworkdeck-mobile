# 四端共享契约（服务端仓：OpenAPI 真源 + 契约测试）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 checkba_cloud 服务端仓手写 `/api/mobile/*` 与短信登录的 OpenAPI 3.0.3 作为 API 真源，并用 MockMvc 契约测试保证真实响应不偏离它。

**Architecture:** 控制器返回 `Map<String,Object>`，无法从代码推导 schema，所以 YAML 手写、放 `src/main/resources/openapi/`，随 jar 打包。`MobileApiContractTest` 复用既有 `MobileRelayEndpointIntegrationTest` 的 H2 环境配方，逐端点请求并用 swagger-request-validator 校验响应体。移动仓随后用 `pull-api.mjs` 钉版副本（移动仓计划 Task 8）。

**Tech Stack:** Spring Boot 3.2.4 / Java 17 / Maven / H2 / `com.atlassian.oai:swagger-request-validator-mockmvc`。

**Spec:** `aiworkdeck-mobile/docs/specs/2026-09-02-contract-design.md` §7（本计划在 checkba_cloud 仓执行；spec 在移动仓）

## Global Constraints

- 在 checkba_cloud 仓执行，路径以 `backend/` 为根；按该仓惯例开分支、走 PR。
- OpenAPI 版本 `3.0.3`。未登录时全站返回 HTTP 200 + `{code: 4010}` 信封，YAML 里每个鉴权端点的 200 响应都要 `oneOf` 覆盖信封。
- 契约测试只校验**响应**（`validation.request` 级别 IGNORE），本期只覆盖手机端调用的六个端点；桌面端 `/inbox/*`、`/devices`、`PUT /projects` 写进 YAML 但不校验。
- 不改任何控制器返回值；发现实现与客户端预期不一致只记录进 YAML `description`，不在本计划修。
- 提交信息末尾加 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`。

---

## 文件结构

| 路径 | 职责 |
|---|---|
| `backend/src/main/resources/openapi/mobile-v1.yaml` | API 真源 |
| `backend/src/test/java/com/checkba/MobileApiContractTest.java` | 六个手机端端点的响应对 YAML 校验 |
| `backend/pom.xml` | 加 test 依赖 |

---

### Task 1: 手写 `mobile-v1.yaml`

**Files:**
- Create: `backend/src/main/resources/openapi/mobile-v1.yaml`

**Interfaces:**
- Produces: schemas `Envelope`、`RelayProject`、`MediaStatus`、`MediaUsage`、`UploadResult`、`LoginData`、`AccountUser`、`CaptureManifest`；paths 见下

- [ ] **Step 1: 写 YAML**

```yaml
openapi: 3.0.3
info:
  title: AI Workdeck Mobile Relay API
  version: "1.0.0"
  description: |
    手机端（iOS / 小程序 / 安卓 / 鸿蒙）与桌面端共用的中转接口。真源在本文件；
    移动仓 contract/api/mobile-v1.yaml 是钉版副本。鉴权一律请求头 X-Session-Id。
    未登录不是 401，而是 HTTP 200 + {code: 4010} 信封——客户端按信封判鉴权失败。
servers:
  - url: https://addin.aiworkdeck.com
    description: 大陆版（北京）
  - url: https://addin.workdeck.ai
    description: 国际版（新加坡）
components:
  parameters:
    SessionId:
      name: X-Session-Id
      in: header
      required: false
      schema: { type: string }
      description: 登录会话或 awdt_ 设备令牌。缺失或失效 → 200 + Envelope(code 4010)。
  schemas:
    Envelope:
      type: object
      required: [code]
      properties:
        code: { type: integer, description: "0 成功；4010 未登录；1 业务错误" }
        message: { type: string, nullable: true }
        data: { nullable: true }
    RelayProject:
      type: object
      required: [deviceId, key, name]
      properties:
        deviceId: { type: string, description: 桌面机 UUID }
        deviceName: { type: string, nullable: true }
        key: { type: string, description: 桌面机本地库项目 id；跨机同号不同物，必须连 deviceId }
        name: { type: string }
    MediaStatus:
      type: object
      required: [clientMediaId, delivered, waitingSeconds]
      properties:
        clientMediaId: { type: string }
        delivered: { type: boolean, description: 桌面端已 ACK 落盘（中转区已删） }
        waitingSeconds: { type: integer, format: int64, description: 已投递为 0 }
        expiresAt: { type: string, description: 中转区到期时刻（ISO 本地时间），仅未投递件带 }
    MediaUsage:
      type: object
      required: [usedBytes, quotaBytes]
      properties:
        usedBytes: { type: integer, format: int64 }
        quotaBytes: { type: integer, format: int64 }
    UploadResult:
      type: object
      required: [code, id, clientMediaId, delivered]
      properties:
        code: { type: integer, enum: [0] }
        id: { type: integer, format: int64 }
        clientMediaId: { type: string }
        delivered: { type: boolean, description: 幂等重传命中已投递记录时为 true }
    AccountUser:
      type: object
      required: [id, username, displayName]
      properties:
        id: { type: integer, format: int64 }
        username: { type: string }
        displayName: { type: string }
        avatarUrl: { type: string, description: 无头像时为空串 }
        role: { type: string }
        subscriptionType: { type: string, nullable: true }
    LoginData:
      type: object
      required: [sessionId, user]
      description: |
        注意：服务端不返回 isNewUser。小程序 api.ts 的 LoginResult 声明了 isNewUser，
        实际永远 undefined；iOS 侧已是可选。客户端应按可选处理（记录于 2026-09-02，不在服务端改）。
      properties:
        sessionId: { type: string }
        mustBindPhone: { type: boolean }
        user: { $ref: '#/components/schemas/AccountUser' }
    LoginEnvelope:
      type: object
      required: [code]
      properties:
        code: { type: integer }
        message: { type: string, nullable: true }
        data: { $ref: '#/components/schemas/LoginData' }
    CaptureManifest:
      type: object
      description: |
        客户端随影像生成的取证清单（与 iOS CaptureManifest.swift 逐字段一致）。当前服务端只接收
        clientMediaId / capturedAt / fileName / mediaType 四个字段（multipart 参数），其余留在客户端；
        接 TSA 后 tsaToken 上行，结构不变。
      required: [clientMediaId, sha256, capturedAt, deviceModel, osVersion, appVersion, fromCamera]
      properties:
        clientMediaId: { type: string, format: uuid, description: 幂等键 }
        sha256: { type: string, minLength: 64, maxLength: 64 }
        capturedAt: { type: string, format: date-time, description: 设备时钟 }
        serverReceivedAt: { type: string, format: date-time, nullable: true }
        latitude: { type: number, nullable: true }
        longitude: { type: number, nullable: true }
        horizontalAccuracy: { type: number, nullable: true, description: 米 }
        deviceModel: { type: string }
        osVersion: { type: string }
        appVersion: { type: string }
        fromCamera: { type: boolean, description: 是否强制来自相机 }
        tsaToken: { type: string, nullable: true, description: 可信时间戳，当前恒 null }
paths:
  /api/auth/sms-login/send-code:
    post:
      summary: 发送短信验证码
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [phone]
              properties: { phone: { type: string, pattern: '^1\d{10}$' } }
      responses:
        "200":
          description: code 0 已发送；code 1 业务拒绝（频率、号码格式、人机门）
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Envelope' }
  /api/auth/sms-login/verify:
    post:
      summary: 校验验证码并签发会话
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [phone, code]
              properties:
                phone: { type: string }
                code: { type: string }
      responses:
        "200":
          description: code 0 带 data；否则 code 非 0 且 data 缺失
          content:
            application/json:
              schema: { $ref: '#/components/schemas/LoginEnvelope' }
  /api/mobile/projects:
    get:
      summary: 手机端：该账号全部设备的项目目录并集（裸数组）
      parameters: [{ $ref: '#/components/parameters/SessionId' }]
      responses:
        "200":
          description: 裸数组；未登录为 Envelope(4010)
          content:
            application/json:
              schema:
                oneOf:
                  - type: array
                    items: { $ref: '#/components/schemas/RelayProject' }
                  - $ref: '#/components/schemas/Envelope'
    put:
      summary: 桌面端：项目目录全量替换（本期不校验）
      parameters: [{ $ref: '#/components/parameters/SessionId' }]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [deviceId, projects]
              properties:
                deviceId: { type: string }
                deviceName: { type: string, nullable: true }
                projects:
                  type: array
                  items:
                    type: object
                    required: [key, name]
                    properties: { key: { type: string }, name: { type: string } }
      responses:
        "200":
          description: code 0 + count/totalCount/truncated
          content:
            application/json:
              schema:
                oneOf:
                  - type: object
                    required: [code, count, totalCount, truncated]
                    properties:
                      code: { type: integer, enum: [0] }
                      count: { type: integer }
                      totalCount: { type: integer }
                      truncated: { type: boolean }
                  - $ref: '#/components/schemas/Envelope'
  /api/mobile/media:
    post:
      summary: 手机端：上传一件现场影像到中转区（幂等键 clientMediaId）
      parameters: [{ $ref: '#/components/parameters/SessionId' }]
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required: [file, deviceId, projectKey, clientMediaId, fileName, mediaType]
              properties:
                file: { type: string, format: binary }
                deviceId: { type: string }
                projectKey: { type: string }
                clientMediaId: { type: string }
                fileName: { type: string }
                mediaType: { type: string, enum: [image, video, audio] }
                capturedAt: { type: string, description: ISO-8601，可选 }
      responses:
        "200":
          description: 成功 UploadResult；未登录 Envelope(4010)
          content:
            application/json:
              schema:
                oneOf:
                  - $ref: '#/components/schemas/UploadResult'
                  - $ref: '#/components/schemas/Envelope'
  /api/mobile/media/status:
    get:
      summary: 手机端：查询影像投递状态（裸数组）
      parameters:
        - { $ref: '#/components/parameters/SessionId' }
        - name: clientMediaIds
          in: query
          required: true
          schema: { type: string }
          description: 逗号分隔
      responses:
        "200":
          description: 裸数组；未登录 Envelope(4010)
          content:
            application/json:
              schema:
                oneOf:
                  - type: array
                    items: { $ref: '#/components/schemas/MediaStatus' }
                  - $ref: '#/components/schemas/Envelope'
  /api/mobile/media/usage:
    get:
      summary: 手机端：中转区用量与配额（裸对象）
      parameters: [{ $ref: '#/components/parameters/SessionId' }]
      responses:
        "200":
          description: 裸对象；未登录 Envelope(4010)
          content:
            application/json:
              schema:
                oneOf:
                  - $ref: '#/components/schemas/MediaUsage'
                  - $ref: '#/components/schemas/Envelope'
  /api/mobile/devices:
    get:
      summary: 插件端：设备清单（本期不校验）
      parameters: [{ $ref: '#/components/parameters/SessionId' }]
      responses:
        "200":
          description: 裸数组
          content:
            application/json:
              schema:
                oneOf:
                  - type: array
                    items:
                      type: object
                      required: [deviceId, online, projects]
                      properties:
                        deviceId: { type: string }
                        deviceName: { type: string, nullable: true }
                        online: { type: boolean }
                        projects: { type: array, items: { $ref: '#/components/schemas/RelayProject' } }
                  - $ref: '#/components/schemas/Envelope'
  /api/mobile/inbox:
    get:
      summary: 桌面端：本设备待取件（本期不校验）
      parameters:
        - { $ref: '#/components/parameters/SessionId' }
        - { name: deviceId, in: query, required: true, schema: { type: string } }
      responses:
        "200":
          description: 裸数组
          content:
            application/json:
              schema:
                oneOf:
                  - type: array
                    items:
                      type: object
                      required: [id, projectKey, clientMediaId, fileName, mediaType, fileSize, createdAt]
                      properties:
                        id: { type: integer, format: int64 }
                        projectKey: { type: string }
                        clientMediaId: { type: string }
                        fileName: { type: string }
                        mediaType: { type: string }
                        fileSize: { type: integer, format: int64 }
                        capturedAt: { type: string, nullable: true }
                        createdAt: { type: string }
                  - $ref: '#/components/schemas/Envelope'
  /api/mobile/inbox/{id}/content:
    get:
      summary: 桌面端：取件字节流。契约红线：成功必须 2xx + application/octet-stream 裸字节，不许 302（本期不校验）
      parameters:
        - { $ref: '#/components/parameters/SessionId' }
        - { name: id, in: path, required: true, schema: { type: integer, format: int64 } }
      responses:
        "200":
          description: 字节流
          content:
            application/octet-stream:
              schema: { type: string, format: binary }
  /api/mobile/inbox/{id}/ack:
    post:
      summary: 桌面端：确认落盘，置 deliveredAt 并立即删 blob（本期不校验）
      parameters:
        - { $ref: '#/components/parameters/SessionId' }
        - { name: id, in: path, required: true, schema: { type: integer, format: int64 } }
      responses:
        "200":
          description: code 0
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Envelope' }
```

- [ ] **Step 2: 语法自检**

Run（Node 22，无需装包）：
```bash
node -e "const y=require('fs').readFileSync('backend/src/main/resources/openapi/mobile-v1.yaml','utf8'); console.log(y.split('\n').length,'lines; paths:',(y.match(/^  \/api\//gm)||[]).length)"
```
Expected: `paths: 9`

- [ ] **Step 3: 提交**

```bash
git add backend/src/main/resources/openapi/mobile-v1.yaml
git commit -m "docs(api): 手机端中转接口 OpenAPI 3.0.3 真源（/api/mobile/* + 短信登录）

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `MobileApiContractTest`

**Files:**
- Modify: `backend/pom.xml`
- Create: `backend/src/test/java/com/checkba/MobileApiContractTest.java`

**Interfaces:**
- Consumes: Task 1 的 YAML；既有 `/api/auth/register` 建号拿 sessionId（与 `MobileRelayEndpointIntegrationTest.register` 同法）

- [ ] **Step 1: 查最新版本并加依赖**

Run:
```bash
curl -s 'https://search.maven.org/solrsearch/select?q=g:com.atlassian.oai+AND+a:swagger-request-validator-mockmvc&rows=1&wt=json' | python3 -c "import sys,json;print(json.load(sys.stdin)['response']['docs'][0]['latestVersion'])"
```
把输出的版本号填进 `backend/pom.xml` 的 `<dependencies>`（test scope）：

```xml
        <dependency>
            <groupId>com.atlassian.oai</groupId>
            <artifactId>swagger-request-validator-mockmvc</artifactId>
            <version>【上一步输出】</version>
            <scope>test</scope>
        </dependency>
```

Run: `cd backend && mvn -q dependency:resolve -Dclassifier=test 2>&1 | tail -3`
Expected: 无 ERROR

- [ ] **Step 2: 写失败测试**

`backend/src/test/java/com/checkba/MobileApiContractTest.java`：

```java
package com.checkba;

import com.atlassian.oai.validator.OpenApiInteractionValidator;
import com.atlassian.oai.validator.report.LevelResolver;
import com.atlassian.oai.validator.report.ValidationReport;
import com.checkba.service.ai.tools.WebTools;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.nio.charset.StandardCharsets;
import java.util.Map;

import static com.atlassian.oai.validator.mockmvc.OpenApiValidationMatchers.openApi;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * API 契约测试：手机端调用的六个端点，真实响应必须合 src/main/resources/openapi/mobile-v1.yaml。
 * 只校验响应（请求级别 IGNORE，multipart 请求校验在该库里不稳）。
 * 环境配方同 MobileRelayEndpointIntegrationTest。移动仓 contract/api/ 钉的是这份 YAML 的副本。
 */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:mobile-api-contract;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DEFAULT_NULL_ORDERING=HIGH;NON_KEYWORDS=VALUE;DB_CLOSE_DELAY=-1",
        "security.local-mode=false",
        "storage.local.root-path=${java.io.tmpdir}/mobile-api-contract-store"
})
@AutoConfigureMockMvc
@ActiveProfiles("desktop")
class MobileApiContractTest {

    private static OpenApiInteractionValidator validator;

    @Autowired private MockMvc mvc;
    @Autowired private ObjectMapper om;
    @MockBean private WebTools webTools;

    @BeforeAll
    static void loadSpec() throws Exception {
        String spec = new String(
                MobileApiContractTest.class.getResourceAsStream("/openapi/mobile-v1.yaml").readAllBytes(),
                StandardCharsets.UTF_8);
        validator = OpenApiInteractionValidator.createForInlineApiSpecification(spec)
                .withLevelResolver(LevelResolver.create()
                        .withLevel("validation.request", ValidationReport.Level.IGNORE)
                        .build())
                .build();
    }

    private String register(String username) throws Exception {
        String body = om.writeValueAsString(Map.of(
                "username", username, "password", "pw123456", "displayName", username));
        MvcResult r = mvc.perform(post("/api/auth/register").contentType(APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andReturn();
        JsonNode json = om.readTree(r.getResponse().getContentAsString());
        String sid = json.path("data").path("sessionId").asText();
        assertFalse(sid.isEmpty(), "注册应返回 sessionId：" + r.getResponse().getContentAsString());
        return sid;
    }

    @Test
    void handsetEndpointsMatchSpec() throws Exception {
        String sid = register("contract_" + System.nanoTime());
        String mediaId = "0a1b2c3d-2222-4333-8444-555566667777";

        // 未登录信封也在契约里
        mvc.perform(get("/api/mobile/projects"))
                .andExpect(status().isOk())
                .andExpect(openApi().isValid(validator));

        // 桌面推目录，让 GET /projects 有内容
        mvc.perform(put("/api/mobile/projects").header("X-Session-Id", sid)
                        .contentType(APPLICATION_JSON)
                        .content("""
                                {"deviceId":"dev-c","deviceName":"Mac","projects":[{"key":"1","name":"契约项目"}]}"""))
                .andExpect(status().isOk());

        mvc.perform(get("/api/mobile/projects").header("X-Session-Id", sid))
                .andExpect(status().isOk())
                .andExpect(openApi().isValid(validator));

        MockMultipartFile file = new MockMultipartFile(
                "file", "现场影像-20260902-170000-0a1b.jpg", "application/octet-stream", "JPEG".getBytes());
        mvc.perform(multipart("/api/mobile/media").file(file)
                        .param("deviceId", "dev-c").param("projectKey", "1")
                        .param("clientMediaId", mediaId)
                        .param("fileName", "现场影像-20260902-170000-0a1b.jpg")
                        .param("mediaType", "image")
                        .param("capturedAt", "2026-09-02T17:00:00Z")
                        .header("X-Session-Id", sid))
                .andExpect(status().isOk())
                .andExpect(openApi().isValid(validator));

        mvc.perform(get("/api/mobile/media/status").param("clientMediaIds", mediaId)
                        .header("X-Session-Id", sid))
                .andExpect(status().isOk())
                .andExpect(openApi().isValid(validator));

        mvc.perform(get("/api/mobile/media/usage").header("X-Session-Id", sid))
                .andExpect(status().isOk())
                .andExpect(openApi().isValid(validator));
    }

    @Test
    void smsLoginEnvelopesMatchSpec() throws Exception {
        // 不真发短信：非法号码走 code 1 分支，信封形状仍受契约约束
        mvc.perform(post("/api/auth/sms-login/send-code").contentType(APPLICATION_JSON)
                        .content("{\"phone\":\"123\"}"))
                .andExpect(status().isOk())
                .andExpect(openApi().isValid(validator));

        mvc.perform(post("/api/auth/sms-login/verify").contentType(APPLICATION_JSON)
                        .content("{\"phone\":\"13800000000\",\"code\":\"000000\"}"))
                .andExpect(status().isOk())
                .andExpect(openApi().isValid(validator));
    }
}
```

- [ ] **Step 3: 跑测试**

Run: `cd backend && mvn -q test -Dtest=MobileApiContractTest 2>&1 | tail -40`
Expected: 两例通过。若 `openApi().isValid` 报某字段不合：**先核对是 YAML 写错还是实现变了**——本计划只改 YAML，不改控制器。

- [ ] **Step 4: 反向验证**

临时把 YAML 里 `MediaUsage.required` 改成 `[usedBytes, quotaBytes, foo]`，重跑，Expected: `handsetEndpointsMatchSpec` 失败并指出 `foo` 缺失；然后 `git checkout backend/src/main/resources/openapi/mobile-v1.yaml`。

- [ ] **Step 5: 确认 CI 会跑到**

```bash
grep -n "mvn" .github/workflows/ci.yml
```
Expected: 有 `mvn ... test`（或 `verify`）且未用 `-Dtest=` 白名单排除新类。若 ci.yml 只 `package -DskipTests`，在该 job 加一步 `mvn -q test -Dtest=MobileApiContractTest`。

- [ ] **Step 6: 提交并开 PR**

```bash
git add backend/pom.xml backend/src/test/java/com/checkba/MobileApiContractTest.java .github/workflows/ci.yml
git commit -m "test(api): MobileApiContractTest——手机端六端点响应对 openapi/mobile-v1.yaml 校验

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin HEAD
gh pr create --title "feat(api): /api/mobile OpenAPI 真源 + 契约测试（dev-board#392）" --body "$(cat <<'EOF'
## 摘要
- 手写 `openapi/mobile-v1.yaml`（3.0.3）覆盖 /api/mobile/* 与短信登录；未登录 200+4010 信封入契约
- `MobileApiContractTest` 用 swagger-request-validator 校验手机端六端点真实响应
- 不改任何控制器；发现服务端不返回 isNewUser 而小程序类型声明了它，记录在 LoginData.description

配套：移动仓 `docs/specs/2026-09-02-contract-design.md` §7，合并后移动仓跑 `node contract/tools/pull-api.mjs` 钉版。

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 7: 通知移动仓计划**

合并后在移动仓执行其计划 Task 8（`pull-api.mjs` 钉版）。
