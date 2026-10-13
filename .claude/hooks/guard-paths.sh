#!/usr/bin/env bash
# Hook PreToolUse: aplica .claudeignore às ferramentas de arquivo e ao Bash,
# bloqueia leitura sem limite de arquivos grandes, conteúdo com segredos e as
# formas destrutivas de git (inclusive as que escapam das regras de permissão:
# `git -C`, `git -c`, aspas, caminho completo, `bash -c`).
# Exit 2 bloqueia a chamada; o texto em stderr chega ao modelo.
# Qualquer erro interno também bloqueia (fail closed).
set -euo pipefail

readonly ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
readonly IGNORE_FILE="$ROOT/.claudeignore"
readonly MAX_READ_BYTES=262144

# Subcomandos de git que só leem. Com opções globais (-C, -c...), os demais pedem confirmação.
readonly GIT_READONLY=" status diff log show rev-parse ls-files blame describe shortlog grep cat-file ls-tree merge-base for-each-ref version help "

ASK_REASON=""

die() {
  echo "[guard] BLOQUEADO: $*" >&2
  exit 2
}

trap 'die "erro interno do guard (linha $LINENO)"' ERR

if ! command -v jq >/dev/null 2>&1; then
  die "jq não encontrado. Instale-o para o guard funcionar."
fi

# Resolve "." e ".." textualmente e devolve o caminho sem barra inicial.
normalize() {
  local -a parts=()
  local -a stack=()
  local part

  IFS=/ read -ra parts <<< "$1" || true

  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      ''|.) ;;
      ..) if (( ${#stack[@]} > 0 )); then unset 'stack[-1]'; fi ;;
      *) stack+=("$part") ;;
    esac
  done

  (IFS=/; printf '%s' "${stack[*]:-}")
}

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<< "$input")"
BASE="$(jq -r '.cwd // ""' <<< "$input")"
[[ -n "$BASE" ]] || BASE="$ROOT"
readonly ROOT_N="$(normalize "$ROOT")"

