#!/bin/bash
#SBATCH --array=1-2%2           # Array job
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

source ~/miniforge3/bin/activate
source activate biotools

# Load configuration variables
output_dir=$(jq -r .output_file.path ${config_file})
parabricks_sif=$(jq -r .singularity_containers.parabricks ${config_file})
gatk_sif=$(jq -r .singularity_containers.gatk ${config_file})
Ref_dir=$(jq -r .reference_genome.dir ${config_file})
Ref=$(jq -r .reference_genome.fasta_file ${config_file})
temp_dir=$(jq -r .miscellaneous_files.temp_dir ${config_file})
sample_ids=${output_dir}/sample_ids.txt
mount_dir=$(jq -r .miscellaneous_files.mount_dir ${config_file})
#=====================================================================================================

conda deactivate

NUM=$SLURM_ARRAY_TASK_ID
NAME=$(cat $sample_ids | head -$NUM | tail -1)

# Set up directories
fastp_result=${output_dir}/00_samples/${NAME}/00_fastp_results
haplotype_output=${output_dir}/00_samples/${NAME}/01_haplotype_result
bam_dir=${haplotype_output}/00_bam_files
bam_after_marks=${haplotype_output}/01_bam_after_marks
marksduplicate_metrics=${haplotype_output}/02_marksduplicate_metrics
BQSR_report=${haplotype_output}/03_BQSR_report
bam_after_bqsr_results=${haplotype_output}/04_after_bqsr_results
gvcf_output=${output_dir}/01_gvcf

for dir in ${temp_dir} ${bam_dir} ${bam_after_marks} ${marksduplicate_metrics} \
${BQSR_report} ${bam_after_bqsr_results} ${gvcf_output}
do
    mkdir -p ${dir} 
done

# Run bwa-mem and pipe output to create sorted BAM
bwa mem -t 16 -K 10000000 -R "@RG\tID:${NAME}\tPU:${NAME}\tSM:${NAME}\tPL:illumina\tLB:${NAME}" \
${Ref} ${fastp_result}/${NAME}_R1.fq ${fastp_result}/${NAME}_R2.fq | \
singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
SortSam --MAX_RECORDS_IN_RAM 5000000 -I /dev/stdin \
-O ${bam_dir}/${NAME}.germline.bam --SORT_ORDER coordinate --TMP_DIR ${temp_dir}

# Mark Duplicates
singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
            MarkDuplicates \
            -I ${bam_dir}/${NAME}.germline.bam \
            -O ${bam_after_marks}/${NAME}.germline_dedup.bam \
            -M ${marksduplicate_metrics}/${NAME}.germline_dedup.bam.metrics.txt \
            --TMP_DIR ${temp_dir}

# Generate BQSR Report
singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
            BaseRecalibrator \
            -R ${Ref} \
            -I ${bam_after_marks}/${NAME}.germline_dedup.bam \
            -O ${BQSR_report}/${NAME}.germline_recal.table \
            --known-sites ${Ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf \
            --known-sites ${Ref_dir}/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz 

# Run ApplyBQSR Step
singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
            ApplyBQSR \
            -R ${Ref} \
            -I ${bam_after_marks}/${NAME}.germline_dedup.bam \
            --bqsr-recal-file ${BQSR_report}/${NAME}.germline_recal.table \
            -O ${bam_after_bqsr_results}/${NAME}.germline_dedup_bqsr.bam


#Run Haplotype Caller
singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
            HaplotypeCaller \
            --input ${bam_after_bqsr_results}/${NAME}.germline_dedup_bqsr.bam \
            --output ${gvcf_output}/${NAME}.germline.g.vcf \
            --reference ${Ref} \
            -ERC GVCF \
            --native-pair-hmm-threads 16
