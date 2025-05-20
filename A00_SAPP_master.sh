#!/bin/bash
set -euo pipefail

#### Script to run everything in one go.

show_help(){
cat <<EOF
SAPP: Short-read Analysis Pipeline for Pathogenic variants 

Usage: $0 [-h] [-g | --gpu] [-c | --cpu] [--config <config_file>]
Options:
  -h, --help  Show help message
  -g, --gpu   Run in GPU mode 
  -c, --cpu   Run in CPU mode 
  --config    Specify the config file (default: e99_config.json)
EOF
exit 1
}

gpu=false
cpu=false
config_file="e99_config.json"

OPTIONS=$(getopt -o hgc -l help,gpu,cpu -- "$@")

eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -h | --help)  show_help ;;
        -g | --gpu)   gpu=true; shift ;;
        -c | --cpu)   cpu=true; shift ;;
        --config)     config_file=$2; shift 2 ;;
        --) shift; break ;;
    esac
done

# Alert to prevent both GPU and CPU from being set simultaneously
if [[ "$gpu" == "true" && "$cpu" == "true" ]]; then
    echo "Error: Cannot run in both GPU and CPU mode simultaneously."
    show_help
fi

# Alert If no mode for the script was set.
if [[ "$gpu" == "false" && "$cpu" == "false" ]]; then
    echo "Error: please select the script mode GPU (-g) or CPU (-c)."
    show_help
fi

source ~/miniforge3/bin/activate
source activate biotools

#======================================Change this when working on new project========================
output_dir=$(jq -r .output_file.path ${config_file})
num_of_samples=$(jq -r .sample_data.num_of_samples ${config_file})
starting_sample=$(jq -r .sample_data.starting_sample ${config_file})
fastp_array_job_limit=$(jq -r .parameters.fastp_array_job_limit ${config_file})
parabricks_array_job_limit=$(jq -r .parameters.fastp_array_job_limit ${config_file})
gpu_node=$(jq -r .parameters.gpu_node ${config_file})
cpu_node=$(jq -r .parameters.cpu_node ${config_file})
#=====================================================================================================

# Creating directory for log files
fastp_log_dir=${output_dir}/98_logs/e01_fastp/
Parabricks_log_dir=${output_dir}/98_logs/e02_parabricks/
haplotypcaller_log_dir=${output_dir}/98_logs/e02.1_haplotypecaller/
GATK_log_dir=${output_dir}/98_logs/e03_genotyping/
ANNOVAR_log_dir=${output_dir}/98_logs/e04_annotation/
variant_per_sample_log_dir=${output_dir}/98_logs/e05_var_per_sample/
merging_log_dir=${output_dir}/98_logs/e06_merging/

for dir in ${fastp_log_dir} ${GATK_log_dir} ${ANNOVAR_log_dir} ${variant_per_sample_log_dir} ${merging_log_dir} 
do
    mkdir -p ${dir}
done

#Getting sample id file.
## NOTE: This step can be skipped if you can generate a file with sample names in one column in a txt.file.
##       IMP: The file name should be: sample_ids.txt

### Example of sample_ids.txt:
###         E00014223
###         E00012545

sample_ids_log_dir=${output_dir}/98_logs/e00_sample_ids/
mkdir -p ${sample_ids_log_dir}

sample_ids_job_id=$(sbatch --job-name=sample_ids --output=${sample_ids_log_dir}/%x_%j.out \
                        --error=${sample_ids_log_dir}/%x_%j.err --partition=${cpu_node} e00_get_samples.sh --config ${config_file} | awk '{print $4}') 

echo "Submitted batch job ${sample_ids_job_id} -- sample_ids"


#Running fastp
fastp_job_id=$(sbatch --job-name=fastp --array=${starting_sample}-${num_of_samples}%${fastp_array_job_limit} --output=${fastp_log_dir}/fastp_%A_%a.out \
                        --error=${fastp_log_dir}/fastp_%A_%a.err --partition=${cpu_node} --dependency=afterok:${sample_ids_job_id} e01_fastp.sh --config ${config_file} | awk '{print $4}')

echo "Submitted batch job ${fastp_job_id} -- fastp"

# CPU or GPU selection mode
if [ "$gpu" == "true" ];then
#Running Parabricks using GPU nodes
job_name=parabricks
mkdir -p ${Parabricks_log_dir}
echo "Running script in GPU mode"
qsub -N ${job_name} -t 1:${num_of_samples}:1 -tc ${parabricks_array_job_limit} -o ${Parabricks_log_dir} -e ${Parabricks_log_dir} -q ${gpu_node} -hold_jid fastp e02_parabricks.sh
fi

if [ "$cpu" == "true" ];then
#Running GATK haplotypcaller using CPU nodes
job_name=haplotype_caller
mkdir -p ${haplotypcaller_log_dir}
echo "Running script in CPU mode"
haplotype_caller_job_id=$(sbatch --job-name=${job_name} --array=${starting_sample}-${num_of_samples}%${fastp_array_job_limit} --output=${haplotypcaller_log_dir}/${job_name}_%A_%a.out \
                        --error=${haplotypcaller_log_dir}/${job_name}_%A_%a.err --partition=${cpu_node} --dependency=afterok:${fastp_job_id} e02.1_haplotypecaller.sh --config ${config_file} | awk '{print $4}')

echo "Submitted batch job ${haplotype_caller_job_id} -- ${job_name}"
fi



#Running GATK Genotyping
genotyping_job_id=$(sbatch --job-name=genotyping --output=${GATK_log_dir}/genotyping_%A_%a.out \
                        --error=${GATK_log_dir}/genotyping_%A_%a.err --partition=${cpu_node} --dependency=afterok:${fastp_job_id} e03_genotyping.sh --config ${config_file} | awk '{print $4}')

echo "Submitted batch job ${genotyping_job_id} -- genotyping"


#Annotation using ANNOVAR
annotation_job_id=$(sbatch --job-name=annotation --output=${ANNOVAR_log_dir}/annotation_%A_%a.out \
                        --error=${ANNOVAR_log_dir}/annotation_%A_%a.err e04_Annotation.sh | awk '{print $4}')

echo "Submitted batch job ${annotation_job_id} -- annotation"

#Generating a file for each sample
variant_per_sample_job_id=$(sbatch --job-name=variant_per_sample --array=${starting_sample}-${num_of_samples} --output=${variant_per_sample_log_dir}/variant_per_sample_%A_%a.out \
                        --error=${variant_per_sample_log_dir}/variant_per_sample_%A_%a.err --partition=${cpu_node} --dependency=afterok:${annotation_job_id} e05_var_per_sample.sh --config ${config_file} | awk '{print $4}')

echo "Submitted batch job ${variant_per_sample_job_id} -- variant_per_sample"

#Merging all the vcf files
merging_job_id=$(sbatch --job-name=merging --output=${merging_log_dir}/merging_%A_%a.out \
                        --error=${merging_log_dir}/merging_%A_%a.err --partition=${cpu_node} --dependency=afterok:${variant_per_sample_job_id} e06_merge_var.sh  --config ${config_file} | awk '{print $4}')

echo "Submitted batch job ${merging_job_id} -- merging"