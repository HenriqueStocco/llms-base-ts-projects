# Tooling de qualidade, hooks e CI

Detalhe das seções 15 de `AGENTS.md`, com exemplos e procedimentos. Não contradiz o núcleo; em caso de divergência, vale o núcleo. A numeração original foi mantida.

## 15. Tooling de qualidade, hooks e CI

Regras **comportamentais** (este documento) orientam o julgamento do agente. Verificações **automatizadas** impõem o que pode ser checado por máquina. Uma não substitui a outra.

### 15.1 Controles e política

Controles proporcionais ao projeto:

- Formatador e lint.
- Typecheck.
- Testes direcionados e suíte completa.
- Build.
- Detecção de código e dependências não utilizados.
- Consistência de versões de dependências.
- Scanner de segredos.
- Verificação de dependências e vulnerabilidades.
- Hooks de Git.
- Hooks do agente, quando a plataforma oferecer.
- CI obrigatório em branches protegidas.
- Proteções para comandos destrutivos e operações sensíveis.

Nenhum desses controles é capacidade universal. Verificar o que o projeto e a plataforma realmente oferecem; não presumir que um hook ou uma checagem existe.

Política:

- Não ignorar verificação essencial em silêncio.
- Não usar mecanismo de bypass (pular hooks, desativar regra, marcar teste como ignorado) para contornar falha sem autorização e justificativa registrada.
- Não declarar verificação aprovada sem evidência: comando executado e resultado obtido. Não fingir que uma ferramenta está instalada.
- Durante o desenvolvimento, preferir verificações direcionadas e rápidas. Não executar suíte muito lenta a cada passo quando uma verificação mais eficiente for adequada. Executar as verificações completas aplicáveis antes de concluir, ou registrar por que não foi possível.
- Tratar o CI como a fonte de validação reproduzível.
- Tratar hooks locais como proteção complementar, não como substitutos do CI. Toda validação crítica também existe no CI.

### 15.2 Ferramentas padrão

Padrão preferido dos projetos cobertos por este documento, salvo incompatibilidade técnica comprovada ou decisão explícita do projeto:

| Ferramenta | Função |
| --- | --- |
| **Biome** | Formatação e lint. |
| **Knip** | Arquivos, exports e dependências não utilizados. |
| **Syncpack** | Consistência de versões de dependências entre manifestos. |
| **Scripts Bash + Git hooks** | Validações automáticas e padronização de mensagens de commit. |

Esse padrão não autoriza ignorar a stack existente. Antes de instalar ou configurar qualquer ferramenta:

1. Verificar se ela já está instalada.
2. Examinar versões, scripts e configuração existentes.
3. Consultar a documentação compatível com a versão instalada. Comandos, flags e opções mudam entre versões principais.
4. Verificar a compatibilidade com Bun, Node.js, o gerenciador de pacotes e o formato do repositório.
5. Reutilizar e completar a configuração existente quando apropriado.
6. Não duplicar funcionalidade sem benefício concreto.
7. Não substituir em silêncio outra ferramenta já estabelecida.
8. Registrar toda exceção técnica relevante.

Regras:

- Não inventar nomes de opções, scripts, flags ou comandos. Usar os scripts do manifesto e a ajuda da versão instalada.
- Se uma ferramenta for incompatível com o projeto, documentar o motivo e propor a alternativa mínima necessária.
- A ausência de uma ferramenta padrão é um achado de classe **Atenção** (4.3). Instalar ou configurar tooling é tarefa própria: não fazê-lo como efeito colateral de outra tarefa.

### 15.3 Biome

Ferramenta padrão de formatação e lint, quando a versão instalada suportar as linguagens do projeto.

- Configurar regras consistentes e compatíveis com o projeto.
- Usar modo de verificação, sem escrita, no CI.
- Aplicar correções automáticas somente nos arquivos do escopo pretendido, e revisar o resultado.
- Não ignorar regra sem justificativa escrita junto à supressão.
- Não desabilitar regra globalmente para resolver um problema localizado.
- Não executar formatadores concorrentes sobre os mesmos arquivos.
- Não afirmar que o projeto está formatado sem executar a verificação correspondente.
- A separação visual da seção 9 continua obrigatória onde o formatador não a impõe.

