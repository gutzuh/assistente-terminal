#!/bin/bash

VERDE="\033[0;32m"; AMARELO="\033[0;33m"; CIANO="\033[0;36m"; VERMELHO="\033[0;31m"; MAGENTA="\033[0;35m"; NEGRITO="\033[1m"; RESET_COR="\033[0m"


command -v jq >/dev/null 2>&1 || { echo -e >&2 "${VERMELHO}Erro: 'jq' não está instalado.${RESET_COR}"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e >&2 "${VERMELHO}Erro: 'curl' não está instalado.${RESET_COR}"; exit 1; }
command -v git >/dev/null 2>&1 || { echo -e >&2 "${VERMELHO}Erro: 'git' não está instalado.${RESET_COR}"; exit 1; }
command -v perl >/dev/null 2>&1 || { echo -e >&2 "${VERMELHO}Erro: 'perl' não está instalado.${RESET_COR}"; exit 1; }

MODELOS_GERAIS=(
    "openrouter/horizon-beta"
    "google/gemma-2-9b-it:free"
    "mistralai/mistral-7b-instruct:free"
)

MODELOS_CODIGO=(
    "qwen/qwen-2.5-coder-32b-instruct:free"
    "mistralai/devstral-small-2505:free"
    "moonshotai/kimi-dev-72b:free"
    "openrouter/horizon-beta"
)

_obter_contexto_detalhado_sistema() {
    local os_info="N/A"; if [ -f /etc/os-release ]; then os_info=$(source /etc/os-release && echo "$PRETTY_NAME"); elif [[ "$(uname -s)" == "Darwin" ]]; then os_info="$(sw_vers -productName) $(sw_vers -productVersion)"; fi
    printf "%-20s %s
" "OS:" "$os_info"; printf "%-20s %s
" "Arquitetura:" "$(uname -m)"; printf "%-20s %s
" "Kernel:" "$(uname -r)"; printf "%-20s %s
" "Usuário Atual:" "$(whoami)"; printf "%-20s %s
" "Diretório Atual:" "$(pwd)"; printf "%-20s %s
" "Espaço em Disco:" "$(df -h / | awk 'NR==2 {print $4 " livres de " $2}')"; printf "%-20s %s
" "CPU:" "$(sysctl -n machdep.cpu.brand_string 2>&1 || lscpu | grep "Model name" | sed 's/.*: *//')"; printf "%-20s %s
" "RAM Total:" "$(free -h | awk '/^Mem/ {print $2}' 2>&1 || echo "$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024)) GB")"
}

mostrar_ajuda() {
    echo -e "${CIANO}Assistente de Terminal v10.1 (Múltiplas IAs)${RESET_COR}"
    echo "Uso: assistente <comando> [opções]"
    echo ""
    echo -e "${AMARELO}Comandos:${RESET_COR}"
    echo "  ${NEGRITO}codigo <arquivo> --tarefa <descrição>${RESET_COR} - Usa IAs especialistas para analisar seu código."
    echo "  ${NEGRITO}agente [-a|--autonomo] <objetivo>${RESET_COR} - Resolve tarefas de terminal."
    echo "  ${NEGRITO}ia <pergunta>${RESET_COR}                  - Pergunta rápida para uma IA generalista."
    echo "  ${NEGRITO}spec${RESET_COR}                        - Mostra especificações do sistema."
    echo "  ${NEGRITO}git commit${RESET_COR}                  - Cria um commit padronizado."
    echo "  ${NEGRITO}ajuda${RESET_COR}                       - Mostra esta mensagem de ajuda."
}

