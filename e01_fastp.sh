#!/bin/bash
#SBATCH --array=1-20%20         # Array job
#SBATCH --mem=100G               # Memory allocation per array job (adjust as needed)
#SBATCH --cpus-per-task=16       # CPUs per task

set -euo pipefail

#======================================Change this when working on new project========================
# load config file
OPTIONS=$(getopt -o "" -l config: -- "$@")

config_file="e99_config.json"
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        --config) config_file=$2; shift 2;;
        --) shift; break ;;
    esac
done

source ~/miniforge3/bin/activate
source activate biotools

# Load configuration variables
config_file="${config_file}"
output_dir=$(jq -r .output_file.path ${config_file})
sample_ids=${output_dir}/sample_ids.txt
read_1_extension=$(jq -r .sample_data.read_1_extension ${config_file})
read_2_extension=$(jq -r .sample_data.read_2_extension ${config_file})
#=====================================================================================================

NUM=$SLURM_ARRAY_TASK_ID
NAME=$(cat $sample_ids | head -$NUM | tail -1)

fastq_dir=${output_dir}/00_samples/${NAME}
fastp_result=${output_dir}/00_samples/${NAME}/00_fastp_results
fastp_result_all=${output_dir}/00_samples/01_fastp_all_results

mkdir -p ${fastp_result}
mkdir -p ${fastp_result_all}


fastp \
    -i ${fastq_dir}/${NAME}${read_1_extension} -I ${fastq_dir}/${NAME}${read_2_extension} \
    --detect_adapter_for_pe \
    -j ${fastp_result}/${NAME}_fastp.json \
    -h ${fastp_result}/${NAME}_fastp.html \
    -o ${fastp_result}/${NAME}_R1.fq -O ${fastp_result}/${NAME}_R2.fq

cp ${fastp_result}/${NAME}_fastp.json ${fastp_result_all}
