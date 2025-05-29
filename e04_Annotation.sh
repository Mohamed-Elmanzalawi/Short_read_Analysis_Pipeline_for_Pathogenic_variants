#!/bin/bash
#SBATCH --time=48:00:00        # Time limit (adjust as needed)
#SBATCH --mem=100G             # Memory allocation per task/array job (adjust as needed)
#SBATCH --cpus-per-task=10     # CPUs per task/array job
#SBATCH --export=NONE

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
        --light_mode)  light_mode=true; shift ;;
        --) shift; break ;;
    esac
done

source ~/miniforge3/etc/profile.d/conda.sh 
source activate biotools

# Load the configuration file
output_dir=$(jq -r .output_file.path ${config_file})
gatk_sif=$(jq -r .singularity_containers.gatk ${config_file})
annovar_dir=$(jq -r .annovar.dir ${config_file})
annovar_db=$(jq -r .annovar.db ${config_file})
annovar_protocol=$(jq -r '.annovar.annotation_protocols | keys_unsorted | join (",") '  ${config_file})
annovar_operation=$(jq -r '.annovar.annotation_protocols | values | join (",") '  ${config_file})
#=====================================================================================================

conda deactivate

genotype_dir=${output_dir}/03_genotyping_gvcf
annotation_dir=${output_dir}/04_annotation
combinegvcf_dir=${output_dir}/02_combine_gvcf

mkdir -p ${annotation_dir}

vcf_inputs=$(ls ${genotype_dir}/*_all.filt.vcf.gz | awk '{print "--INPUT "$0}' | tr '\n' ' ')
singularity exec ${gatk_sif} gatk MergeVcfs \
      ${vcf_inputs} \
      --OUTPUT ${genotype_dir}/chr_merged_all.filt.vcf.gz

singularity exec ${gatk_sif} gatk  SelectVariants \
                                        --exclude-filtered \
                                        -select-genotype "GQ > 10 && DP > 5" \
                                        -V ${genotype_dir}/chr_merged_all.filt.vcf.gz \
                                        -O ${genotype_dir}/analysis-ready.vcf.gz


${annovar_dir}/table_annovar.pl \
   ${genotype_dir}/analysis-ready.vcf.gz \
   ${annovar_db} \
    --buildver hg38 \
    --outfile ${annotation_dir}/analysis-ready \
    --remove \
    --protocol ${annovar_protocol} \
    --operation ${annovar_operation} \
    --argument ",--hgvs --exonicsplicing,,,,,,,,,"\
    --nastring . \
    --vcfinput \
    --polish


col=$(head -1 ${annotation_dir}/analysis-ready.hg38_multianno.txt | tr '\t' '\n' | grep -n -x "^Otherinfo13" | cut -d: -f1)
col=$((col - 1))

samples_name=$(grep "^#CHR" ${annotation_dir}/analysis-ready.hg38_multianno.vcf | cut -f 10-)
# Extract the first old columns of the original header
old_header_prefix=$(head -n 1 ${annotation_dir}/analysis-ready.hg38_multianno.txt | cut -f1-$col)

# Combine the old prefix with the new suffix
new_header=$(printf "%s\t%s" "$old_header_prefix" "$samples_name")

# Create a backup copy
cp ${annotation_dir}/analysis-ready.hg38_multianno.txt ${annotation_dir}/analysis-ready.hg38_multianno_original.txt

# Replace the header in the first file
sed -i "1s/.*/$new_header/" ${annotation_dir}/analysis-ready.hg38_multianno.txt

# #Light_mode: Deleting unecessary results
fastp_result=${output_dir}/00_samples/${NAME}/00_fastp
bam_dir=${preproc_output}/00_bam_files
marksduplicate_metrics=${preproc_output}/02_duplicate_metrics
BQSR_report=${preproc_output}/03_BQSR_report
bam_after_bqsr_results=${preproc_output}/04_after_bqsr

if [[ ${light_mode} == "true" ]]; then
    for dir in ${bam_dir} ${marksduplicate_metrics} ${fastp_result}\
        ${BQSR_report} ${bam_after_bqsr_results} ${genotype_dir} ${combinegvcf_dir}
    do
        rm -rf ${dir} 
    done
fi