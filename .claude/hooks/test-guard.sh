#!/usr/bin/env bash
# Testes do guard-paths.sh. Cada caso roda o hook num projeto temporário
# e compara o código de saída: 0 = permitido, 2 = bloqueado.
# Casos "ask" exigem exit 0 e a decisão "ask" na saída.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="$here/guard-paths.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Segredos falsos montados em tempo de execução: o arquivo não contém nenhum
# literal que pareça segredo (e portanto passa por scanners e pelo próprio guard).
fake_pem="-----BEGIN RSA PRIV""ATE KEY-----"
fake_aws="AKIA""ABCDEFGHIJKLMNOP"
fake_gh="ghp""_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ"

project="$tmp/project"
mkdir -p "$project/src" "$project/secrets" "$project/.kube"
printf '.env\n.env.*\n!.env.example\n*.pem\nid_rsa*\n.ssh/\n.kube/\nsecrets/\n' > "$project/.claudeignore"
printf 'SECRET=1\n' > "$project/.env"
printf 'SECRET=1\n' > "$project/.env.example"
printf 'x\n' > "$project/src/app.ts"
printf 'x\n' > "$project/src/key.pem"
printf 'x\n' > "$project/src/id_rsa"
printf 'x\n' > "$project/secrets/token.txt"
printf 'x\n' > "$project/.kube/config"
printf '{}\n' > "$project/src/nb.ipynb"
head -c 300000 /dev/zero > "$project/big.log"

failures=0

# run <código esperado> <nome> <ferramenta> <tool_input em JSON> [texto esperado na saída]
run() {
  local want="$1"
  local name="$2"
  local tool="$3"
  local input="$4"
  local expect_out="${5:-}"
  local got=0
  local out

  out="$(jq -nc --arg tool "$tool" --arg cwd "$project" --argjson input "$input" \
    '{tool_name: $tool, cwd: $cwd, tool_input: $input}' \
    | CLAUDE_PROJECT_DIR="$project" "$guard" 2>/dev/null)" || got=$?

  if [[ "$got" != "$want" ]]; then
    echo "FAIL  $name (esperado $want, obtido $got)"
    failures=$((failures + 1))
  elif [[ -n "$expect_out" && "$out" != *"$expect_out"* ]]; then
    echo "FAIL  $name (saída sem '$expect_out')"
    failures=$((failures + 1))
  elif [[ -z "$expect_out" && "$want" == 0 && "$out" == *'"ask"'* ]]; then
    echo "FAIL  $name (pediu confirmação sem necessidade)"
    failures=$((failures + 1))
  else
    echo "ok    $name"
  fi
}

# Arquivos
run 2 "Read bloqueia .env"                 Read "{\"file_path\":\"$project/.env\"}"
run 0 "Read permite .env.example (negação)" Read "{\"file_path\":\"$project/.env.example\"}"
run 0 "Read permite arquivo comum"          Read "{\"file_path\":\"$project/src/app.ts\"}"
run 2 "Read bloqueia *.pem em subpasta"     Read "{\"file_path\":\"$project/src/key.pem\"}"
run 2 "Read bloqueia id_rsa"                Read "{\"file_path\":\"$project/src/id_rsa\"}"
run 2 "Read bloqueia diretório secrets/"    Read "{\"file_path\":\"$project/secrets/token.txt\"}"
run 2 "Read bloqueia diretório .kube/"      Read "{\"file_path\":\"$project/.kube/config\"}"
run 2 "Read bloqueia caminho com .. escapando"  Read "{\"file_path\":\"$project/src/../.env\"}"
run 2 "Read bloqueia caminho relativo"      Read "{\"file_path\":\".env\"}"
run 2 "Read sem limit em arquivo grande"    Read "{\"file_path\":\"$project/big.log\"}"
run 0 "Read com limit em arquivo grande"    Read "{\"file_path\":\"$project/big.log\",\"limit\":100}"
run 2 "Grep bloqueia path ignorado"         Grep "{\"pattern\":\"x\",\"path\":\"$project/.env\"}"
run 2 "Glob bloqueia path ignorado"         Glob "{\"pattern\":\"*\",\"path\":\"$project/secrets\"}"
run 2 "Write bloqueia .env"                 Write "{\"file_path\":\"$project/.env\",\"content\":\"A=1\"}"
run 0 "Write permite arquivo comum"         Write "{\"file_path\":\"$project/src/app.ts\",\"content\":\"ok\"}"
run 2 "Write bloqueia chave privada"        Write "{\"file_path\":\"$project/src/novo.ts\",\"content\":\"$fake_pem\"}"
run 2 "Edit bloqueia token AWS em new_string" Edit "{\"file_path\":\"$project/src/app.ts\",\"old_string\":\"x\",\"new_string\":\"$fake_aws\"}"
run 2 "MultiEdit bloqueia token GitHub"     MultiEdit "{\"file_path\":\"$project/src/app.ts\",\"edits\":[{\"old_string\":\"x\",\"new_string\":\"$fake_gh\"}]}"
run 2 "NotebookEdit bloqueia path ignorado" NotebookEdit "{\"notebook_path\":\"$project/secrets/a.ipynb\",\"new_source\":\"x\"}"
run 2 "NotebookEdit bloqueia segredo em new_source" NotebookEdit "{\"notebook_path\":\"$project/src/nb.ipynb\",\"new_source\":\"$fake_aws\"}"
run 0 "NotebookEdit permite conteúdo comum" NotebookEdit "{\"notebook_path\":\"$project/src/nb.ipynb\",\"new_source\":\"print(1)\"}"