### 15.4 Knip

Configurar respeitando entry points, plugins e particularidades do projeto.

- Executar após mudanças relevantes em arquivos, exports, scripts ou dependências.
- Investigar cada resultado antes de remover qualquer coisa. A ausência de referência estática não prova que algo é desnecessário.
- Verificar entry points, imports dinâmicos, convenções de frameworks e plugins, scripts do manifesto, configuração de CI e arquivos referenciados indiretamente.
- Não remover arquivo ou export apenas porque a análise não detectou uso.
- Não fazer remoção em massa sem revisar o impacto.
- Não ignorar falsos positivos globalmente. Preferir exceções localizadas, documentadas e justificadas.
- Reavaliar as regras de ignore quando o código mudar.

### 15.5 Syncpack

Manter versões e manifestos consistentes, especialmente em monorepos. O objetivo é consistência compatível, não uniformidade artificial.

- Verificar a configuração existente, as políticas de versão, as dependências internas e as exceções necessárias.
- Executar a verificação de consistência após mudanças em dependências.
- Corrigir divergências de forma intencional, avaliando a compatibilidade antes de sincronizar.
- Não alinhar às cegas versões incompatíveis.
- Não atualizar dependência apenas para eliminar diferença numérica.
- Não alterar lockfile sem entender a causa e revisar o resultado.
- Preservar exceções justificadas de ferramentas, runtimes ou pacotes que exigem versões distintas.

### 15.6 Scripts Bash

Centralizar validações e regras de commit em scripts Bash versionados, quando o ambiente for compatível. Os hooks chamam os scripts; não duplicam comandos longos.

Cada script:

- Tem nome e responsabilidade claros.
- Falha com código de saída diferente de zero e propaga erros dos comandos que executa.
- Emite mensagens claras, na saída de erro, dizendo o que falhou e como corrigir.
- Não imprime segredos.
- Não executa comando destrutivo como efeito colateral de uma validação.
- É previsível e reproduzível: mesma entrada, mesmo resultado.
- Verifica a existência dos comandos de que depende e informa quando faltam.
- Não depende do diretório de execução: resolve caminhos a partir da raiz do repositório.
- Usa quoting consistente e trata caminhos com espaços.
- Tem teste quando contém lógica relevante.

Plataforma de referência: Linux, em mais de uma distribuição. Os scripts funcionam sem alteração em distribuições diferentes (por exemplo, Ubuntu e Arch):

- Declarar `#!/usr/bin/env bash` e executar com Bash. Não depender de `/bin/sh`: em algumas distribuições ele é o Bash, em outras é um shell mais restrito.
- Não presumir a mesma versão de Bash, de utilitários ou de ferramentas instaladas: distribuições de lançamento contínuo e de lançamento fixo divergem.
- Não chamar gerenciador de pacotes do sistema (`apt`, `pacman` etc.) nem depender de caminhos específicos de uma distribuição. Verificar se o comando existe e informar o que falta.
- macOS e Windows só entram como requisito quando o projeto declarar suporte; nesse caso, declarar os requisitos e evitar extensões exclusivas dos utilitários GNU.

Exemplo — validação de mensagem para o hook `commit-msg`. O Git passa como primeiro argumento o caminho do arquivo que contém a mensagem:

```bash
#!/usr/bin/env bash
set -euo pipefail

message_file="${1:?uso: commit-msg <arquivo-da-mensagem>}"
pattern='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9-]+\))?!?: .+'

IFS= read -r subject < "$message_file" || true

if [[ ! "$subject" =~ $pattern ]]; then
  echo "Mensagem de commit inválida: \"$subject\"" >&2
  echo "Formato esperado: <type>(<scope>): <description>" >&2
  exit 1
fi
```

Tipos, escopos e exceções (commits de merge ou de revert gerados pelo Git, por exemplo) seguem a convenção do projeto (17.3).

### 15.7 Git hooks

