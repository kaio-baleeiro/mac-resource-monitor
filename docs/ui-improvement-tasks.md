# Tarefas de melhoria do monitor

## Aplicado nesta rodada

- [x] Corrigir o deadlock da coleta de processos: a saída do `ps` é drenada antes de aguardar o término.
- [x] Serializar o leitor de métricas e disponibilizar `readAsync()` para a interface.
- [x] Pausar a coleta quando o popover desaparece e reiniciar os baselines ao retomar.
- [x] Diferenciar estados `available`, `warmingUp`, `unavailable` e `failed`.
- [x] Expor estados de métrica no payload do MCP sem alterar nomes de ferramentas.
- [x] Manter CPU, RAM, GPU e armazenamento visíveis no modo detalhado.
- [x] Remover o segundo controle redundante de alternância resumo/detalhes.
- [x] Evitar que métricas indisponíveis apareçam como barras em zero.
- [x] Adicionar status visual da coleta e labels de acessibilidade básicos.
- [x] Tornar rankings determinísticos em caso de empate.
- [x] Permitir abrir os detalhes de um processo, copiar o PID e abrir o Monitor de Atividade.
- [x] Manter uma cor própria para CPU, RAM, GPU e armazenamento nos modos compacto e detalhado.
- [x] Simular aquecimento, indisponibilidade e falha de métricas sem executar o coletor real.
- [x] Ocultar valores antigos no MCP quando o estado da métrica não for confiável.

## Próxima rodada

- [ ] Adicionar pressão de memória e swap como métricas separadas.
- [ ] Adicionar histórico curto e tendência de CPU/RAM.
- [ ] Implementar altura baseada na área visível do monitor ativo, validando notch e múltiplos monitores.
- [ ] Criar testes de unidade para estados, formatação localizada e ciclo de visibilidade.
- [ ] Criar testes de UI para resumo, detalhes, texto ampliado, estados de erro e nomes longos.
- [ ] Adicionar smoke test do binário MCP stdio no CI.
- [ ] Medir custo energético do monitor com o popover aberto e fechado.
- [ ] Validar VoiceOver, navegação por teclado, alto contraste e reduzir movimento em macOS 13+.

## Critérios de aceite

- A interface continua responsiva enquanto `ps` e IOKit são consultados.
- Fechar o popover interrompe novas leituras.
- Falha, aquecimento e zero real não são apresentados com a mesma semântica.
- O modo detalhado rola o conteúdo sem esconder o resumo nem o rodapé.
- O MCP permanece somente leitura e mantém as cinco ferramentas existentes.
