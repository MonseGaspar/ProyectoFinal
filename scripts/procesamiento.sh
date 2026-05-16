#!/bin/bash
# Pre-procesamiento de secuencias de genomas completos obtenidos de DRYAD
# Monserrat Gaspar Argote
# Creado: 1 abril 2026
# Actualización: 7 mayo 2026

### 1. DEFINIR VARIABLES#

PROYECTO="$HOME/ProyectoFinal"
RAW="$PROYECTO/datos/raw"
CONTENEDORES="$PROYECTO/programas_contenedores"
RESULTADOS="$PROYECTO/resultados"

FASTQC_SIF="$CONTENEDORES/fastqc.sif"
FASTP_SIF="$CONTENEDORES/fastp.sif"

# Telegram
TELEGRAM_TOKEN="Aqui coloca tu TOKEN "
TELEGRAM_CHAT_ID="6266082248"

#### 2. configrar telegram ##

enviar_telegram() {
    local MENSAJE="$1"

    [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0

    if ! command -v curl >/dev/null 2>&1; then
        echo "Aviso: curl no está instalado; no se enviará mensaje a Telegram."
        return 0
    fi

    RESPUESTA=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${MENSAJE}")

    echo "Respuesta Telegram: $RESPUESTA"
}

listar_omitidas() {
    local TEXTO=""
    for i in "${!SKIPPED_SAMPLES[@]}"; do
        TEXTO+=$'\n'"- ${SKIPPED_SAMPLES[$i]}: ${SKIPPED_REASONS[$i]}"
    done
    printf '%s' "$TEXTO"
}

validar_fastq() {
    local FILE="$1"

    gzip -t "$FILE" 2>/dev/null || {
        echo "Archivo .gz corrupto: $FILE"
        return 1
    }

    zcat "$FILE" | awk '
        NR % 4 == 1 && $0 !~ /^@/ {exit 1}
        NR % 4 == 2 {seq_len = length($0)}
        NR % 4 == 3 && $0 !~ /^\+/ {exit 1}
        NR % 4 == 0 && length($0) != seq_len {exit 1}
        END {if (NR % 4 != 0) exit 1}
    ' >/dev/null || {
        echo "Archivo FASTQ inválido: $FILE"
        return 1
    }
}

error_script() {
    local LINEA="$1"
    enviar_telegram "Falla en el script de preprocesamiento. Línea: $LINEA"
}
trap 'error_script $LINENO' ERR

### 3. PREPARAR CARPETAS DE TRABAJO ###

mkdir -p "$CONTENEDORES" \
         "$RESULTADOS/01_calidad_inicial" \
         "$RESULTADOS/02_lecturas_filtradas" \
         "$RESULTADOS/03_calidad_post_filtrado"

### 4. LIMPIAR RESULTADOS DE INTENTOS PREVIOS ###

