#!/bin/bash
#$ -cwd
#$ -q all.q@gpu1
#$ -t 1:235:1
#$ -tc 2
set -euo pipefail

#======================================Change this when working on new project========================
# load config file
OPTIONS=$(getopt -o "" -l light_mode,config: -- "$@")

config_file="e99_config.json"
light_mode=false
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        --config) config_file=$2; shift 2;;
        --light_mode)  light_mode=$2; shift2 ;;
        --) shift; break ;;
    esac
done

source ~/miniforge3/bin/activate
source activate biotools

output_dir=$(jq -r .output_file.path e99_config.json)
parabricks_sif=$(jq -r .singularity_containers.parabricks e99_config.json)
Ref_dir=$(jq -r .reference_genome.dir e99_config.json)
Ref=$(jq -r .reference_genome.fasta_file e99_config.json)
temp_dir=$(jq -r .miscellaneous_files.temp_dir e99_config.json)
sample_ids=${output_dir}/sample_ids.txt
#=====================================================================================================

NUM=$SGE_TASK_ID
NAME=$(cat $sample_ids | head -$NUM | tail -1)

fastp_result=${output_dir}/00_samples/${NAME}/00_fastp
parabricks_output=${output_dir}/00_samples/${NAME}/02_GPU_preproc_results


for dir in ${temp_dir} ${parabricks_output}/01_bam_after_marks/ ${parabricks_output}/02_marksduplicate_metrics/ \
${parabricks_output}/03_BQSR_report/ ${parabricks_output}/04_haplo_htvc_results/ ${output_dir}/01_gvcf/
do
    mkdir -p ${dir} 
done


if [[ ${light_mode} == "true" ]]; then

singularity exec --nv -B /mnt:/mnt ${parabricks_sif} \
    pbrun germline \
    --ref ${Ref} \
    --in-fq ${fastp_result}/${NAME}_R1.fq ${fastp_result}/${NAME}_R2.fq "@RG\tID:${NAME}\tPU:${NAME}\tSM:${NAME}\tPL:illumina\tLB:${NAME}" \
    --tmp-dir ${temp_dir} \
    --num-cpu-threads-per-stage 16 \
    --bwa-cpu-thread-pool 16 \
    --gpusort \
    --gpuwrite \
    --knownSites ${Ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf \
    --knownSites ${Ref_dir}/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz \
    --gvcf \
    --out-bam ${parabricks_output}/01_bam_after_marks/${NAME}.germline_dedup.bam \
    --out-variants ${output_dir}/01_gvcf/${NAME}.germline.g.vcf

else 

singularity exec --nv -B /mnt:/mnt ${pa rabricks_sif} \
    pbrun germline \
    --ref ${Ref} \
    --in-fq ${fastp_result}/${NAME}_R1.fq ${fastp_result}/${NAME}_R2.fq "@RG\tID:${NAME}\tPU:${NAME}\tSM:${NAME}\tPL:illumina\tLB:${NAME}" \
    --tmp-dir ${temp_dir} \
    --num-cpu-threads-per-stage 16 \
    --bwa-cpu-thread-pool 16 \
    --gpusort \
    --gpuwrite \
    --knownSites ${Ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf \
    --knownSites ${Ref_dir}/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz \
    --gvcf \
    --out-bam ${parabricks_output}/01_bam_after_marks/${NAME}.germline_dedup.bam \
    --out-duplicate-metrics ${parabricks_output}/02_duplicate_metrics/${NAME}.germline_dedup.bam.metrics.txt \
    --out-recal-file ${parabricks_output}/03_BQSR_report/${NAME}.germline_recal_table.txt \
    --htvc-bam-output ${parabricks_output}/04_haplo_htvc/${NAME}.germline_htvc.bam \
    --out-variants ${output_dir}/01_gvcf/${NAME}.germline.g.vcf

#Light_mode: Deleting unecessary results
rm -rf ${fastp_result}

fi