# chatspx-tools-mcp

A thin **MCP (Model Context Protocol)** server — stdio transport — that wraps the
**ChatSPX Captain "Custom Tools"** REST API. It lets an admin **create, edit,
delete and test** Captain custom tools from an MCP client (Claude Desktop,
Cursor, etc.) **without touching the source code**.

It is a *governance front-end*: a person with an admin api_access_token can shape
the agent's toolbox from chat, while activation stays a deliberate human step in
the UI.

---

## Governance (read this first)

- **Tools created through this server are always born DISABLED** (`enabled:false`).
- A new tool **does nothing** until an **admin reviews and activates it in the
  ChatSPX UI at `/agents/tools`**.
- **Enabling a tool via MCP is blocked.** `update_tool` accepts `enabled:false`
  (a kill-switch to disable a live tool) but **refuses `enabled:true`**.
- Every tool call writes a one-line **audit record to stderr**
  (`[AUDIT] <iso-timestamp> action=... id=...`).

This keeps the "who can build a tool" surface convenient while the "what the
agent is actually allowed to run" decision remains an explicit click by a human.

---

## Install & build

Requires **Node >= 18**.

```bash
cd mcp/chatspx-tools
npm install
npm run build      # compiles TypeScript -> dist/index.js
```

Run it standalone (it will wait for an MCP client on stdio):

```bash
npm start          # = node dist/index.js
```

---

## Configuration (environment variables)

| Variable             | Required | Example                         | Description                                              |
| -------------------- | :------: | ------------------------------- | -------------------------------------------------------- |
| `CHATSPX_API_URL`    |   yes    | `https://chat.example.com`      | Base URL of the ChatSPX install (no trailing slash).     |
| `CHATSPX_API_TOKEN`  |   yes    | `abc123...`                     | An **admin** user's `api_access_token` (sent as header). |
| `CHATSPX_ACCOUNT_ID` |   yes    | `1`                             | Numeric account id the tools belong to.                  |

All calls hit `…/api/v1/accounts/{CHATSPX_ACCOUNT_ID}/captain/…` with the header
`api_access_token: {CHATSPX_API_TOKEN}`.

> Find your `api_access_token` in ChatSPX under **Profile Settings → Access Token**.
> It must belong to an **administrator** — create/update/delete are admin-only.

---

## MCP client configuration

Add the server to your client's MCP config. Use the **absolute path** to the
built `dist/index.js`.

### Claude Desktop / Cursor (`mcpServers`)

```json
{
  "mcpServers": {
    "chatspx-tools": {
      "command": "node",
      "args": ["/absolute/path/to/chatwoot/mcp/chatspx-tools/dist/index.js"],
      "env": {
        "CHATSPX_API_URL": "https://chat.example.com",
        "CHATSPX_API_TOKEN": "your_admin_api_access_token",
        "CHATSPX_ACCOUNT_ID": "1"
      }
    }
  }
}
```

- **Claude Desktop** config file:
  - macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
  - Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- **Cursor**: `~/.cursor/mcp.json` (or the project's `.cursor/mcp.json`), same
  `mcpServers` shape.

Restart the client after editing the config.

---

## Tools exposed

| Tool                | Method & path                                  | Notes                                                              |
| ------------------- | ---------------------------------------------- | ----------------------------------------------------------------- |
| `list_tools`        | `GET /captain/assistants/tools`                | All agent tools (built-in **and** custom): `{id,title,description,icon}`. |
| `list_custom_tools` | `GET /captain/custom_tools`                    | Full config of this account's custom tools.                       |
| `create_tool`       | `POST /captain/custom_tools`                   | **Forces `enabled:false`.** Returns the created tool.             |
| `update_tool`       | `PATCH /captain/custom_tools/{id}`             | Edits fields. **Refuses `enabled:true`** (UI-only activation).    |
| `delete_tool`       | `DELETE /captain/custom_tools/{id}`            | Permanent. Prefer `update_tool enabled:false` to just pause.      |
| `test_tool`         | `POST /captain/custom_tools/{id}/test`         | Smoke-test against the real endpoint. Works on disabled tools.    |

### `create_tool` / `update_tool` fields

| Field               | Type                                              | Notes                                                                            |
| ------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------- |
| `title`             | string (required on create)                       | Slug is derived from it (e.g. `Fetch Order Status` -> `custom_fetch_order_status`). |
| `description`       | string                                            | Helps the agent decide when to call the tool.                                    |
| `endpoint_url`      | string (required on create)                       | **Public https URL.** localhost/private IPs are blocked (SSRF guard). May contain Liquid, e.g. `…/orders/{{ order_id }}`. |
| `http_method`       | `GET` \| `POST`                                   | Default `GET`.                                                                   |
| `auth_type`         | `none` \| `bearer` \| `basic` \| `api_key`        | Default `none`.                                                                  |
| `auth_config`       | object                                            | `bearer`: `{token}` · `basic`: `{username,password}` · `api_key`: `{key,location,name}`. |
| `param_schema`      | array of `{name,type,description,required?}`      | Parameters the agent collects before calling.                                    |
| `request_template`  | string (Liquid)                                   | POST body template, e.g. `{ "order_id": "{{ order_id }}" }`.                     |
| `response_template` | string (Liquid)                                   | Formats the upstream response for the agent.                                     |
| `copilot_only`      | boolean                                           | Limit the tool to Copilot (agent-assist) only.                                   |
| `enabled`           | boolean (**update only**)                         | Only `false` honored; `true` is refused (activate in the UI).                    |

### `test_tool` input

```json
{ "id": 42, "params": { "order_id": "123" } }
```

Returns `{ ok, status, body }` (or `{ ok:false, error }` if the upstream call
failed).

---

## Example session

1. `list_custom_tools` — see what already exists.
2. `create_tool` with `title`, `endpoint_url`, `param_schema` — created **disabled**.
3. `test_tool` with sample `params` — confirm the endpoint responds.
4. A human admin opens **`/agents/tools`** and **activates** the tool.
5. Later, `update_tool` with `enabled:false` to pause it, or `delete_tool` to remove it.

---

## Development

```bash
npm run dev     # tsx watch (hot reload from src/)
npm run build   # tsc -> dist/
npm run clean   # remove dist/
```

Audit logs and the startup banner go to **stderr** (stdout is reserved for the
MCP protocol stream).
