#!/bin/bash

set -e

# Script feito por Lucas Lopes para cortar dados em latitude, longitude, período e grade

# Modificado por Heric Camargo

set_colors() {
    RED='\033[1;31m'        # Vermelho brilhante
    GREEN='\033[1;32m'      # Verde brilhante
    YELLOW='\033[1;93m'     # Amarelo claro
    BLUE='\033[1;36m'       # Azul claro ciano
    MAGENTA='\033[1;35m'    # Magenta brilhante
    NC='\033[0m'            # Sem cor (reset)
}

# Testa se está em um terminal para exibir cores
if [ -t 1 ] && ! grep -q -e '--no-color' <<<"$@"
then
    set_colors
fi

# Definir os cortes espaciais disponíveis e seus parâmetros
declare -A CORTES_ESPACIAIS
CORTES_ESPACIAIS["as"]="-sellonlatbox,-82.50,-32.50,-56.25,16.25"
CORTES_ESPACIAIS["polos"]="-sellonlatbox,0,360,-58.75,58.75"
CORTES_ESPACIAIS["pr"]="-sellonlatbox,-55,-48,-27,-22"
CORTES_ESPACIAIS["br"]="-sellonlatbox,-75,-34,-35,5"
CORTES_ESPACIAIS["cwb"]="-sellonlatbox,-50,-49,-26,-25"
# Adicione novos cortes aqui
# CORTES_ESPACIAIS["novo_corte"]="-sellonlatbox,param1,param2,param3,param4"

# Função de ajuda
function ajuda() {
    echo -e "${YELLOW}Uso: ${GREEN}$0 ${BLUE}-i${GREEN} INPUT ${BLUE}-o${GREEN} EXTENSÃO [${BLUE}-t${GREEN} ANO_INI-ANO_FIM] [${BLUE}-g${GREEN} GRADE] [${BLUE}-s${GREEN} CORTE_ESPACIAL] [${BLUE}-c${GREEN}] [${BLUE}-m${GREEN}] [${BLUE}-x${GREEN}]${NC}"
    echo
    echo -e "${YELLOW}Opções:${NC}"
    echo -e "${BLUE}  -i INPUT             ${NC}Arquivo(s) de entrada ${YELLOW}(obrigatório)${NC}"
    echo -e "${BLUE}                       ${NC}Pode ser: caminho de um arquivo, diretório, ou lista de arquivos separados por espaço${NC}"
    echo -e "${BLUE}  -o EXTENSÃO          ${NC}Extensão do arquivo de saída: nc ou ctl ${YELLOW}(obrigatório)${NC}"
    echo -e "${BLUE}  -t ANO_INI-ANO_FIM   ${NC}Período de tempo${NC}"
    echo -e "${BLUE}  -g GRADE             ${NC}Grade para remapeamento${NC}"
    echo -e "${BLUE}  -s CORTE_ESPACIAL    ${NC}Recorta o Dado${NC}"
    echo -e "${BLUE}  -c                   ${NC}Indica que o arquivo é de chuva e deve ser processado com 'divdpm'${NC}"
    echo -e "${BLUE}  -m                   ${NC}Mascara o oceano (mantém apenas dados terrestres)${NC}"
    echo -e "${BLUE}  -x                   ${NC}Omite informações no nome do arquivo final (mantém apenas data)${NC}"
    echo -e "${YELLOW}Grades:${NC}"
    echo -e "${BLUE}  r720x360 ${NC}: 720x360 (0.5x0.5)${NC}"
    echo -e "${BLUE}  r360x180 ${NC}: 360x180 (1x1)${NC}"
    echo -e "${BLUE}  r144x72  ${NC}: 144x72  (2.5x2.5)${NC}"
    echo -e "${BLUE}  r72x36   ${NC}: 72x36   (5x5)${NC}"
    echo -e "${YELLOW}Cortes espaciais disponíveis:${NC}"
    for corte in "${!CORTES_ESPACIAIS[@]}"; do
        printf "${BLUE}  %-8s${NC} : %s\n" "$corte" "${CORTES_ESPACIAIS[$corte]}"
    done
    echo -e "${YELLOW}Exemplos:${NC}"
    echo -e "${MAGENTA}  $0 ${NC}-i dados.ctl -o nc -t 1950-2020 -g r144x72 -s as -c${NC}"
    echo -e "${MAGENTA}  $0 ${NC}-i dados.nc -o ctl -g r144x72${NC}"
    echo -e "${MAGENTA}  $0 ${NC}-i dados.nc -o nc -t 2000-2010${NC}"
    echo -e "${MAGENTA}  $0 ${NC}-i /caminho/do/diretorio -o nc -t 1950-2020${NC}"
    echo -e "${MAGENTA}  $0 ${NC}-i arquivo1.nc arquivo2.nc arquivo3.nc -o nc -g r144x72${NC}"
}

