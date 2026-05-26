
#!/bin/bash

# Pre-procesamiento de secuencias de genomas completos obtenidos de DRYAD
# Monserrat Gaspar Argote
# Creado: 1 abril 2026
# Actualizacion: 7 mayo 2026

### 1. DEFINIR RUTAS ###

PROYECTO="$HOME/ProyectoFinal"
RAW="$PROYECTO/datos/raw"
CONTENEDORES="$PROYECTO/programas_contenedores"
RESULTADOS="$PROYECTO/resultados"

FASTQC_SIF="$CONTENEDORES/fastqc.sif"
FASTP_SIF="$CONTENEDORES/fastp.sif"

# Configurar el Telegram :)
TELEGRAM_TOKEN="poner el token "
TELEGRAM_CHAT_ID="6266082248"


### 2. FUNCION PARA ENVIAR MENSAJES A TELEGRAM ###


enviar_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${MENSAJE}"
}
## prueba mandando un mensaje a mi telegram
# Prueba mandando un mensaje a Telegram
MENSAJE="Comenzando a trabajar"
enviar_telegram

### 3. FUNCION PARA REVISAR ARCHIVOS en FASTA,
# aqui solo estoy dando instrucciones (validar_fastq) aún no esta validando los archivos

validar_fastq() {
    ARCHIVO="$1"

    # Gzip verifica que el archivo .gz este correctamente comprimido con -t 
    if ! gzip -t "$ARCHIVO"; then
        echo "Archivo .gz corrupto: $ARCHIVO"
        return 1
    fi

    # Luego con zcat revisamos el archivo sin descomprimirlo, con awk checamos que elfasta tenga la estructura correcta
    # es decir:registros de cuatro lineas, donde la primera linea empieza con @, 
    #la tercera empieza con +, y el numero total de lineas debe ser multiplo de cuatro.
    if ! zcat "$ARCHIVO" | awk '
        NR % 4 == 1 && $0 !~ /^@/ {exit 1}
        NR % 4 == 3 && $0 !~ /^\+/ {exit 1}
        END {if (NR % 4 != 0) exit 1}
    '; then
    #si no cumple entonces manda aviso de cual es el archivo que no funcionó
        echo "Archivo invalido: $ARCHIVO"
        return 1
    fi

    return 0
}


### 4. CREAR CARPETAS DE TRABAJO ###

mkdir -p "$CONTENEDORES"                         #aqui van los contenedores
mkdir -p "$RESULTADOS/01_calidad_inicial"        #resultados de FastQC antes del filtrado
mkdir -p "$RESULTADOS/02_lecturas_filtradas"     #archivos generados por fastp 
mkdir -p "$RESULTADOS/03_calidad_post_filtrado"  #mis resultados de FastQC despues del filtrado


