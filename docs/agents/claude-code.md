# Claude Code: permissões, hooks, modelos e subagentes

Complementa `AGENTS.md` (matriz de risco em 16.2) e `CLAUDE.md`. Descreve **o que a máquina impõe**, o que depende só de comportamento, o que cada papel pode fazer e como alterar as proteções. Itens marcados **(proposto)** estão em `proposals/claude/` e só valem depois de aplicados (seção 5).

## 1. O que é imposto e o que é só comportamental

| Camada | Onde | O que faz | Limite conhecido |
| --- | --- | --- | --- |
| Regras de permissão | `.claude/settings.json` → `permissions` | `deny` bloqueia, `ask` pede confirmação, `allow` libera. Ordem: deny, ask, allow. Hook não anula `deny` nem `ask`. | Regras de `Bash` casam o **texto** do comando. `/usr/bin/git push`, `git -C . push`, `git 'push'` e `bash -c '...'` escapam. `Read` deny cobre as ferramentas de arquivo e comandos como `cat`/`sed`/redirecionamento, mas não um script (`python`, `node`) que abre o arquivo sozinho. |
| Hook `PreToolUse` | `.claude/hooks/guard-paths.sh` | Aplica `.claudeignore`; bloqueia leitura de arquivo grande sem `limit`; bloqueia segredo em conteúdo gravado; **(proposto)** bloqueia `git` destrutivo em qualquer forma e pede confirmação para `git -C`/`-c`/`--git-dir`. Vale também dentro de subagentes. | Verificação por tokens, best effort: expansão de variável, glob e script externo escapam. Pode dar falso positivo (ex.: o filtro `.key` de um `jq` casa com `*.key`). Por padrão, **hook que falha deixa a ação passar**; **(proposto)** `onFailure: "block"`. |
| `.claudeignore` | raiz | Lista de caminhos sensíveis, lida pelo hook. Reduz contexto. | Não é barreira de segurança. Duplica o `Read(...)` de `deny`: ao editar um, editar o outro. |
| Sandbox | `/sandbox` (**desligado hoje**) | Único mecanismo que bloqueia, no sistema operacional, o que um subprocesso lê, escreve e acessa de rede. | Cobre só comandos de shell; as ferramentas de arquivo seguem as regras de permissão. Linux precisa de `bubblewrap` e `socat`; no Ubuntu 24.04+ o AppArmor exige ajuste. |
| `AGENTS.md`, `CLAUDE.md` | raiz | Orientam o julgamento. | **Comportamental**: o modelo pode errar ou ignorar. Para bloquear de verdade, regra de permissão ou hook. |

## 2. Matriz de risco (16.2) → configuração

| Nível | Configuração | Quem decide |
| --- | --- | --- |
| **A** inspeção local | `allow` explícito para `git status/diff/log/show`, `git worktree list`; leitura dentro do projeto; testes, lint e typecheck do projeto | automático |
| **B** alteração local reversível | edição dentro do projeto, **exceto** `.claude/**`, `.claudeignore` e settings do usuário (`deny`) | modo de permissão da sessão |
| **C** impacto operacional | `ask`: commit e demais comandos que mudam o Git, instalação de dependências, `publish`/`deploy`, `ssh`/`scp`/`rsync`, `curl`/`wget`, `sudo`, `docker compose`/`run`/`build`/`rm`, clientes de banco, `rm -r`, `chmod -R` | usuário confirma cada vez |
| **D** crítica ou destrutiva | `deny` quando é irreversível e raro: `push --force`/`--delete`/`+refspec`, `reset --hard`, `clean`, `stash drop`/`clear`, `docker system prune`, `docker volume rm`/`prune`. O usuário executa, se quiser, com `!` | só o usuário, por operação |

Critério: **`deny` para o que não se desfaz e quase nunca o agente precisa fazer; `ask` para o que é legítimo mas compartilhado.** `ask` e `deny` não dependem do modelo.

## 3. O que cada papel pode e não pode

Vale para **todos** os papéis e modelos: permissões e hooks são herdados pelos subagentes; modelo menor **não** ganha permissão extra; ninguém altera as proteções (`.claude/**`, `.claudeignore`, settings do usuário) nem troca o modelo da sessão (isso é do usuário: `claude --model`, `--effort`, `/model`).