# Imprime o caminho relativo à raiz do projeto. Retorna 1 se estiver fora dela.
to_root_relative() {
  local abs

  if [[ "$1" == /* ]]; then
    abs="$(normalize "$1")"
  else
    abs="$(normalize "$BASE/$1")"
  fi

  if [[ "$abs" == "$ROOT_N" ]]; then
    printf '.'
  elif [[ "$abs" == "$ROOT_N"/* ]]; then
    printf '%s' "${abs#"$ROOT_N"/}"
  else
    return 1
  fi
}

# Verdadeiro se o caminho relativo casa com um padrão no formato gitignore.
# Aproximação: `*` também casa `/`, então o resultado erra para o lado seguro.
matches_pattern() {
  local rel="$1"
  local pat="$2"
  local anchored=0

  pat="${pat%/}"

  if [[ "$pat" == /* ]]; then
    pat="${pat#/}"
    anchored=1
  elif [[ "$pat" == */* && "$pat" != \*\*/* ]]; then
    anchored=1
  fi

  pat="${pat#\*\*/}"

  if (( anchored )); then
    [[ "$rel" == $pat || "$rel" == $pat/* ]]
  else
    [[ "$rel" == $pat || "$rel" == */$pat || "$rel" == $pat/* || "$rel" == */$pat/* ]]
  fi
}

# Verdadeiro se o caminho relativo está listado em .claudeignore.
is_ignored() {
  local rel="$1"
  local line
  local ignored=0

  [[ -f "$IGNORE_FILE" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"

    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi

    if [[ "$line" == !* ]]; then
      if matches_pattern "$rel" "${line#!}"; then
        ignored=0
      fi
    elif matches_pattern "$rel" "$line"; then
      ignored=1
    fi
  done < "$IGNORE_FILE"

  (( ignored ))
}

check_path() {
  local rel

  if rel="$(to_root_relative "$1")" && is_ignored "$rel"; then
    die "\"$rel\" está listado em .claudeignore. Não leia, altere nem use esse caminho. Se ele for indispensável, peça ao usuário."
  fi
}

# Bloqueia leitura sem `limit` de arquivos acima de MAX_READ_BYTES.
check_read_size() {
  local file
  local size

  if [[ -n "$(jq -r '.tool_input.limit // empty' <<< "$input")" ]]; then
    return 0
  fi

  if [[ "$1" == /* ]]; then
    file="$1"
  else
    file="$BASE/$1"
  fi

  [[ -f "$file" ]] || return 0

  size="$(wc -c < "$file")"

  if (( size > MAX_READ_BYTES )); then
    die "arquivo com ${size} bytes excede o limite de leitura. Use offset e limit para ler trechos."
  fi
}

# Bloqueia escrita de conteúdo que parece segredo (chave privada, chave AWS, token GitHub).
check_secrets() {
  local text

  text="$(jq -r '[.tool_input.content?, .tool_input.new_string?, .tool_input.new_source?, .tool_input.edits[]?.new_string?] | map(select(type == "string")) | .[]' <<< "$input")"

  if grep -Eq -e '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----' -e 'AKIA[0-9A-Z]{16}' -e 'gh[pousr]_[A-Za-z0-9]{36}' <<< "$text"; then
    die "o conteúdo parece conter segredo. Remova o valor e use variável de ambiente ou um arquivo já ignorado."
  fi
}

# Verifica cada palavra do comando Bash como possível caminho (best effort).
check_bash() {
  local cmd
  local tok
  local -a tokens=()

  cmd="$(jq -r '.tool_input.command // ""' <<< "$input" | tr '\n\t;&|()<>`' '          ')"
  read -ra tokens <<< "$cmd" || true

  for tok in ${tokens[@]+"${tokens[@]}"}; do
    tok="${tok//[\'\"]/}"
    tok="${tok##*=}"

    if [[ -n "$tok" ]]; then
      check_path "$tok"
    fi
  done
}

# Analisa um segmento de comando (já sem aspas). Bloqueia as formas destrutivas
# de git em qualquer invocação; com opções globais, pede confirmação.
check_git_segment() {
  local -a toks=("$@")
  local n=${#toks[@]}
  local i=0
  local global=0
  local sub
  local r

  # Pula atribuições de ambiente e prefixos (`env`, `sudo`, `bash -c`...).
  while (( i < n )); do
    case "${toks[i]}" in
      *=*|command|env|sudo|nohup|time|exec|nice|xargs|eval|bash|sh|zsh|-c) i=$((i + 1)) ;;
      *) break ;;
    esac
  done

  if (( i >= n )); then
    return 0
  fi

  if [[ "${toks[i]}" != git && "${toks[i]}" != */git ]]; then
    return 0
  fi

  i=$((i + 1))

  # Pula as opções globais que ficam antes do subcomando.
  while (( i < n )); do
    case "${toks[i]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) global=1; i=$((i + 2)) ;;
      --git-dir=*|--work-tree=*|--namespace=*|--config-env=*|-c?*|-C?*) global=1; i=$((i + 1)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done

  if (( i >= n )); then
    return 0
  fi

  sub="${toks[i]}"
  i=$((i + 1))

  case "$sub" in
    reset)
      for r in "${toks[@]:i}"; do
        if [[ "$r" == --hard ]]; then
          die "git reset --hard descarta alterações (nível D). Exige autorização explícita do usuário para esta operação."
        fi
      done
      ;;
    clean)
      die "git clean remove arquivos não rastreados (nível D). Exige autorização explícita do usuário para esta operação."
      ;;
    stash)
      if [[ "${toks[i]:-}" == drop || "${toks[i]:-}" == clear ]]; then
        die "git stash $sub descarta trabalho guardado (nível D). Exige autorização explícita do usuário."
      fi
      ;;
    push)
      for r in "${toks[@]:i}"; do
        if [[ "$r" == --force* || "$r" == --delete || "$r" == -d || "$r" == +* || "$r" == :* || "$r" =~ ^-[a-zA-Z]*f[a-zA-Z]*$ ]]; then
          die "git push com force, delete ou refspec forçado ('$r') reescreve ou apaga histórico remoto (nível D). Exige autorização explícita do usuário."
        fi
      done
      ;;
  esac

  if (( global )) && [[ "$GIT_READONLY" != *" $sub "* ]]; then
    if [[ -z "$ASK_REASON" ]]; then
      ASK_REASON="git com opções globais (-C, -c, --git-dir...) escapa das regras de permissão. Confirme: git $sub"
    fi
  fi
}

# Divide o comando Bash em segmentos (; & | parênteses crase quebra de linha)
# e analisa cada um para git.
check_git() {
  local cmd
  local seg
  local tok
  local -a raw
  local -a toks

  cmd="$(jq -r '.tool_input.command // ""' <<< "$input")"

  while IFS= read -r seg || [[ -n "$seg" ]]; do
    raw=()
    toks=()
    read -ra raw <<< "$seg" || true

    for tok in ${raw[@]+"${raw[@]}"}; do
      toks+=("${tok//[\'\"]/}")
    done

    check_git_segment ${toks[@]+"${toks[@]}"}
  done < <(printf '%s' "$cmd" | tr ';&|()`\n' '\n\n\n\n\n\n\n')
}

case "$tool" in
  Read|Edit|Write|MultiEdit|NotebookEdit|Grep|Glob)
    file_path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""' <<< "$input")"

    if [[ -n "$file_path" ]]; then
      check_path "$file_path"
    fi

    if [[ "$tool" == Read && -n "$file_path" ]]; then
      check_read_size "$file_path"
    fi

    if [[ "$tool" == Write || "$tool" == Edit || "$tool" == MultiEdit || "$tool" == NotebookEdit ]]; then
      check_secrets
    fi
    ;;
  Bash)
    check_bash
    check_git
    ;;
esac

# Decisão "ask": força a confirmação do usuário, sem aprovar nem negar por conta própria.
if [[ -n "$ASK_REASON" ]]; then
  jq -nc --arg reason "[guard] $ASK_REASON" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
fi

exit 0