Todo projeto adota hooks locais para os eventos abaixo. Verificar a semântica real de cada hook na documentação do Git e do gerenciador de hooks em uso antes de configurá-lo.

| Hook | Momento | Responsabilidade |
| --- | --- | --- |
| `commit-msg` | Depois de escrita a mensagem, antes de o commit ser criado. | Validar a mensagem. |
| `pre-commit` | Antes de o commit ser criado. | Verificações rápidas sobre o conteúdo staged. |
| `pre-push` | Antes de o push transferir dados ao remoto. | Verificações adicionais antes de publicar. |

**`commit-msg`**

- Validar a mensagem real recebida do Git, sem texto fixo no script.
- Aplicar a convenção de commits do projeto (17.3).
- Rejeitar mensagem vazia ou fora do padrão, com erro claro e acionável.

**`pre-commit`**

- Verificar os arquivos que serão commitados, não o repositório inteiro.
- Verificar ou aplicar formatação e lint, conforme a política do projeto.
- Detectar arquivos proibidos, artefatos indevidos e segredos, quando houver ferramenta disponível.
- Não executar a suíte E2E nem verificações lentas a cada commit.
- Se o formatador modificar arquivos, garantir que o commit contenha o resultado formatado **sem** incluir alterações que o usuário não havia colocado em stage. Arquivos parcialmente staged exigem cuidado: adicionar o arquivo inteiro de volta incluiria o que foi deixado de fora de propósito.

**`pre-push`**

- Executar typecheck, testes direcionados e demais verificações relevantes ao projeto.
- Identificar o destino (o Git informa o remoto e as referências ao hook) e bloquear publicações que violem as regras do projeto.
- Não fazer deploy nem operações adicionais inesperadas.
- Não repetir verificações lentas que o CI já executa por completo.

**`push`**

O Git **não possui** um hook de cliente chamado `push`, e `pre-push` não é equivalente a ele. No cliente, o hook do estágio de publicação é `pre-push`. Hooks que executam após o recebimento dos dados (`pre-receive`, `update`, `post-receive`) rodam no servidor e dependem do provedor de hospedagem.

- Se o gerenciador de hooks ou a plataforma do projeto oferecer um evento próprio para esse estágio, documentar sua finalidade e não duplicar o que `pre-push` já cobre.
- Se não oferecer, não inventar o hook. Colocar a proteção em `pre-push` e no CI, e informar a limitação.

**Instalação e manutenção**

- Verificar como os hooks são instalados e ativados. O Git só executa hooks no diretório de hooks efetivo: o padrão, dentro do diretório `.git` e não versionado, ou o definido por `core.hooksPath`.
- Um diretório de hooks versionado não tem efeito até ser ativado, pelo gerenciador de hooks ou por `core.hooksPath`.
- Garantir instalação reproduzível para novos colaboradores e documentar como reinstalar e validar.
- Não contornar hooks para concluir uma tarefa mais rápido (15.1).

### 15.8 Segurança dos hooks

Hooks executam código arbitrário na máquina de cada colaborador e fazem parte da superfície de ataque.

- Inspecionar os scripts e as ferramentas executados pelos hooks.
- Não introduzir download ou instalação remota não verificada durante um commit ou push.
- Não armazenar credenciais nos scripts.
- Não usar `eval` nem execução dinâmica de conteúdo não confiável.
- Evitar permissões excessivas.
- Não alterar arquivos fora do escopo do commit.
- Não mascarar erro nem retornar sucesso artificial.
- Evitar loops, instalações recursivas e execução duplicada das mesmas verificações.
- Emitir mensagem clara quando uma dependência estiver ausente.
- Não desabilitar hooks como solução permanente para um erro de configuração: corrigir a configuração.

### 15.9 Arquivos essenciais do repositório

Avaliar presença e adequação. Criar ou atualizar somente o que for aplicável e necessário.

**`.gitignore`**