| Papel | Modelo e esforço | Pode | Não pode |
| --- | --- | --- | --- |
| Entrevista e criação da change | Opus 5.5, `medium` (`high` só em decisão ambígua ou crítica) | Ler o repositório, escrever a change, propor mudanças de configuração em `proposals/` | Alterar proteções; nível C/D sem autorização |
| Implementação e correções | Sonnet 5.5, `medium`; `low` em ajuste simples. Escalar para Opus após 2 tentativas sem sucesso, em sessão nova | Editar código e testes, rodar verificações locais (A e B) | Commit, push, instalar, migrar, deploy sem autorização |
| Subagente de leitura | Haiku 5.5. `tools: Read, Grep, Glob` | Buscar, ler, resumir | Editar, executar comandos, commit |
| Subagente executor de testes | Haiku 5.5. `tools: Read, Grep, Glob, Bash` | Rodar testes, lint e typecheck e devolver só as falhas | Editar arquivos |
| Revisor (`/code-review`) | Opus, contexto limpo | Ler o diff e reportar achados | Aplicar correções sem pedido |

Regras de uso:
- Escolher modelo e esforço **ao abrir a sessão**. Trocar de modelo no meio invalida o cache da conversa inteira.
- `opusplan` não serve ao fluxo OpenSpec: o plan mode não grava arquivos, e cada alternância troca de modelo.
- Quem decide o modelo de um subagente: o parâmetro da chamada, depois o `model` do arquivo `.claude/agents/*.md`, depois `CLAUDE_CODE_SUBAGENT_MODEL`, depois o modelo da sessão. Para forçar todos: `CLAUDE_CODE_SUBAGENT_MODEL` com `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`.
- Regra em `CLAUDE.md` **influencia**, mas não garante a delegação. O que dirige o roteamento é o campo `description` do subagente. O `Explore` embutido herda o modelo da sessão; um subagente customizado chamado `Explore` com `model: haiku` o substitui.
- Skill com `model:` no frontmatter troca o modelo só durante aquele turno e volta no prompt seguinte.

## 4. Limites que continuam abertos

1. **Subprocessos** (`python`, `node`) podem ler o que o `Read` deny e o hook não enxergam. Só o **sandbox** fecha isso.
2. **Grep/Glob** sem `path` varrem o diretório atual; o hook só vê o `path` informado. Fora de um repositório Git, o `ripgrep` pode não aplicar o `.gitignore` (não verificado).
3. **MCP e `WebFetch`** não passam pelo hook de arquivos. Controlar por regras de permissão (`mcp__servidor__ferramenta`, `WebFetch(domain:...)`).
4. **Prefixos de comando** (`env`, `command`, `time`) são tratados pelo hook de `git`, mas outros wrappers não.
5. Sem `onFailure: "block"`, hook que não inicia, estoura o tempo ou falha **deixa a ação passar**. Exige Claude Code 2.1.295 ou superior.

Se quiser fechar o item 1, ligar o sandbox (verificar o resultado em `/sandbox`, aba Config):

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": { "denyRead": ["~/.ssh", "~/.aws", "~/.gnupg", "~/**/.env"] }
  }
}
```

Instalar `bubblewrap` e `socat` (pacotes de mesmo nome em Ubuntu e Arch). Com `allowUnsandboxedCommands: false`, o comando que falha no sandbox não tenta de novo fora dele.

## 5. Como alterar as proteções

O agente **não** edita `.claude/**`, `.claudeignore` nem settings do usuário (`deny`), e não contorna isso por Bash. Quando uma proteção precisar mudar, o agente escreve a proposta em `proposals/claude/` e o usuário aplica:

```bash
cp proposals/claude/settings.json .claude/settings.json
cp proposals/claude/hooks/guard-paths.sh proposals/claude/hooks/test-guard.sh .claude/hooks/
cp proposals/claude/claudeignore .claudeignore
bash .claude/hooks/test-guard.sh
```

Depois, `jq empty .claude/settings.json`, `/hooks` e `/permissions` para conferir, e remover `proposals/`.