# Bash: caminhos
run 2 "Bash bloqueia cat .env"              Bash "{\"command\":\"cat .env\"}"
run 2 "Bash bloqueia redirecionamento <.env" Bash "{\"command\":\"grep A<.env\"}"
run 2 "Bash bloqueia --file=.env"          Bash "{\"command\":\"tool --file=.env\"}"
run 2 "Bash bloqueia encadeado com &&"     Bash "{\"command\":\"ls && cat .env\"}"
run 0 "Bash permite .env.example"          Bash "{\"command\":\"cat .env.example\"}"
run 0 "Bash permite comando sem caminho sensível" Bash "{\"command\":\"git status --short\"}"

# Bash: git destrutivo em qualquer forma
run 2 "git reset --hard"                    Bash "{\"command\":\"git reset --hard HEAD~1\"}"
run 2 "git -C ... reset --hard"             Bash "{\"command\":\"git -C ../outro reset --hard\"}"
run 2 "caminho completo /usr/bin/git"       Bash "{\"command\":\"/usr/bin/git reset --hard\"}"
run 2 "git com aspas no subcomando"         Bash "{\"command\":\"git 'reset' --hard\"}"
run 2 "bash -c com git destrutivo"          Bash "{\"command\":\"bash -c 'git reset --hard'\"}"
run 2 "git clean"                           Bash "{\"command\":\"git clean -fd\"}"
run 2 "git -c ... clean"                    Bash "{\"command\":\"git -c core.x=1 clean -fdx\"}"
run 2 "git stash drop"                      Bash "{\"command\":\"git stash drop\"}"
run 2 "git stash clear"                     Bash "{\"command\":\"git stash clear\"}"
run 2 "push --force depois do remote"      Bash "{\"command\":\"git push origin main --force\"}"
run 2 "push -f depois do remote"           Bash "{\"command\":\"git push origin main -f\"}"
run 2 "push --force-with-lease"            Bash "{\"command\":\"git push --force-with-lease origin main\"}"
run 2 "push refspec forçado (+)"           Bash "{\"command\":\"git push origin +main\"}"
run 2 "push delete por refspec (:)"        Bash "{\"command\":\"git push origin :velha\"}"
run 2 "push --delete"                       Bash "{\"command\":\"git push origin --delete velha\"}"
run 2 "git destrutivo depois de &&"        Bash "{\"command\":\"git log -1 && git push origin main --force\"}"
run 2 "git destrutivo em substituição"     Bash "{\"command\":\"echo \$(git clean -fd)\"}"

# Bash: sem falso positivo
run 0 "push comum não é bloqueado pelo hook" Bash "{\"command\":\"git push origin feature-fix\"}"
run 0 "branch com f no nome"                Bash "{\"command\":\"git push origin hot-fix\"}"
run 0 "rm -f depois de git não vira force"  Bash "{\"command\":\"git status && rm -f /tmp/x\"}"
run 0 "git stash list"                      Bash "{\"command\":\"git stash list\"}"
run 0 "git reset --soft"                    Bash "{\"command\":\"git reset --soft HEAD~1\"}"
run 0 "texto 'git' como argumento"          Bash "{\"command\":\"echo git reset --hard\"}"

# Bash: git com opções globais pede confirmação, exceto leitura
run 0 "git -C commit pede confirmação"      Bash "{\"command\":\"git -C ../outro commit -m x\"}" '"ask"'
run 0 "git -c push pede confirmação"        Bash "{\"command\":\"git -c push.default=current push\"}" '"ask"'
run 0 "git -C status não pede"              Bash "{\"command\":\"git -C ../outro status\"}"
run 0 "git --git-dir log não pede"          Bash "{\"command\":\"git --git-dir=../x/.git log -1\"}"

# Ferramentas fora do escopo e entrada inválida
run 0 "Ferramenta não coberta passa"        Skill "{\"skill\":\"x\"}"

bad_json_got=0
echo 'não é json' | CLAUDE_PROJECT_DIR="$project" "$guard" >/dev/null 2>&1 || bad_json_got=$?

if [[ "$bad_json_got" == 2 ]]; then
  echo "ok    JSON inválido bloqueia (fail closed)"
else
  echo "FAIL  JSON inválido bloqueia (esperado 2, obtido $bad_json_got)"
  failures=$((failures + 1))
fi

echo
if (( failures > 0 )); then
  echo "$failures teste(s) falharam."
  exit 1
fi

echo "Todos os testes passaram."
