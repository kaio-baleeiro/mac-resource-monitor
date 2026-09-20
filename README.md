---
title: Monitoramento de Recursos do Mac
aliases:
  - Monitoramento de Hardware
  - Consumo de Recursos no Mac
tags:
  - projeto
  - macos
  - hardware
  - observabilidade
type: project
status: active
created: 2026-09-19
updated: 2026-09-19
source_agent: codex
agent_context: mac-hardware-monitoring
confidence: medium
review: true
---

# Monitoramento de Recursos do Mac

Aplicativo nativo e local de barra de menus para visualizar rapidamente o
consumo de recursos em Macs Apple Silicon M3 ou posteriores.

## Requisitos

- macOS 13 ou posterior;
- Mac Apple Silicon, incluindo M3, M4 e gerações posteriores;
- Swift 6 ou Xcode Command Line Tools para compilar.

O projeto não depende de caminhos específicos de uma máquina, não inclui
credenciais ou telemetria externa e não exige um serviço remoto.

Criar uma forma simples de acompanhar o consumo de recursos de hardware no
Mac, com uma visualização mais clara do que a disponível hoje no sistema.

> [!note] Intenção inicial
> O projeto deve responder rapidamente: “o que está usando os recursos agora?”
> e “há algum sinal de sobrecarga ou aquecimento?”.

## Objetivo

Reunir em uma única visualização, legível e objetiva:

- CPU total e por processo;
- memória usada, pressão de memória e swap;
- GPU, quando as métricas estiverem disponíveis no hardware;
- armazenamento e atividade de leitura/escrita;
- temperatura, energia e velocidade das ventoinhas, quando acessíveis;
- rede, como indicador complementar de atividade.

## Direção de produto

- Priorizar leitura rápida em vez de excesso de métricas.
- Usar cartões, cores e históricos curtos para destacar anomalias.
- Mostrar o valor atual junto de uma tendência recente.
- Diferenciar “alto uso esperado” de “sinal de problema”.
- Manter o monitoramento local, sem depender de enviar telemetria para fora da máquina.

## Escopo inicial

1. Descobrir quais métricas são acessíveis de forma confiável no macOS da máquina.
2. Definir uma interface de painel com visão geral e detalhamento por recurso.
3. Escolher a implementação mais adequada: menu bar, janela compacta ou painel web local.
4. Medir o custo do próprio monitoramento para não criar uma nova fonte de consumo.

## Fora do escopo por enquanto

- Monitoramento remoto de outras máquinas.
- Alertas enviados para serviços externos.
- Coleta histórica de longo prazo antes de validar a utilidade da visualização.

## Próximas decisões

- [ ] Confirmar modelo do Mac, versão do macOS e arquitetura.
- [ ] Escolher o formato principal da interface.
- [ ] Levantar APIs e comandos locais disponíveis para cada métrica.
- [ ] Criar um protótipo da visão geral.
- [ ] Definir limites visuais para uso normal, atenção e risco.

## Contexto

Este projeto nasceu da dificuldade de interpretar rapidamente o consumo de
recursos na visualização atual do Mac. A primeira versão deve privilegiar
clareza e diagnóstico cotidiano, não uma coleção completa de métricas.

## Primeira versão do app

A primeira implementação é um app nativo de barra de menus, sem dependências
externas. O ícone usa o indicador de velocímetro do sistema; ao clicar nele,
abre um painel compacto com CPU, RAM, GPU e disco principal, atualizado uma vez
por segundo. O botão **Detalhes** amplia o painel e mostra velocidade de rede,
quantidade de processos lidos e os processos que mais consomem CPU e RAM.

O macOS não oferece ao app, de forma pública e confiável, a divisão da GPU por
processo. A leitura de I/O de disco por processo também exige uma coleta
privilegiada; por isso essas duas limitações aparecem no painel em vez de gerar
dados incompletos.

Para compilar e gerar o aplicativo:

```sh
./scripts/build-app.sh
```

O resultado fica em `dist/Monitoramento de Recursos.app`. A versão atual é
local e não configura inicialização automática com o macOS.

## MCP para agentes de IA

O projeto também inclui um servidor MCP local por `stdio`. Ele permite que um
agente consulte o estado atual da máquina sem acessar a interface gráfica e sem
enviar telemetria para um serviço externo.

Ferramentas disponíveis:

- `get_system_resources`: CPU, RAM, GPU, disco principal, rede e quantidade de processos;
- `get_top_processes`: processos que mais consomem CPU ou RAM.

Compile o servidor MCP com:

```sh
./scripts/build-mcp.sh
```

Depois, registre `scripts/run-mcp.sh` no cliente MCP do agente. Há um exemplo
em [`docs/mcp-config.example.json`](docs/mcp-config.example.json); substitua
`/path/to/mac-resource-monitor` pelo caminho local do clone. O servidor usa
somente `stdout` para o protocolo MCP e não imprime logs misturados às respostas.
