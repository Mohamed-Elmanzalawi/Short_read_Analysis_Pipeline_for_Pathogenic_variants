#!/bin/bash
set -euo pipefail

#### Script to run everything in one go.

show_help(){
cat <<EOF
SAPP: Short-read Analysis Pipeline for Pathogenic variants 

Usage: $0 [-h] [-g | --gpu] [-c | --cpu] [-l | --light_mode] [--config <config_file>]
Options:
  -h, --help  Show help message
  -g, --gpu             Run in GPU mode 
  -c, --cpu             Run in CPU mode 
  -l, --light_mode      Run in light mode that significantly reduces the size of the output files.
  --config              Specify the config file (default: e99_config.json)
EOF
exit 1
}

gpu=false
cpu=false
config_file="e99_config.json"
light_mode=false
date=$(date +'%Y-%m-%d %H:%M:%S')

OPTIONS=$(getopt -o hgcl -l help,gpu,cpu -- "$@")

eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -h | --help)  show_help ;;
        -g | --gpu)   
            gpu=True
            echo "${date}: Running SAPP in GPU mode"
            shift ;;
        -c | --cpu)   
            cpu=True
            echo "${date}: Running SAPP in CPU mode"
            shift ;;
        -l | --light_mode)  
            light_mode=True 
            echo "${date}: Running SAPP in light mode"
            shift ;;
        --config)     config_file=$2; shift 2 ;;
        --) shift; break ;;
    esac
done

# Alert to prevent both GPU and CPU from being set simultaneously
if [[ "$gpu" == "True" && "$cpu" == "True" ]]; then
    echo "${date}: Error: Cannot run in both GPU and CPU mode simultaneously."
    show_help
fi

# Alert If no mode for the script was set.
if [[ "$gpu" == "False" && "$cpu" == "False" ]]; then
    echo "${date}: Error: please select the script mode GPU (-g) or CPU (-c)."
    show_help
fi

source ~/miniforge3/bin/activate
source activate biotools

#======================================Change this when working on new project========================

output_dir=$(jq -r .output_file.path ${config_file})
num_of_samples=$(jq -r .sample_data.num_of_samples ${config_file})
starting_sample=$(jq -r .sample_data.starting_sample ${config_file})
fastp_array_job_limit=$(jq -r .parameters.fastp_array_job_limit ${config_file})
parabricks_array_job_limit=$(jq -r .parameters.parabricks_array_job_limit ${config_file})
haplotypecaller_array_job_limit=$(jq -r .parameters.haplotypecaller_array_job_limit ${config_file})
gpu_node=$(jq -r .parameters.gpu_node ${config_file})
cpu_node=$(jq -r .parameters.cpu_node ${config_file})

#=======================================Log file directories==========================================

fastp_log_dir=${output_dir}/98_logs/e01_fastp/
Parabricks_log_dir=${output_dir}/98_logs/e02_parabricks/
haplotypcaller_log_dir=${output_dir}/98_logs/e02.1_haplotypecaller/
GATK_log_dir=${output_dir}/98_logs/e03_genotyping/
ANNOVAR_log_dir=${output_dir}/98_logs/e04_annotation/
variant_per_sample_log_dir=${output_dir}/98_logs/e05_var_per_sample/
merging_log_dir=${output_dir}/98_logs/e06_merging/
sample_ids_log_dir=${output_dir}/98_logs/e00_sample_ids/

#==========================================Building sample id file====================================

## NOTE: This step can be skipped if you can generate a file with sample names in one column in a txt.file.
##       IMP: The file name should be: sample_ids.txt

### Example of sample_ids.txt:
###         E00014223
###         E00012545

sample_ids_job_id=$(sbatch --job-name=sample_ids --output=${sample_ids_log_dir}/%x_%j.out \
                        --error=${sample_ids_log_dir}/%x_%j.err --partition=${cpu_node} e00_get_samples.sh --config ${config_file} | awk '{print $4}') 

echo "${date}: Submitted batch job ${sample_ids_job_id} -- sample_ids"

#=============================================Fastp===================================================

