
# 1.Título del proyecto
Pre-procesamiento de secuencias de genomas completos de E.coli obtenidos de DRYAD

# 2. Introducción
Debido a que todavía no cuento con secuencias genómicas para desarrollar mi proyecto de doctorado, 
para el proyecto del curso utilicé lecturas genómicas de *E. coli* descargadas de Dryad con el fin de diseñar, probar y documentar 
un script reproducible que posteriormente pueda usar para mi proyecto doctoral  filogenómica del complejo *Psittacara* de México y
 Centroamérica.

El análisis filogenómico de datos genómicos requiere una etapa inicial de preprocesamiento antes de realizar ensamblado, 
alineamiento o análisis posteriores. Por ello, en este proyecto desarrollé un pipeline en Bash para verificar que los archivos 
FASTQ obtenidos después de la secuenciación no tengan errores de integridad o formato, identificar muestras problemáticas, 
evaluar la calidad de las lecturas, realizar la limpieza de adaptadores y bases de baja calidad.

## 3. Objetivo
Este script es un pipeline reproducible para realizar el preprocesamiento de lecturas genómicas 

Verifica que los archivos FASTQ no tengan errores

Identifica muestras que deben omitirse por problemas de integridad o formato

Evalúa la calidad de las lecturas

Elimina adaptadores y filtrado por calidad

Envía mensajes automáticos a mi Telegram para saber cuándo se terminó cada proceso y notifica si hay alguna muestra que no se procesó 

## Descripción general del flujo de trabajo
1. Variables: Primero se definen las rutas del proyecto, las carpetas de trabajo, en donde se guardan resultados y los contenedores
2. Configuracion de Telegram
3. Carpetas: Luego se preparan las carpetas para guardar contenedores, datos, resultados lecturas filtradas 
4. Limpieza: Estuve probando varias veces el script, por lo tanto, en esta sección se borran archivos de corridas anteriores 
para que el flujo inicie desde cero
5. Contenedores: Se descarga las imágenes del software que usaré en Apptainer, 
usé un condicional si no existen se descarga FASTQC y fastp.
6. Existencia de archivos FASTQ: Se revisa que existan los archivos en la carpeta
7. Validación de FASTQ: se verifica que los archivos tengan la estructura correcta, 
que haya archivos en par (R1 y R2). Las muestras que no cumplan con esto se omiten del proceso y se registran mandando mensaje a telegram.
8. Revisión de la calidad de las lecturas: Ejecuta FASTQC con las muestras que pasaron la validación
9. Limpieza con fastp: en pares R1/R2 se detectan adaptadores, elimina bases de baja calidad y lecturas muy cortas.
10. Revisión de lecturas filtradas: Con FASTQC se revisan nuevamente la calidad de las lecturas
11. Resultados: Se reporta el número de muestras válidas y omitidas asi como sus claves
12. Notificación a telegram: el script manda avisos al terminar los procesos de FASTQC, fastp y el resumen final   

## 5. Estructura del repositorio
 mgaspar@biomolecular:~/ProyectoFinal$ tree

├── datos

│   └── raw

├── programas_contenedores

├── README.md

├── resultados

│   ├── 01_calidad_inicial

│   ├── 02_lecturas_filtradas

│   └── 03_calidad_post_filtrado

└── scripts
    
    └── procesamiento.sh

##6. Requisitos de software

Bash 

Apptainer 

FastQC 0.11.9 

fastp 0.20.1 

## 7. Reproducibilidad
Este script es reproducible porque usa Apptainer, lo que facilita no tener que estar descargando FASTQC y 
fastp manualmente y además hay una sección (sección 4) en la que se descargan los contenedores automáticamente.

## 8. El script se puede ejecutar así:

Primero hay que clonar el repositorio:

```bash
git clone https://github.com/MonseGaspar/ProyectoFinal.git
entrar a la carpeta del proyecto: 
cd ProyectoFinal
Entrar a la carpeta scripts: 
cd scripts
Luego dar permisos de ejecución al script: 
chmod 740 preprocesamiento.sh
Para ejecutar el pipeline: 
./preprocesamiento.sh

## 9. Entradas y salidas
Entrada: archivos FASTQ en carpeta raw dentro de datos
Salidas
Revisión de calidad inicial
En la carpeta 01_calidad_inicial se generan:los  archivo fastqc.html y fastqc.zip
Lecturas filtradas 
En la carpeta 02_lecturas_filtradas se genera: R1 y R2_trimmed.fastq.gz,, fastp.html y fastp.json
Revisión de calidad posterior al trimming
En carpeta 03_calidad_post_filtrado se genera los archivos fastq.gz y fasqc.zip

## 10. Información del sistema
Este proyecto fue probado en el siguiente equipo:

- Tipo de equipo: servidor
- Sistema operativo: Ubuntu 22.04.5 LTS
- CPU: QEMU Virtual CPU version 2.5
- Núcleos / hilos: 8 / 8
- RAM: 15 GiB
- GPU: no detectada 
- Almacenamiento: disco de 500 GB
Tiempo de ejecución 24 minutos 

##11. Autoría
Monserrat Gaspar Argote 

