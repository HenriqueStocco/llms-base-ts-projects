# Git

Detalhe das seções 17 de `AGENTS.md`, com exemplos e procedimentos. Não contradiz o núcleo; em caso de divergência, vale o núcleo. A numeração original foi mantida.

## 17. Git

Operações de Git seguem a matriz de risco (16.2).

### 17.1 Escopo e inspeção

- Restringir as alterações ao escopo necessário.
- Não presumir que o working tree está limpo. Antes de qualquer operação relevante, consultar `git status` e identificar: branch atual, alterações staged e unstaged, arquivos não rastreados relevantes e o histórico e as referências necessários.
- Determinar se as alterações existentes pertencem ao usuário, a outra tarefa ou à tarefa em andamento.
- Preservar alterações preexistentes do usuário. Não descartar, sobrescrever nem reverter trabalho alheio sem autorização, nem para simplificar uma operação.
- Não editar à mão arquivos gerados; alterar a fonte e regenerar.
- Não modificar arquivos de configuração apenas para contornar uma falha.
- Inspecionar o diff final e remover alterações inesperadas: arquivos fora do escopo, reformatação acidental, código de depuração, artefatos temporários.
- Manter compatibilidade com consumidores existentes, salvo quebra solicitada e tratada explicitamente (versão, migração, comunicação).

### 17.2 Commits

- Não criar commits sem instrução ou fluxo autorizado que os solicite.
- Preparar commits pequenos, coerentes e relacionados à tarefa.
- Adicionar arquivos por caminho explícito. Evitar adicionar tudo de uma vez quando houver alterações alheias no working tree.
- Revisar o conteúdo staged antes de criar o commit: o que importa é o que será registrado, não o estado geral do diretório.
- Não incluir arquivos sensíveis, artefatos desnecessários nem alterações alheias.
- Não usar `--no-verify`, `--no-gpg-sign` ou bypass equivalente sem autorização explícita e justificativa. Se um hook falhar, corrigir a causa.

```bash
git status --short
git add src/users/service.ts src/users/tests/service.test.ts
git diff --staged
```

### 17.3 Mensagens de commit

Seguir o padrão configurado no projeto. Na ausência de outro contrato explícito, usar Conventional Commits:

```text
<type>(<scope>): <description>
```

```text
feat(auth): add token refresh
fix(users): prevent duplicate registration
test(api): cover invalid request payloads
refactor(core): simplify error handling
docs(core): clarify setup instructions
chore(deps): synchronize package versions
```

- Descrição curta, específica e no idioma e na forma verbal adotados pelo projeto.
- Não inventar tipos, escopos ou exceções que contradigam a configuração existente. Consultar a configuração de validação e o histórico recente.

### 17.4 Push

Pedido para implementar ou commitar não autoriza publicar.

- Não fazer push automaticamente após um commit.
- Confirmar remote, branch e destino antes de publicar.
- Avaliar se o push atualiza uma branch compartilhada.
- Não publicar arquivos sensíveis nem alterações ainda não revisadas.
- Não usar force push como tentativa automática de resolver divergência.
- Respeitar proteções de branch e políticas de revisão.

### 17.5 Pull, merge e rebase

- Inspecionar o estado local antes de integrar alterações remotas.
- Preservar o trabalho não commitado.
- Avaliar conflitos e efeitos sobre o histórico.
- Não resolver conflito escolhendo uma versão automaticamente: entender a intenção dos dois lados.
- Não fazer rebase de branch compartilhada sem autorização.
- Não alterar histórico remoto para simplificar uma integração.
- Preferir operações explícitas e verificáveis.

### 17.6 Operações que descartam ou ocultam trabalho

Exigem cuidado especial, entre outras: `git reset --hard`, `git clean -fd`, `git clean -fdx`, `git checkout -- <path>`, `git restore`, `git stash`, `git stash drop`, `git stash clear`, `git rebase`, `git branch -D`, `git push --force`.

Antes de usar qualquer uma:

1. Examinar o estado do Git.
2. Identificar exatamente quais alterações serão afetadas.
3. Determinar se pertencem ao usuário ou a outra tarefa.
4. Preferir alternativa reversível.
5. Obter autorização quando houver risco de descarte, sobrescrita ou alteração de histórico.

Regras:

- Não usar `git stash` para contornar um working tree sujo. O stash oculta alterações relevantes e dificulta sua recuperação.
- Não usar `git reset --hard`, `git clean -fdx` ou equivalente sem compreender o descarte e ter autorização explícita para ele. `git clean` com `-x` também apaga arquivos ignorados, como `.env` e dependências instaladas.
- Alterações descartadas que nunca foram commitadas, em geral, não são recuperáveis pelo Git.

### 17.7 Worktrees

Úteis para features paralelas, hotfixes e tarefas isoladas. Não criar worktree para tarefa simples quando o fluxo existente bastar.

Antes de criar, alterar ou remover:

- Consultar `git worktree list`.
- Verificar branch e diretório de destino. O Git recusa, por padrão, usar em outra worktree uma branch já vinculada a uma; não forçar.
- Preservar alterações locais e arquivos não rastreados.
- Verificar se há processos ou tarefas em andamento no diretório.
- Não remover uma worktree porque parece antiga: verificar seu estado antes. Não forçar a remoção de uma worktree com alterações.

### 17.8 Tags, releases e histórico compartilhado

- Não criar tag de release, publicar versão ou modificar release sem autorização.
- Não reescrever histórico compartilhado nem forçar atualização de branch remota para resolver conflito.
- Antes de qualquer alteração autorizada de histórico compartilhado, avaliar o impacto sobre colaboradores e pipelines.