- Ignorar dependências instaladas, artefatos gerados, caches, logs e arquivos locais não versionáveis.
- Ignorar `.env` e demais arquivos de credenciais, mantendo exceção explícita para modelos seguros, como `.env.example`.
- Não ignorar arquivos necessários ao build ou ao desenvolvimento. Evitar padrões amplos que escondam arquivos importantes.
- Adicionar uma regra não remove do índice um arquivo já rastreado: isso exige tratamento específico.
- Não remover arquivos rastreados sem compreender o impacto. Um segredo que já foi commitado continua no histórico e deve ser tratado como comprometido.

**`.gitattributes`**

- Definir normalização de fim de linha coerente quando necessário (por exemplo, `text=auto`) e marcar formatos binários.
- Evitar diffs espúrios entre sistemas operacionais. Preservar binários e formatos especiais.
- Avaliar o impacto antes de aplicar uma normalização em massa a arquivos existentes: ela altera muitos arquivos de uma vez.
- Não impor regras indiscriminadas a todos os arquivos.

**`.claudeignore` e arquivos de exclusão de contexto de agentes**

- Verificar, na documentação da ferramenta e da versão em uso, se o arquivo é reconhecido e qual é sua semântica. Não presumir suporte.
- Não é mecanismo universal nem barreira de segurança. Nunca depender dele para proteger segredos.
- Quando reconhecido, usá-lo para reduzir contexto irrelevante: artefatos, arquivos gerados, caches e dados locais.
- Não excluir arquivos essenciais ao entendimento do projeto.
- Distinguir três coisas: arquivo ignorado pelo Git, arquivo omitido do contexto do agente e arquivo protegido por controle de acesso.
- Se a ferramenta não reconhecer o arquivo, informar a limitação e usar o mecanismo oficialmente suportado por ela (regras de permissão ou de negação de leitura, por exemplo).

**Demais arquivos**

Inspecionar, conforme a stack: manifesto (`package.json`), lockfile do gerenciador em uso, `tsconfig.json`, configurações do Biome, do Knip e do Syncpack, scripts de validação, configuração e instalação dos hooks, configuração de CI.

### 15.10 Ordem de implementação do tooling

Ao adotar ou atualizar tooling em um projeto existente:

1. Inspecionar ferramentas, versões, scripts e hooks existentes.
2. Identificar o que já funciona e o que falta.
3. Definir as verificações e os contratos necessários.
4. Reutilizar as configurações válidas.
5. Implementar as mudanças mínimas.
6. Validar scripts e configurações.
7. Executar as verificações locais.
8. Inspecionar o diff e o estado do Git.
9. Documentar exceções, limitações e comandos relevantes.

Não substituir toda a configuração do projeto para obter um padrão visualmente uniforme.

Quando a tarefa for apenas criar ou atualizar instruções para agentes, não instalar dependências, não configurar hooks reais e não modificar os demais arquivos do projeto.

### 15.11 Regras verificáveis por ferramenta

Quando o projeto tiver o controle correspondente, usá-lo como evidência. Ao configurar um projeto novo, preferir automatizar:

| Regra | Verificação possível |
| --- | --- |
| Tipagem estrita (6) | Modo `strict` do compilador; opções adicionais de rigor conforme o projeto. |
| `any` explícito, non-null assertion, supressões (6.1, 6.4) | Regras de lint (Biome). |
| `catch` vazio, promessas não tratadas (11) | Regras de lint, conforme o suporte da versão instalada. |
| Formatação (9) | Formatador em modo de verificação (Biome). |
| Nomes de arquivos (8.1) | Regra de lint de nomenclatura, se disponível. |
| Código, exports e dependências sem uso (8.4, 14) | Knip. |
| Versões divergentes entre manifestos (7.1, 14) | Syncpack. |
| Dependências circulares e fronteiras entre pacotes (7) | Análise de grafo de dependências ou regras de lint. |
| Mensagem de commit (17.3) | Hook `commit-msg`. |
| Segredos em commits (5.2) | Scanner de segredos, em `pre-commit` e no CI. |
| Dependências vulneráveis (14) | Auditoria de dependências. |
| Comportamento (12) | Testes em `pre-push` (direcionados) e no CI (completos). |

O restante depende de revisão do diff.