funcao_ia() {
    local pergunta="$1"; if [ -z "$OPENROUTER_API_KEY" ]; then echo -e "${VERMELHO}Erro: OPENROUTER_API_KEY não definida.${RESET_COR}"; return 1; fi; if [ -z "$pergunta" ]; then echo -e "${VERMELHO}Erro: Forneça uma pergunta.${RESET_COR}"; return 1; fi
    echo -e "${CIANO}Pensando...${RESET_COR}"; local MENSAGEM_SISTEMA="Você é um assistente prestativo."; local resposta_ia=""; local modelo_usado=""
    for modelo in "${MODELOS_GERAIS[@]}"; do
        echo -e "${CIANO}Tentando modelo geral: ${modelo}...${RESET_COR}"
        local corpo_json=$(jq -n --arg model "$modelo" --arg system_msg "$MENSAGEM_SISTEMA" --arg user_msg "$pergunta" '{"model": $model, "messages": [{"role": "system", "content": $system_msg}, {"role": "user", "content": $user_msg}]}')
        resposta_ia=$(curl -s -X POST https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" -d "$corpo_json")
        if ! echo "$resposta_ia" | jq -e '.error' > /dev/null; then modelo_usado=$modelo; break; fi; resposta_ia=""
    done
    if [ -z "$resposta_ia" ]; then echo -e "${VERMELHO}ERRO: Todos os modelos gerais falharam.${RESET_COR}"; return 1; fi
    local conteudo_resposta=$(echo "$resposta_ia" | jq -r '.choices[0].message.content'); echo -e "
${VERDE}--- Resposta (usando ${modelo_usado}) ---${RESET_COR}
${conteudo_resposta}"
}

funcao_spec() { echo -e "${CIANO}--- Especificações do Sistema ---${RESET_COR}"; _obter_contexto_detalhado_sistema; }
funcao_git_commit() { echo -e "${CIANO}Commit Padronizado...${RESET_COR}"; echo -e "${AMARELO}Tipo:${RESET_COR}"; select tipo in "feat" "fix" "docs" "style" "refactor" "test" "chore"; do if [ -n "$tipo" ]; then break; fi; done; echo -e -n "${AMARELO}Mensagem: ${RESET_COR}"; read -r mensagem; if [ -z "$mensagem" ]; then echo -e "${VERMELHO}Cancelado.${RESET_COR}"; return 1; fi; local msg_commit="$tipo: $mensagem"; echo -e -n "${AMARELO}Executar 'git add . && git commit -m \"$msg_commit\"'? (s/N) ${RESET_COR}"; read -r conf; if [[ "$conf" == "s" || "$conf" == "S" ]]; then git add . && git commit -m "$msg_commit"; else echo -e "${VERMELHO}Cancelado.${RESET_COR}"; fi; }

funcao_codigo_analisar() {
    local arquivo="$1"; local tarefa=""; shift
    while (( "$#" )); do case "$1" in --tarefa) if [ -n "$2" ]; then tarefa="$2"; shift 2; else echo "Erro: --tarefa precisa de um valor." >&2; return 1; fi;; *) shift;; esac; done
    if [ ! -f "$arquivo" ]; then echo -e "${VERMELHO}ERRO: Arquivo '${arquivo}' não encontrado.${RESET_COR}"; return 1; fi
    if [ -z "$tarefa" ]; then echo -e "${VERMELHO}ERRO: Especifique uma tarefa com '--tarefa \"sua tarefa\"'.${RESET_COR}"; return 1; fi

    local conteudo_arquivo; conteudo_arquivo=$(cat "$arquivo"); local extensao="${arquivo##*.}"; local linguagem="$extensao"
    echo -e "${CIANO}Analisando '${arquivo}' para a tarefa: '${tarefa}'...${RESET_COR}"

    read -r -d '' prompt_programador <<EOF
Você é um engenheiro de software sênior, especialista na linguagem '${linguagem}'. Sua tarefa é analisar o código e responder ao pedido do usuário.

