#!/bin/bash
#SBATCH --array=1-2             # Array job
#SBATCH --time=48:00:00         # Time limit (adjust as needed)
#SBATCH --mem=100G              # Memory allocation per task (adjust as needed)
#SBATCH --cpus-per-task=16      # CPUs per task

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

source ~/miniconda3/bin/activate
source activate biotools

# Load the configuration file
output_dir=$(jq -r .output_file.path ${config_file})
annovar_file=${output_dir}/04_annotation/analysis-ready.hg38_multianno.txt
sample_ids=${output_dir}/sample_ids.txt
pathogenicity_prediction=$(jq -r .parameters.Pathogenicity_Prediction ${config_file})
Pathogenicity_conditions=$(jq -r .parameters.Pathogenicity_conditions ${config_file})
#=====================================================================================================

NUM=$SGE_TASK_ID
NAME=$(cat $sample_ids | head -$NUM | tail -1)

var_per_sample_dir=${output_dir}/05_var_per_sample
sample_dir=${var_per_sample_dir}/$NAME
mkdir -p ${var_per_sample_dir} 
mkdir -p ${sample_dir} 
python e05.1_var_per_sample.py $annovar_file $var_per_sample_dir $NAME $pathogenicity_prediction $Pathogenicity_conditions