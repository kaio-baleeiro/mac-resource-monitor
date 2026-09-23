# Configuração do MCP por cliente

O servidor é local, somente leitura e usa transporte `stdio`. Ele não abre
portas, não envia telemetria e não lê conteúdo de arquivos. O comando portátil
deve apontar para `scripts/run-mcp.sh` depois de compilar o projeto.

```sh
./scripts/build-mcp.sh
```

O servidor foi mantido no formato básico `command` + `args` para funcionar em
clientes diferentes. Os nomes dos campos de configuração não são universais:

| Cliente | Configuração local | Campo principal |
| --- | --- | --- |
| Codex | `~/.codex/config.toml` ou `.codex/config.toml` | `[mcp_servers.nome]` |
| Claude Code | `~/.claude.json` ou `.mcp.json` | `mcpServers` |
| Gemini CLI | `~/.gemini/settings.json` ou `.gemini/settings.json` | `mcpServers` |
| Devin CLI | `.devin/mcp_config.json` ou `~/.config/devin/mcp_config.json` | `mcpServers` |
| Cursor | `~/.cursor/mcp.json` ou `.cursor/mcp.json` | `mcpServers` |
| VS Code/Copilot | `.vscode/mcp.json` ou `~/.copilot/mcp-config.json` | `servers` |

## Codex CLI, Desktop e extensão IDE

```sh
codex mcp add mac-resource-monitor -- /CAMINHO/DO/CLONE/scripts/run-mcp.sh
codex mcp list
```

Ou em `~/.codex/config.toml`:

```toml
[mcp_servers.mac-resource-monitor]
command = "/CAMINHO/DO/CLONE/scripts/run-mcp.sh"
startup_timeout_sec = 15
tool_timeout_sec = 30
```

No aplicativo, abra **Settings → MCP servers → Add server**, escolha **STDIO**
e informe o caminho completo do script. Salve e reinicie o servidor. A
configuração do Codex CLI, Desktop e extensão IDE é compartilhada no mesmo
host.

## Claude Code

```sh
claude mcp add --transport stdio mac-resource-monitor -- \
  /CAMINHO/DO/CLONE/scripts/run-mcp.sh
claude mcp list
claude mcp get mac-resource-monitor
```

Para compartilhar com um projeto, use `--scope project`; para todos os
projetos do usuário, use `--scope user`. O separador `--` antes do comando é
importante. A alternativa JSON é:

```json
{
  "mcpServers": {
    "mac-resource-monitor": {
      "type": "stdio",
      "command": "/CAMINHO/DO/CLONE/scripts/run-mcp.sh",
      "args": []
    }
  }
}
```

Em `.mcp.json`, servidores de projeto podem pedir aprovação na primeira
execução.

## Claude Desktop

O caminho oficial atual para servidores locais distribuídos ao Claude Desktop
é um bundle `.mcpb`. Gere um bundle Apple Silicon com:

```sh
./scripts/build-mcpb.sh
```

Depois, instale `dist/mac-resource-monitor.mcpb` em **Settings → Extensions →
Advanced settings → Install Extension…**. O bundle contém o binário MCP e um
manifesto sem caminhos pessoais. Para versões que ainda aceitam configuração
stdio direta, use o mesmo `command` da seção Claude Code.

## Gemini CLI

```sh
gemini mcp add --scope user mac-resource-monitor \
  /CAMINHO/DO/CLONE/scripts/run-mcp.sh
gemini mcp list
```

Ou em `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "mac-resource-monitor": {
      "command": "/CAMINHO/DO/CLONE/scripts/run-mcp.sh",
      "args": [],
      "timeout": 30000,
      "trust": false
    }
  }
}
```

Em um projeto, o arquivo pode ficar em `.gemini/settings.json`. O workspace
precisa estar confiável para o Gemini CLI iniciar servidores MCP locais.

## Devin CLI e Devin Desktop

Para o Devin CLI local, use:

```sh
devin mcp add mac-resource-monitor -- \
  /CAMINHO/DO/CLONE/scripts/run-mcp.sh
devin mcp list
```

O formato equivalente em `.devin/mcp_config.json` é:

```json
{
  "mcpServers": {
    "mac-resource-monitor": {
      "command": "/CAMINHO/DO/CLONE/scripts/run-mcp.sh",
      "args": []
    }
  }
}
```

O Devin em nuvem não consegue iniciar um processo que existe apenas no seu
Mac. Para esse caso seria necessário um servidor remoto Streamable HTTP; este
projeto deliberadamente não o expõe porque o objetivo é observar a máquina
local. O Devin Desktop também pode usar a configuração padrão dele para MCP,
mas `serverUrl` é específico para servidores HTTP remotos do Devin — não use
esse campo para este servidor stdio.

## Cursor

Em `~/.cursor/mcp.json` ou `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "mac-resource-monitor": {
      "command": "/CAMINHO/DO/CLONE/scripts/run-mcp.sh",
      "args": []
    }
  }
}
```

## VS Code / GitHub Copilot

O VS Code usa `servers`, não `mcpServers`. Em `.vscode/mcp.json`:

```json
{
  "servers": {
    "mac-resource-monitor": {
      "type": "stdio",
      "command": "/CAMINHO/DO/CLONE/scripts/run-mcp.sh",
      "args": []
    }
  }
}
```

Também é possível adicionar pela paleta de comandos **MCP: Add Server**.

## Ferramentas e fluxo recomendado para agentes

- `get_system_resources`: visão atual de CPU, RAM, GPU, disco principal, rede e quantidade de processos.
- `get_top_processes`: ranking de processos por `resource: "cpu"` ou `resource: "memory"`, com `limit` entre 1 e 20.
- `get_process_details`: consulta pontual pelo `pid`; o processo pode desaparecer entre duas leituras.
- `get_machine_info`: macOS, arquitetura, CPUs, memória física e GPU detectada.
- `get_metric_capabilities`: explica métricas ausentes, aproximações e limites de privacidade.

Fluxo recomendado: comece com `get_system_resources`; se houver pressão,
consulte `get_top_processes`; use `get_process_details` apenas para investigar
um PID específico. GPU pode aparecer como nula quando o macOS não publica a
utilização do acelerador.

## Smoke test e suíte de cenários

O runner local executa uma matriz determinística de **2.000 cenários distintos**
sem depender de um processo real ou de dados pessoais. A matriz inclui estados
simulados de baseline, indisponibilidade, falha de GPU, rede, disco e lista de
processos:

```sh
./scripts/test-mcp.sh
```

Para validar também o binário release via stdio:

```sh
./scripts/build-mcp.sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | ./scripts/run-mcp.sh
```

## Fontes oficiais consultadas

- [Codex MCP](https://developers.openai.com/pt-BR/docs/extend/mcp)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Gemini CLI MCP](https://google-gemini.github.io/gemini-cli/docs/tools/mcp-server.html)
- [Devin MCP](https://docs.devin.ai/work-with-devin/devin-mcp)
- [Devin CLI MCP configuration](https://docs.devin.ai/cli/extensibility/mcp/configuration)
- [VS Code MCP configuration](https://code.visualstudio.com/docs/agents/reference/mcp-configuration)
- [MCP server primitives](https://modelcontextprotocol.io/specification/2025-06-18/server)
- [MCP Bundle manifest](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)