log_to_ctl() {
    local msg="$1"
    # Acumula a mensagem de log na variável, adicionando uma nova linha
    LOG_ENTRIES+="$([[ -z "$LOG_ENTRIES" ]] && echo "" )* $(date +"%Y-%m-%d %H:%M:%S") - $msg"$'\n'
}

# Inicializa as variáveis com valores padrão
INPUT=""
EXTENSAO_SAIDA=""
PERIODO=""
GRADE=""
CORTE_ESPACIAL=""
PROCESSAR_CHUVA=0
MASCARAR_OCEANO=0
OMITIR_SUFIXOS=0
LOG_ENTRIES=""               # Variável para acumular logs

# Processa os argumentos usando getopts
while getopts "i:o:t:g:s:hcmx" opt; do
    case $opt in
        i)
            INPUT="$OPTARG"
            ;;
        o)
            EXTENSAO_SAIDA="$OPTARG"
            ;;
        t)
            PERIODO="$OPTARG"
            ;;
        g)
            GRADE="$OPTARG"
            ;;
        s)
            CORTE_ESPACIAL="$OPTARG"
            ;;
        c)
            PROCESSAR_CHUVA=1
            ;;
        m)
            MASCARAR_OCEANO=1
            ;;
        x)
            OMITIR_SUFIXOS=1
            ;;
        h | *)
            ajuda
            exit 0
            ;;
    esac
done

# Verificações das entradas:

# Verifica se os argumentos obrigatórios foram fornecidos
if [ -z "$INPUT" ] || [ -z "$EXTENSAO_SAIDA" ]; then
    echo -e "${RED}Erro: Os argumentos -i e -o são obrigatórios.${NC}"
    ajuda
    exit 1
fi

