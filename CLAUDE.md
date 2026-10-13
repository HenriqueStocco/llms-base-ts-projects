@AGENTS.md

## Arquivos ignorados pelo agente (.claudeignore)

- Todo caminho listado em `.claudeignore` (sintaxe do `.gitignore`) **não deve ser lido, modificado nem usado** pelo agente, nem para inspeção, nem para depuração, nem como exemplo.
- Antes de ler, editar ou citar um arquivo sensível, conferir se ele casa com `.claudeignore`.
- Se a tarefa exigir um caminho ignorado, parar e pedir ao usuário. Não contornar com `cat`, `grep`, `sed`, scripts ou outra ferramenta.
- Não copiar o conteúdo de caminhos ignorados para respostas, commits, logs ou testes.
- Esta regra é comportamental. A aplicação técnica é feita por `.claude/hooks/guard-paths.sh` e pelas regras `permissions.deny` de `.claude/settings.json`.

## Proteções, modelos e delegação

Detalhe e tabela de papéis: `docs/agents/claude-code.md` (ler antes de alterar permissões, hooks ou subagentes).

- Não editar `.claude/**`, `.claudeignore` nem os settings do usuário, e não contornar isso por Bash. Proteção que precise mudar: escrever a proposta em `proposals/claude/` e pedir ao usuário que aplique.
- Permissão negada ou hook que bloqueou: ajustar a abordagem, nunca repetir o mesmo comando nem procurar outro caminho para o mesmo efeito.
- O modelo e o esforço da sessão são escolha do usuário; não tentar trocá-los. Se a tarefa pedir outro (ex.: bug difícil que o modelo atual não resolveu em 2 tentativas), sugerir.
- Delegar a subagente leituras amplas do repositório, execução de testes e análise de logs, para manter o contexto principal pequeno. Revisão de diff, em subagente com contexto limpo.
- Subagentes herdam as mesmas permissões e proibições; modelo menor não amplia o que pode ser feito.