rm -f "$RESULTADOS"/01_calidad_inicial/*
rm -f "$RESULTADOS"/02_lecturas_filtradas/*
rm -f "$RESULTADOS"/03_calidad_post_filtrado/*

### 5. DESCARGAR CONTENEDORES ###

[[ -f "$FASTQC_SIF" ]] || apptainer pull "$FASTQC_SIF" docker://biocontainers/fastqc:v0.11.9_cv8
[[ -f "$FASTP_SIF"  ]] || apptainer pull "$FASTP_SIF"  docker://biocontainers/fastp:v0.20.1_cv1

### 6. VERIFICAR QUE EXISTAN ARCHIVOS FASTQ ###

R1_FILES=("$RAW"/*_R1_001.fastq.gz)

if (( ${#R1_FILES[@]} == 0 )); then
    MSG=" no se encontraron archivos R1 en $RAW"
    echo "$MSG"
    enviar_telegram "$MSG"
    exit 1
fi

### 7.Validación, aqui se identifica las muestras con errores y las que son validas y continuaran en el proceso ###

VALID_R1=()
VALID_R2=()
VALID_RAW_FILES=()
VALID_SAMPLES=()

SKIPPED_SAMPLES=()
SKIPPED_REASONS=()

for R1 in "${R1_FILES[@]}"; do
    MUESTRA="$(basename "$R1" _R1_001.fastq.gz)"
    R2="$RAW/${MUESTRA}_R2_001.fastq.gz"

    echo "Revisando muestra: $MUESTRA"

    if [[ ! -f "$R2" ]]; then
        SKIPPED_SAMPLES+=("$MUESTRA")
        SKIPPED_REASONS+=("Falta R2")
        continue
    fi

    if ! validar_fastq "$R1"; then
        SKIPPED_SAMPLES+=("$MUESTRA")
        SKIPPED_REASONS+=("R1 corrupto o mal formado")
        continue
    fi

    if ! validar_fastq "$R2"; then
        SKIPPED_SAMPLES+=("$MUESTRA")
        SKIPPED_REASONS+=("R2 corrupto o mal formado")
        continue
    fi

    VALID_R1+=("$R1")
    VALID_R2+=("$R2")
    VALID_RAW_FILES+=("$R1" "$R2")
    VALID_SAMPLES+=("$MUESTRA")
done

if (( ${#VALID_SAMPLES[@]} == 0 )); then
    MSG="Validación terminada: no hay muestras válidas para procesar."
    echo "$MSG"
    enviar_telegram "$MSG"
    exit 1
fi

MENSAJE_VALIDACION="Validación completada.
Muestras válidas: ${#VALID_SAMPLES[@]}
Muestras omitidas: ${#SKIPPED_SAMPLES[@]}$(listar_omitidas)"

echo "Enviando aviso de validación a Telegram..."
enviar_telegram "$MENSAJE_VALIDACION"

### 8. Revision de las lecturas crudas con FASTQC ###

apptainer exec --bind "$PROYECTO:$PROYECTO" \
"$FASTQC_SIF" \
fastqc "${VALID_RAW_FILES[@]}" \
-o "$RESULTADOS/01_calidad_inicial"

echo "Enviando aviso de FastQC inicial a Telegram..."
enviar_telegram "FastQC inicial terminado.
Archivos analizados: ${#VALID_RAW_FILES[@]}"

### 9. Filtrado y trimming con fastp ###

for i in "${!VALID_R1[@]}"; do
    R1="${VALID_R1[$i]}"
    R2="${VALID_R2[$i]}"
    MUESTRA="${VALID_SAMPLES[$i]}"

    echo "Procesando muestra válida: $MUESTRA"

    apptainer exec --bind "$PROYECTO:$PROYECTO" \
    "$FASTP_SIF" \
    fastp \
    -i "$R1" \
    -I "$R2" \
    -o "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_R1_trimmed.fastq.gz" \
    -O "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_R2_trimmed.fastq.gz" \
    --detect_adapter_for_pe \
    --qualified_quality_phred 20 \
    --length_required 50 \
    --html "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_fastp.html" \
    --json "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_fastp.json"
done

echo "Enviando aviso de fastp a Telegram..."
enviar_telegram "Filtrado y trimming listos.
Muestras procesadas: ${#VALID_SAMPLES[@]}"

### 10.Con FASTQC revision de las lecturas ya filtradas  ###

TRIMMED_FILES=("$RESULTADOS"/02_lecturas_filtradas/*_trimmed.fastq.gz)

if (( ${#TRIMMED_FILES[@]} > 0 )); then
    apptainer exec --bind "$PROYECTO:$PROYECTO" \
    "$FASTQC_SIF" \
    fastqc "${TRIMMED_FILES[@]}" \
    -o "$RESULTADOS/03_calidad_post_filtrado"

    echo "Enviando aviso de FastQC final a Telegram..."
    enviar_telegram " FastQC final terminado.
Archivos filtrados evaluados: ${#TRIMMED_FILES[@]}"
fi

### 11.Resultdos se manda el resumen final a telegram ###

echo "========================================"
echo "Resumen final del preprocesamiento"
echo "Muestras válidas analizadas: ${#VALID_SAMPLES[@]}"
printf '  - %s\n' "${VALID_SAMPLES[@]}"
echo "Muestras omitidas: ${#SKIPPED_SAMPLES[@]}"
for i in "${!SKIPPED_SAMPLES[@]}"; do
    echo "  - ${SKIPPED_SAMPLES[$i]} -> ${SKIPPED_REASONS[$i]}"
done
echo "========================================"
echo "Preprocesamiento completado."

MENSAJE_FINAL="Preprocesamiento completado.
Muestras válidas: ${#VALID_SAMPLES[@]}
Muestras omitidas: ${#SKIPPED_SAMPLES[@]}$(listar_omitidas)"

echo "Enviando aviso final a Telegram..."
enviar_telegram "$MENSAJE_FINAL"