#Running fastp
fastp_job_id=$(sbatch --job-name=fastp --array=${starting_sample}-${num_of_samples}%${fastp_array_job_limit} --output=${fastp_log_dir}/fastp_%A_%a.out \
                        --error=${fastp_log_dir}/fastp_%A_%a.err --partition=${cpu_node} --dependency=afterok:${sample_ids_job_id} e01_fastp.sh --config ${config_file} | awk '{print $4}')

echo "${date}: Submitted batch job ${fastp_job_id} -- fastp"

#=======================================Parabricks or GATK HaplotypeCaller=============================

# CPU or GPU selection mode
if [ "$gpu" == "True" ];then
#Running Parabricks using GPU nodes
job_name=parabricks

parabricks_job_id=$(sbatch --job-name=${job_name} --array=${starting_sample}-${num_of_samples}%${parabricks_array_job_limit} --output=${Parabricks_log_dir}/${job_name}_%A_%a.out \
                        --error=${Parabricks_log_dir}/${job_name}_%A_%a.err --partition=${gpu_node} --dependency=afterok:${fastp_job_id} e02_parabricks.sh --config ${config_file} --light_mode ${light_mode} | awk '{print $4}')

echo "${date}: Submitted batch job ${parabricks_job_id} -- ${job_name}"
fi

if [ "$cpu" == "True" ];then
#Running GATK haplotypcaller using CPU nodes
job_name=haplotype_caller

haplotype_caller_job_id=$(sbatch --job-name=${job_name} --array=${starting_sample}-${num_of_samples}%${haplotypecaller_array_job_limit} --output=${haplotypcaller_log_dir}/${job_name}_%A_%a.out \
                        --error=${haplotypcaller_log_dir}/${job_name}_%A_%a.err --partition=${cpu_node} --dependency=afterok:${fastp_job_id} e02.1_haplotypecaller.sh --config ${config_file} | awk '{print $4}')

echo "${date}: Submitted batch job ${haplotype_caller_job_id} -- ${job_name}"
fi

#=========================================GATK Genotyping=============================================

#Running GATK Genotyping
genotyping_job_id=$(sbatch --job-name=genotyping --output=${GATK_log_dir}/genotyping_%A_%a.out \
                        --error=${GATK_log_dir}/genotyping_%A_%a.err --partition=${cpu_node} --dependency=afterok:${haplotype_caller_job_id} e03_genotyping.sh --config ${config_file} | awk '{print $4}')

echo "${date}: Submitted batch job ${genotyping_job_id} -- genotyping"

#=============================================ANNOVAR=================================================

#Annotation using ANNOVAR
annotation_job_id=$(sbatch --job-name=annotation --output=${ANNOVAR_log_dir}/annotation_%A_%a.out \
                        --error=${ANNOVAR_log_dir}/annotation_%A_%a.err --partition=${cpu_node} --dependency=afterok:${genotyping_job_id} e04_Annotation.sh --config ${config_file} --light_mode ${light_mode} | awk '{print $4}')

echo "${date}: Submitted batch job ${annotation_job_id} -- annotation"

#======================================Varaints file per sample=======================================

#Generating a file for each sample
variant_per_sample_job_id=$(sbatch --job-name=variant_per_sample --output=${variant_per_sample_log_dir}/variant_per_sample_%A_%a.out \
                        --error=${variant_per_sample_log_dir}/variant_per_sample_%A_%a.err --partition=${cpu_node} --dependency=afterok:${annotation_job_id} e05_var_per_sample.sh --config ${config_file} | awk '{print $4}')


echo "${date}: Submitted batch job ${variant_per_sample_job_id} -- variant_per_sample"

#==========================Create final VCF file with all sample after filtering======================

#Merging all the vcf files
merging_job_id=$(sbatch --job-name=merging --output=${merging_log_dir}/merging_%A_%a.out \
                        --error=${merging_log_dir}/merging_%A_%a.err --partition=${cpu_node} --dependency=afterok:${variant_per_sample_job_id} e06_merge_var.sh  --config ${config_file} | awk '{print $4}')

echo "${date}: Submitted batch job ${merging_job_id} -- merging"