# Verifica o tipo de entrada para o modo batch
# if [ "$MODO_BATCH" -eq 1 ]; then
    # Prepara a lista de arquivos a serem processados
    ARQUIVOS_PARA_PROCESSAR=()
    
    # Verifica se a entrada é um diretório
    if [ -d "$INPUT" ]; then
        echo -e "${GREEN}Processando todos os arquivos .nc e .ctl no diretório: $INPUT${NC}"
        # Coleta todos os arquivos .nc e .ctl no diretório
        while IFS= read -r arquivo; do
            ARQUIVOS_PARA_PROCESSAR+=("$arquivo")
        done < <(find "$INPUT" -maxdepth 1 -type f \( -name "*.nc" -o -name "*.ctl" \) | sort)
        
        if [ ${#ARQUIVOS_PARA_PROCESSAR[@]} -eq 0 ]; then
            echo -e "${RED}Nenhum arquivo .nc ou .ctl encontrado no diretório: $INPUT${NC}"
            exit 1
        fi
    else
        # Trata como uma lista de arquivos separados por espaço
        # Usar eval para expandir wildcards e lidar com múltiplos arquivos
        read -ra ARQUIVOS_PARA_PROCESSAR <<< $(eval echo "$INPUT")
        
        # Verifica se todos os arquivos existem
        for arquivo in "${ARQUIVOS_PARA_PROCESSAR[@]}"; do
            if [ ! -f "$arquivo" ]; then
                echo -e "${RED}Arquivo não encontrado: $arquivo${NC}"
                exit 1
            fi
            
            # Verifica a extensão do arquivo
            ext="${arquivo##*.}"
            if [[ "$ext" != "nc" && "$ext" != "ctl" ]]; then
                echo -e "${RED}Arquivo com extensão inválida: $arquivo. Somente arquivos .nc e .ctl são suportados.${NC}"
                exit 1
            fi
        done
    fi
    
    echo -e "${GREEN}Total de arquivos a processar: ${#ARQUIVOS_PARA_PROCESSAR[@]}${NC}"
# else
#     # Modo padrão: verifica se o arquivo existe
#     if [ ! -f "$INPUT" ]; then
#         echo -e "${RED}Arquivo $INPUT inválido.${NC}\n"
#         exit 1
#     fi
# fi

if [[ "$EXTENSAO_SAIDA" != "nc" && "$EXTENSAO_SAIDA" != "ctl" ]]; then
    echo -e "${RED}Extensão para o arquivo de saída inválida. Extensões permitidas: nc e ctl${NC}\n"
    exit 1
fi

if [ -n "$CORTE_ESPACIAL" ]; then
    if [[ ! -v CORTES_ESPACIAIS["$CORTE_ESPACIAL"] ]]; then
        echo -e "${RED}Opção de corte espacial inválida. Opções válidas: ${!CORTES_ESPACIAIS[@]}${NC}\n"
        exit 1
    fi
fi

if [ -n "$PERIODO" ]; then
    if [[ ! "$PERIODO" =~ ^[0-9]{4}-[0-9]{4}$ ]]; then
        echo -e "${RED}Período de tempo inválido. Use o formato ANO_INI-ANO_FIM${NC}\n"
        exit 1
    fi
    ANO_I=$(echo "$PERIODO" | cut -d'-' -f1)
    ANO_F=$(echo "$PERIODO" | cut -d'-' -f2)
fi

################################## PARÂMETROS ##################################

# Diretório do arquivo de entrada
DIR_IN=$(dirname "$(realpath "$INPUT")")

if [ ! -d "$DIR_IN" ]; then
    echo -e "${RED}Diretório $DIR_IN inexistente!${NC}\n"
    exit 1
fi

if [ -d "$INPUT" ]; then
    # INPUT é um diretório; pulamos a verificação de extensão
    :
else
    BASE_NAME=$(basename "$INPUT")
    PREFIXO="${BASE_NAME%.*}"
    EXTENSAO="${BASE_NAME##*.}"
    
    if [[ "$EXTENSAO" != "nc" && "$EXTENSAO" != "ctl" ]]; then
        echo -e "${RED}Extensão $EXTENSAO inválida. Extensões permitidas: .nc e .ctl${NC}\n"
        exit 1
    fi
fi

# Especificar quais transformações serão feitas
AJUSTAR_CALENDARIO=1
SINCRONIZAR_DATA=1
APAGAR_TMP=1 # Se ativado, apaga os arquivos intermediários

# Cria um diretório temporário seguro e define uma função para limpar ao sair
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Funções para modularizar o código
cortar_polos() {
    echo -e "${GREEN}Cortando latitude e longitude dos polos!${NC}"
    cdo -O -sellonlatbox,0,360,-58.75,58.75 "$1" "$2"
    if [ $? -ne 0 ]; then
        echo "Erro ao executar cdo -sellonlatbox"
        exit 1
    fi
}

# Funções para analisar e limpar o nome do arquivo
extrair_nome_base() {
    local nome="$1"
    # Remove padrões comuns (data, grade, cortes espaciais) do nome
    
    # Primeiro remove os cortes espaciais conhecidos
    for corte in "${!CORTES_ESPACIAIS[@]}"; do
        nome=$(echo "$nome" | sed "s/_${corte}//g")
    done
    
    # Remove grades comuns
    nome=$(echo "$nome" | sed -E 's/_r(720x360|360x180|144x72|72x36)//g')
    
    # Remove padrões de data (XXXX-XXXX)
    nome=$(echo "$nome" | sed -E 's/_[0-9]{4}-[0-9]{4}//g')
    
    # Remove sufixos de processamento
    nome=$(echo "$nome" | sed 's/_chuva//g')
    nome=$(echo "$nome" | sed 's/_land//g')
    
    echo "$nome"
}

construir_nome_final() {
    # Extrai o nome base sem informações de processamento anteriores
    local nome=$(extrair_nome_base "$PREFIXO")
    
    # Adiciona apenas as informações relevantes conforme as opções
    [ -n "$PERIODO" ] && nome+="_${ANO_I}-${ANO_F}"
    
    # Se não estiver no modo de omissão, adiciona os outros sufixos
    if [ "$OMITIR_SUFIXOS" -eq 0 ]; then
        [ -n "$GRADE" ] && nome+="_${GRADE}"
        [ -n "$CORTE_ESPACIAL" ] && nome+="_${CORTE_ESPACIAL}"
        [ "$PROCESSAR_CHUVA" -eq 1 ] && nome+="_chuva"
        [ "$MASCARAR_OCEANO" -eq 1 ] && nome+="_land"
    fi
    
    echo "$nome"
}

mascarar_terra() {
    echo -e "${GREEN}Mascarando o oceano (mantendo apenas dados terrestres)${NC}"
    cdo -f nc setctomiss,0 -gtc,0 -remapcon,"$1" -topo "$TMP_DIR/seamask.nc"
    if [ $? -ne 0 ]; then
        echo "Erro ao executar cdo para criar a máscara terrestre"
        exit 1
    fi
    cdo mul "$1" "$TMP_DIR/seamask.nc" "$2"
    if [ $? -ne 0 ]; then
        echo "Erro ao executar cdo para aplicar a máscara terrestre"
        exit 1
    fi
}

# Função principal de processamento para um arquivo
processar_arquivo() {
    local arquivo_entrada="$1"
    
    echo -e "${YELLOW}Processando: ${BLUE}$arquivo_entrada${NC}"
    
    # Diretório do arquivo de entrada
    local dir_in=$(dirname "$(realpath "$arquivo_entrada")")
    
    if [ ! -d "$dir_in" ]; then
        echo -e "${RED}Diretório $dir_in inexistente!${NC}\n"
        return 1
    fi
    
    local base_name=$(basename "$arquivo_entrada")
    local prefixo="${base_name%.*}"
    local extensao="${base_name##*.}"
    
    if [[ "$extensao" != "nc" && "$extensao" != "ctl" ]]; then
        echo -e "${RED}Extensão $extensao inválida. Extensões permitidas: .nc e .ctl${NC}\n"
        return 1
    fi
    
    # Cria um diretório temporário seguro para este arquivo
    local tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN
    
    local output
    local log_entries=""
    
    # Converte o arquivo ctl para nc se necessário
    if ([[ "$extensao" == "ctl" ]]); then
        echo -e "${GREEN}Convertendo arquivo para .nc${NC}"
        cdo -f nc import_binary "$arquivo_entrada" "$tmp_dir/${prefixo}.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo import_binary"
            return 1
        fi
        output="$tmp_dir/${prefixo}.nc"
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Converted to netCDF: Command: cdo -f nc import_binary \"$arquivo_entrada\" \"$tmp_dir/${prefixo}.nc\""$'\n'
    else
        output="$arquivo_entrada"
    fi
    
    # Validar se as variáveis output e prefixo estão definidas
    if [ -z "$output" ] || [ -z "$prefixo" ]; then
        echo -e "${RED}Variáveis output ou prefixo não definidas.${NC}"
        return 1
    fi
    
    if [[ $AJUSTAR_CALENDARIO -eq 1 ]]; then
        echo -e "${GREEN}Ajustando o calendário${NC}"
        cdo -O -setcalendar,standard -setmissval,-7777.7 "$output" "$tmp_dir/${prefixo}_calendar.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo -setcalendar"
            return 1
        fi
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Adjusted calendar: Command: cdo -O -setcalendar,standard -setmissval,-7777.7 \"$output\" \"$tmp_dir/${prefixo}_calendar.nc\""$'\n'
        output="$tmp_dir/${prefixo}_calendar.nc"
    fi 
    
    # Processa com divdpm se a flag estiver ativada
    if [ "$PROCESSAR_CHUVA" -eq 1 ]; then
        echo -e "${GREEN}Processando o arquivo com a função divdpm${NC}"
        cdo -O divdpm "$output" "$tmp_dir/${prefixo}_divdpm.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo divdpm"
            return 1
        fi
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Processed with divdpm: Command: cdo -O divdpm \"$output\" \"$tmp_dir/${prefixo}_divdpm.nc\""$'\n'
        output="$tmp_dir/${prefixo}_divdpm.nc"
    fi
    
    if [[ $SINCRONIZAR_DATA -eq 1 && -n "$PERIODO" ]]; then
        echo -e "${GREEN}Sincronizando Data${NC}"
        cdo -O settaxis,"${ANO_I}-01-01,00:00:00,1month" "$output" "$tmp_dir/${prefixo}_sync.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo settaxis"
            return 1
        fi
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Synchronized date: Command: cdo -O settaxis,\"${ANO_I}-01-01,00:00:00,1month\" \"$output\" \"$tmp_dir/${prefixo}_sync.nc\""$'\n'
        output="$tmp_dir/${prefixo}_sync.nc"
    fi 
    
    if [ -n "$GRADE" ]; then
        echo -e "${GREEN}Cortando para a grade $GRADE!${NC}"
        cdo remapbil,"$GRADE" "$output" "$tmp_dir/${prefixo}_grade.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo remapbil"
            return 1
        fi
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Remapped to grade $GRADE: Command: cdo remapbil,\"$GRADE\" \"$output\" \"$tmp_dir/${prefixo}_grade.nc\""$'\n'
        output="$tmp_dir/${prefixo}_grade.nc"
    fi
    
    # Aplicar o corte espacial
    if [ -n "$CORTE_ESPACIAL" ]; then
        echo -e "${GREEN}Aplicando corte espacial: $CORTE_ESPACIAL${NC}"
        cdo -O ${CORTES_ESPACIAIS[$CORTE_ESPACIAL]} "$output" "$tmp_dir/${prefixo}_${CORTE_ESPACIAL}.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo ${CORTES_ESPACIAIS[$CORTE_ESPACIAL]}"
            return 1
        fi
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Applied spatial cut \"$CORTE_ESPACIAL\": Command: cdo -O ${CORTES_ESPACIAIS[$CORTE_ESPACIAL]} \"$output\" \"$tmp_dir/${prefixo}_${CORTE_ESPACIAL}.nc\""$'\n'
        output="$tmp_dir/${prefixo}_${CORTE_ESPACIAL}.nc"
    fi
    
    if [ -n "$PERIODO" ]; then
        echo -e "${GREEN}Cortando para o período $ANO_I-$ANO_F${NC}"
        cdo -selyear,"${ANO_I}/${ANO_F}" "$output" "$tmp_dir/${prefixo}_${ANO_I}-${ANO_F}.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo -selyear"
            return 1
        fi
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Selected year range $ANO_I-$ANO_F: Command: cdo -selyear,\"${ANO_I}/${ANO_F}\" \"$output\" \"$tmp_dir/${prefixo}_${ANO_I}-${ANO_F}.nc\""$'\n'
        output="$tmp_dir/${prefixo}_${ANO_I}-${ANO_F}.nc"
    fi
    
    if [ "$MASCARAR_OCEANO" -eq 1 ]; then
        echo -e "${GREEN}Mascarando o oceano (mantendo apenas dados terrestres)${NC}"
        cdo -f nc setctomiss,0 -gtc,0 -remapcon,"$output" -topo "$tmp_dir/seamask.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo para criar a máscara terrestre"
            return 1
        fi
        cdo mul "$output" "$tmp_dir/seamask.nc" "$tmp_dir/${prefixo}_land.nc"
        if [ $? -ne 0 ]; then
            echo "Erro ao executar cdo para aplicar a máscara terrestre"
            return 1
        fi
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Masked ocean (land only): Command: cdo mul with mask after setctomiss and remapcon"$'\n'
        output="$tmp_dir/${prefixo}_land.nc"
    fi
    
    # Extrai o nome base sem informações de processamento anteriores
    local nome=$(extrair_nome_base "$prefixo")
    
    # Adiciona apenas as informações relevantes conforme as opções
    [ -n "$PERIODO" ] && nome+="_${ANO_I}-${ANO_F}"
    
    # Se não estiver no modo de omissão, adiciona os outros sufixos
    if [ "$OMITIR_SUFIXOS" -eq 0 ]; then
        [ -n "$GRADE" ] && nome+="_${GRADE}"
        [ -n "$CORTE_ESPACIAL" ] && nome+="_${CORTE_ESPACIAL}"
        [ "$PROCESSAR_CHUVA" -eq 1 ] && nome+="_chuva"
        [ "$MASCARAR_OCEANO" -eq 1 ] && nome+="_land"
    fi
    
    local final_output_base="$nome"
    if [ "$OMITIR_SUFIXOS" -eq 1 ]; then
        echo -e "${GREEN}Modo de nomeação simplificada ativado${NC}"
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Simplified naming mode activated with -x option"$'\n'
    fi
    
    local final_output
    
    # Se a extensão de saída for 'nc'
    if [[ "$EXTENSAO_SAIDA" == "nc" ]]; then
        final_output="${final_output_base}.nc"
        mv "$output" "$final_output"
        output="$final_output"
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Renamed output to $final_output; Command: mv \"$output\" \"$final_output\""$'\n'
    fi
    
    # Se a extensão de saída for 'ctl'
    if [[ "$EXTENSAO_SAIDA" == "ctl" ]]; then
        final_output="${final_output_base}.ctl"
        local final_nc="$output"
        echo -e "${GREEN}Convertendo formato .nc para .ctl${NC}" 
        /geral/programas/converte_nc_bin/converte_dados_nc_to_bin.sh "$final_nc" "${final_output_base}" > converte.log
        output="$final_output"
        log_entries+="* $(date +"%Y-%m-%d %H:%M:%S") - Converted to CTL format: Command: /geral/programas/converte_nc_bin/converte_dados_nc_to_bin.sh \"$final_nc\" \"${final_output_base}\""$'\n'
    fi
    
    # Ao final do processamento, se a saída for CTL, anexa os logs
    if [[ "$EXTENSAO_SAIDA" == "ctl" ]]; then
        echo -e "${GREEN}Anexando logs ao arquivo de saída${NC}"
        echo -e "" >> "$output" # Adiciona uma linha em branco
        echo -e "$log_entries" >> "$output"
    fi
    
    echo -e "${GREEN}Arquivo de saída: $output${NC}"
    return 0
}

################################## PROCESSAMENTO PRINCIPAL ##################################

# if [ "$MODO_BATCH" -eq 1 ]; then
    echo -e "${GREEN}Iniciando processamento em lote de ${#ARQUIVOS_PARA_PROCESSAR[@]} arquivos${NC}"
    
    # Contador para acompanhamento
    contador=1
    total=${#ARQUIVOS_PARA_PROCESSAR[@]}
    
    # Processa cada arquivo na lista
    for arquivo in "${ARQUIVOS_PARA_PROCESSAR[@]}"; do
        echo -e "${YELLOW}Processando arquivo $contador de $total: $arquivo${NC}"

        BASE_NAME=$(basename "$arquivo")
        PREFIXO="${BASE_NAME%.*}"
        EXTENSAO="${BASE_NAME##*.}"

        if [[ "$EXTENSAO" != "nc" && "$EXTENSAO" != "ctl" ]]; then
            echo -e "${RED}Extensão $EXTENSAO inválida. Extensões permitidas: .nc e .ctl${NC}\n"
            continue # Skip to the next file
        fi
        
        # Chama a função de processamento para cada arquivo
        if ! processar_arquivo "$arquivo"; then
            echo -e "${RED}Erro ao processar o arquivo: $arquivo${NC}"
            # Continue mesmo com erro
        fi
        
        ((contador++))
    done
    
    echo -e "${GREEN}Processamento em lote concluído!${NC}"
# else
#     # Modo padrão: processa um único arquivo
#     processar_arquivo "$INPUT"
# fi

# --------------------------------------------------
# X está variando   Lon = -82.5 a -32.5   X = 1 a 21
# Y está variando   Lat = -56.25 a 16.25   Y = 1 a 30
# --------------------------------------------------