### 5. Eliminar intentos fallidos
#rm con * borra todos los archivos previos, -f no pregunta entonces no se detiene el script
rm -f "$RESULTADOS/01_calidad_inicial"/*
rm -f "$RESULTADOS/02_lecturas_filtradas"/*
rm -f "$RESULTADOS/03_calidad_post_filtrado"/*


### 6. DESCARGAR CONTENEDORES
#si no existen las imágenes las descarga

if [[ ! -f "$FASTQC_SIF" ]]; then
    apptainer pull "$FASTQC_SIF" docker://biocontainers/fastqc:v0.11.9_cv8
fi

if [[ ! -f "$FASTP_SIF" ]]; then
    apptainer pull "$FASTP_SIF" docker://biocontainers/fastp:v0.20.1_cv1
fi

### 7. BUSCAR ARCHIVOS R1 ###
#busca todos los archivos que terminen asi _R1_001.fastq.gz

R1_FILES=("$RAW"/*_R1_001.fastq.gz)

# Si no se hay archivos R1, se manda un aviso y se detiene el script
if (( ${#R1_FILES[@]} == 0 )); then
    MENSAJE="No se encontraron archivos R1 en $RAW"
    echo "$MENSAJE"
    enviar_telegram
    exit 1
fi
R2_FILES=("$RAW"/*_R2_001.fastq.gz)

# Si no se hay archivos R2, se manda un aviso y se detiene el script
if (( ${#R2_FILES[@]} == 0 )); then
    MENSAJE="No se encontraron archivos R2 en $RAW"
    echo "$MENSAJE"
    enviar_telegram
    exit 1
fi


### 8. VALIDAR MUESTRAS ###
#hacer listas
validos_R1=()    #aqui se guardan los archivos R1 que si sirven
validos_R2=()    #aqui se guardan los archivos R2 que si sirven
muestras_validas=() #aqui se guardan los nombres de las muestras que si se van a procesar
muestras_omitidas=()   #aqui se guardan las muestras que no se van a procesar y la razon

#Para cada archivo R1 encontrado en la lista R1_FILES
for R1 in "${R1_FILES[@]}"; do
#identifica el codigo de R1 y busca su par r2
    MUESTRA="$(basename "$R1" _R1_001.fastq.gz)"
    R2="$RAW/${MUESTRA}_R2_001.fastq.gz"

    echo "Revisando muestra: $MUESTRA"
#Si no existe el archivo R2, la marca como "Falta R2" y pasa a la siguiente muestra.
    if [[ ! -f "$R2" ]]; then
        muestras_omitidas+=("$MUESTRA: Falta R2")
        continue
    fi
# Se aplica la funcion validar_fastq al archivo R1 y R2
# Si R1 o R2 estaN corruptos o no tienen estructura basica se omite
    if ! validar_fastq "$R1"; then
        muestras_omitidas+=("$MUESTRA: R1 con mal formato")
        continue
    fi

    if ! validar_fastq "$R2"; then
        muestras_omitidas+=("$MUESTRA: R2 con mal formato")
        continue
    fi

    # Si la muestra paso todas las revisiones..... 
    validos_R1+=("$R1")          # Guarda el archivo R1 valido
    validos_R2+=("$R2")          # Guarda el archivo R2 valido
    muestras_validas+=("$MUESTRA")  # Guarda el nombre de la muestra valida

done


#Si hubo muestras validas, el script avisa cuantas muestras pasaron y cuantas fueron omitidas.
#Ese resumen se imprime en la terminal y tambien se manda a Telegram

MENSAJE="Validacion completada.
Muestras validas: ${#muestras_validas[@]}
Muestras omitidas: ${#muestras_omitidas[@]}"

echo "$MENSAJE"
enviar_telegram


### 9. FASTQC DE LECTURAS CRUDAS ###
#se hcae una sola lista de todos los archivos validos
archivos_crudos_validos=("${validos_R1[@]}" "${validos_R2[@]}")
#ejecuta FASTQC con apptainer y la imagen creada y los manda a 01 calidad inicial
apptainer exec --bind "$PROYECTO:$PROYECTO" \
"$FASTQC_SIF" \
fastqc "${archivos_crudos_validos[@]}" \
-o "$RESULTADOS/01_calidad_inicial"

MENSAJE="FastQC 01 terminado.
Archivos analizados: ${#archivos_crudos_validos[@]}"
enviar_telegram


### 10. FILTRADO Y TRIMMING CON FASTP # toma cada par R1 y R2, les quita adaptadores 
#filtra lecturas de baja calidad y genera archivos nuevos ya filtrados

#primero los archivos validos los empareja con R2 y comienza a procesar 

for i in "${!validos_R1[@]}"; do

    R1="${validos_R1[$i]}"
    R2="${validos_R2[$i]}"
    MUESTRA="${muestras_validas[$i]}"
# y avisa en la terminal que muestra esta trabajando
    echo "Procesando muestra valida: $MUESTRA"
#ejecuta fastp con apptainer y se indica que archivos procesar la i minuscula es para R1 y la I mayuscula R2
    #detectar adaptadores
   # Q20 como umbral minimo de calidad
    #largo de las lecturas,descarta lecturas menores a 50pb
    apptainer exec --bind "$PROYECTO:$PROYECTO" \
    "$FASTP_SIF" \
    fastp \
    -i "$R1" \
    -I "$R2" \
    -o "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_R1_filtrado.fastq.gz" \
    -O "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_R2_filtrado.fastq.gz" \
    --detect_adapter_for_pe \
    --qualified_quality_phred 20 \
    --length_required 50 \
    --html "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_fastp.html" \
    --json "$RESULTADOS/02_lecturas_filtradas/${MUESTRA}_fastp.json"

done

MENSAJE="Filtrado y trimming listos.
Muestras procesadas: ${#muestras_validas[@]}"
enviar_telegram



### 11. FASTQC DE LECTURAS FILTRADAS ###

# Busca los archivos filtrados generados por fastp
archivos_filtrados=("$RESULTADOS"/02_lecturas_filtradas/*_filtrado.fastq.gz)

# Si no se encontraron archivos filtrados, se manda un aviso y se detiene el script
if (( ${#archivos_filtrados[@]} == 0 )); then
    MENSAJE="No se encontraron archivos filtrados para FastQC final."
    echo "$MENSAJE"
    enviar_telegram
    exit 1
fi
# Se ejecuta FastQC con las lecturas filtradas
apptainer exec --bind "$PROYECTO:$PROYECTO" \
"$FASTQC_SIF" \
fastqc "${archivos_filtrados[@]}" \
-o "$RESULTADOS/03_calidad_post_filtrado"

# enviar aviso por Telegram
MENSAJE="FastQC final terminado.
Archivos filtrados evaluados: ${#archivos_filtrados[@]}"
enviar_telegram


### 12. RESUMEN FINAL ###

echo ""
echo "Preprocesamiento completado."
echo "Muestras revisadas: ${#R1_FILES[@]}"
echo "Muestras validas analizadas: ${#muestras_validas[@]}"
echo "Muestras no validas y omitidas: ${#muestras_omitidas[@]}"

echo ""
echo "Muestras omitidas:"
printf '  - %s\n' "${muestras_omitidas[@]}"

MENSAJE="Preprocesamiento completado.
Muestras revisadas: ${#R1_FILES[@]}
Muestras validas analizadas: ${#muestras_validas[@]}
Muestras no validas y omitidas: ${#muestras_omitidas[@]}

Muestras omitidas:
$(printf '  - %s\n' "${muestras_omitidas[@]}")"

enviar_telegram

   

  