**TAREFA:** ${tarefa}
**ARQUIVO:** \`${arquivo}\`
**CÓDIGO:**
\`\`\`${linguagem}
${conteudo_arquivo}
\`\`\`
Responda diretamente à tarefa.
EOF

    local resposta_ia=""; local modelo_usado=""
    for modelo in "${MODELOS_CODIGO[@]}"; do
        echo -e "${CIANO}Tentando modelo de código: ${modelo}...${RESET_COR}"
        local corpo_json=$(jq -n --arg model "$modelo" --arg prompt "$prompt_programador" '{"model": $model, "temperature": 0.1, "messages": [{"role": "user", "content": $prompt}]}')
        resposta_ia=$(curl -s -X POST https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" -d "$corpo_json")
        if ! echo "$resposta_ia" | jq -e '.error' > /dev/null; then modelo_usado=$modelo; break; fi; resposta_ia=""
    done

    if [ -z "$resposta_ia" ]; then echo -e "${VERMELHO}ERRO: Todos os modelos de código falharam.${RESET_COR}"; return 1; fi

    local conteudo_resposta=$(echo "$resposta_ia" | jq -r '.choices[0].message.content')
    echo -e "
${VERDE}--- Análise do Código (usando ${modelo_usado}) ---${RESET_COR}
${conteudo_resposta}"
}

funcao_agente() {
    local objetivo="$1"; local modo_autonomo=false; local MAX_PASSOS=15
    if [[ "$1" == "-a" || "$1" == "--autonomo" ]]; then modo_autonomo=true; shift; objetivo="$@"; else objetivo="$@"; fi
    if [ -z "$objetivo" ]; then echo -e "${VERMELHO}Erro: Forneça um objetivo.${RESET_COR}"; return 1; fi

    read -r -d '' MENSAGEM_SISTEMA_AGENTE <<'EOF'
Você é um Agente de IA especialista em um terminal. Seu objetivo é resolver tarefas de automação no sistema de arquivos e executar comandos. Sua resposta DEVE ser um único objeto JSON com as chaves 'pensamento' e 'comando'. Para finalizar, 'comando' deve ser 'FINALIZAR'. Não use 'cd'.
EOF
    echo -e "${CIANO}Objetivo:${RESET_COR} ${NEGRITO}${objetivo}${RESET_COR}"; if [ "$modo_autonomo" = true ]; then echo -e "${VERMELHO}AVISO: MODO AUTÔNOMO ATIVADO.${RESET_COR}"; sleep 2; fi

    local ultima_observacao="Nenhuma ação executada ainda."
    for ((i=1; i<=MAX_PASSOS; i++)); do
        echo -e "
${MAGENTA}--- Passo ${i}/${MAX_PASSOS} ---${RESET_COR}"
        local prompt_completo; read -r -d '' prompt_completo <<EOF
${MENSAGEM_SISTEMA_AGENTE}
CONTEXTO: $(_obter_contexto_detalhado_sistema | tr '
' '; ')
OBJETIVO: ${objetivo}
OBSERVAÇÃO DA ÚLTIMA AÇÃO: ${ultima_observacao}
SEU PRÓXIMO JSON:
EOF
        echo -e "${CIANO}A IA está pensando...${RESET_COR}"

        local resposta_ia=""; local modelo_usado=""
        for modelo in "${MODELOS_GERAIS[@]}"; do
            echo -e "${CIANO}Tentando modelo geral: ${modelo}...${RESET_COR}"
            local corpo_json=$(jq -n --arg model "$modelo" --arg prompt "$prompt_completo" '{"model": $model, "temperature": 0.2, "messages": [{"role": "user", "content": $prompt}]}')
            resposta_ia=$(curl -s -X POST https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" -d "$corpo_json")
            if ! echo "$resposta_ia" | jq -e '.error' > /dev/null; then modelo_usado=$modelo; break; fi; resposta_ia=""
        done

        if [ -z "$resposta_ia" ]; then echo -e "${VERMELHO}ERRO: Todos os modelos falharam.${RESET_COR}"; return 1; fi

        local conteudo_bruto=$(echo "$resposta_ia" | jq -r '.choices[0].message.content'); local conteudo_json=$(echo "$conteudo_bruto" | perl -0777 -ne 's/.*?({.*}).*/$1/s && print')
        if ! echo "$conteudo_json" | jq -e . > /dev/null 2>&1; then echo -e "${VERMELHO}ERRO: IA retornou JSON inválido (${modelo_usado}).${RESET_COR}
${conteudo_bruto}"; ultima_observacao="JSON inválido."; continue; fi

        local pensamento=$(echo "$conteudo_json" | jq -r '.pensamento'); local comando=$(echo "$conteudo_json" | jq -r '.comando')
        echo -e "${VERDE}PENSAMENTO DA IA:${RESET_COR} ${pensamento}"

        if [[ "$comando" == "FINALIZAR" ]]; then
            local resposta_final=$(echo "$conteudo_json" | jq -r '.resposta_final'); echo -e "
${VERDE}--- Objetivo Concluído! ---${RESET_COR}
${NEGRITO}${resposta_final}${RESET_COR}"; return 0
        fi

        echo -e "${AMARELO}AÇÃO (Shell):${RESET_COR} ${comando}"; local executar=false; if [ "$modo_autonomo" = true ]; then executar=true; else echo -e -n "${AMARELO}Deseja executar? (S/N): ${RESET_COR}"; read -r -n 1 conf; echo; if [[ "$conf" == "s" || "$conf" == "S" ]]; then executar=true; fi; fi
        if [ "$executar" = true ]; then echo -e "${CIANO}Executando...${RESET_COR}"; ultima_observacao=$(eval "$comando" 2>&1); else ultima_observacao="Comando não executado."; fi
        if [ -z "$ultima_observacao" ]; then ultima_observacao="Comando executado com sucesso, sem saída de texto."; fi
        echo -e "${VERDE}--- OBSERVAÇÃO ---${RESET_COR}
${ultima_observacao}"
    done
    echo -e "
${VERMELHO}Limite de ${MAX_PASSOS} passos atingido.${RESET_COR}"
}

COMANDO_PRINCIPAL=$1; shift
case $COMANDO_PRINCIPAL in
    codigo) funcao_codigo_analisar "$@";;
    agente) funcao_agente "$@";;
    ia) funcao_ia "$*";;
    spec) funcao_spec;;
    git) SUB_COMANDO_GIT=$1; case $SUB_COMANDO_GIT in commit) funcao_git_commit;; *) echo -e "${VERMELHO}Subcomando '$SUB_COMANDO_GIT' inválido.${RESET_COR}"; mostrar_ajuda;; esac;;
    ajuda|--help|-h|"") mostrar_ajuda;;
    *) echo -e "${VERMELHO}Comando '$COMANDO_PRINCIPAL' desconhecido.${RESET_COR}"; mostrar_ajuda; exit 1;;
esac
