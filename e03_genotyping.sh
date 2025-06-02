#!/bin/bash
#SBATCH --array=1-24           # Array job
#SBATCH --time=48:00:00        # Time limit (adjust as needed)
#SBATCH --mem=100G             # Memory allocation per task/array job (adjust as needed)
#SBATCH --cpus-per-task=16     # CPUs per task/array job
#SBATCH --export=NONE

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

source ~/miniforge3/etc/profile.d/conda.sh 
source activate biotools

# Load configuration variables
output_dir=$(jq -r .output_file.path ${config_file})
gatk_sif=$(jq -r .singularity_containers.gatk ${config_file})
Ref_dir=$(jq -r .reference_genome.dir ${config_file})
Ref=$(jq -r .reference_genome.fasta_file ${config_file})
temp_dir=$(jq -r .miscellaneous_files.temp_dir ${config_file})
#=====================================================================================================

conda deactivate

# Array of chromosomes
chromosomes=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10"
             "11" "12" "13" "14" "15" "16" "17" "18" "19"
             "20" "21" "22" "X" "Y")

NUM=$SLURM_ARRAY_TASK_ID
CHR=${chromosomes[$NUM-1]}

gvcf=${output_dir}/01_gvcf
combinegvcf_dir=${output_dir}/02_combine_gvcf
genotype_dir=${output_dir}/03_genotyping_gvcf

for dir in ${combinegvcf_dir} ${temp_dir} ${genotype_dir}
do 
mkdir -p ${dir}
done

vcf_inputs=$(ls ${gvcf}/*.g.vcf | awk '{print "--variant "$0}' | tr '\n' ' ')
singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
        CombineGVCFs \
        -R ${Ref} \
        ${vcf_inputs} \
        -D ${Ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf \
        --sequence-dictionary ${Ref_dir}/Homo_sapiens_assembly38.dict \
        --tmp-dir ${temp_dir} \
        -L chr${CHR} \
        -O ${combinegvcf_dir}/chr${CHR}_combined.g.vcf.gz

singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
    GenotypeGVCFs \
	-R ${Ref} \
	-V ${combinegvcf_dir}/chr${CHR}_combined.g.vcf.gz \
	-D ${Ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf  \
	--sequence-dictionary ${Ref_dir}/Homo_sapiens_assembly38.dict \
	--tmp-dir ${temp_dir} \
	-L chr${CHR} \
	-O ${genotype_dir}/chr${CHR}_genotyped.vcf.gz

singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
        SelectVariants \
        -R ${Ref} \
        -V ${genotype_dir}/chr${CHR}_genotyped.vcf.gz \
        --select-type-to-include SNP \
        -O ${genotype_dir}/chr${CHR}_snp.raw.vcf.gz

singularity exec ${gatk_sif} \
gatk --java-options -Xmx16g \
        SelectVariants \
        -R ${Ref} \
        -V ${genotype_dir}/chr${CHR}_genotyped.vcf.gz \
        --select-type-to-include INDEL \
        -O ${genotype_dir}/chr${CHR}_indel.raw.vcf.gz

singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
VariantRecalibrator \
   -R ${Ref} \
   -V ${genotype_dir}/chr${CHR}_snp.raw.vcf.gz \
   --resource:hapmap,known=false,training=true,truth=true,prior=15.0 ${Ref_dir}/hapmap_3.3.hg38.vcf.gz \
   --resource:omni,known=false,training=true,truth=false,prior=12.0 ${Ref_dir}/1000G_omni2.5.hg38.vcf.gz \
   --resource:1000G,known=false,training=true,truth=false,prior=10.0 ${Ref_dir}/1000G_phase1.snps.high_confidence.hg38.vcf.gz \
   --resource:dbsnp,known=true,training=false,truth=false,prior=2.0 ${Ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf \
   -an QD -an MQ -an MQRankSum -an ReadPosRankSum -an FS -an SOR \
   -mode SNP \
   -O ${genotype_dir}/chr${CHR}_snp.recal \
   -L chr${CHR} \
   --tranches-file ${genotype_dir}/chr${CHR}_snp.tranches \
   --sequence-dictionary ${Ref_dir}/Homo_sapiens_assembly38.dict \
   --tmp-dir ${temp_dir} \
   --rscript-file ${genotype_dir}/chr${CHR}_snp.plots.R

singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
ApplyVQSR \
   -R ${Ref} \
   -V ${genotype_dir}/chr${CHR}_snp.raw.vcf.gz \
   -O ${genotype_dir}/chr${CHR}_snp.filt.vcf.gz \
   -L chr${CHR} \
   --truth-sensitivity-filter-level 99.0 \
   --tranches-file ${genotype_dir}/chr${CHR}_snp.tranches \
   --recal-file ${genotype_dir}/chr${CHR}_snp.recal \
   --create-output-variant-index true \
   --sequence-dictionary ${Ref_dir}/Homo_sapiens_assembly38.dict \
   --tmp-dir ${temp_dir} \
   -mode SNP

singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
VariantRecalibrator \
   -R ${Ref} \
   -V ${genotype_dir}/chr${CHR}_indel.raw.vcf.gz \
   --resource:mills,known=false,training=true,truth=true,prior=12 ${Ref_dir}/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz \
   --resource:axiomPoly,known=false,training=true,truth=false,prior=10 ${Ref_dir}/Axiom_Exome_Plus.genotypes.all_populations.poly.hg38.vcf.gz \
   --resource:dbsnp,known=true,training=false,truth=false,prior=2 ${Ref_dir}/Homo_sapiens_assembly38.dbsnp138.vcf \
   -an FS -an ReadPosRankSum -an MQRankSum -an QD -an SOR -an DP \
   -mode INDEL \
   -O ${genotype_dir}/chr${CHR}_indel.recal \
   -L chr${CHR} \
   --tranches-file ${genotype_dir}/chr${CHR}_indel.tranches \
   --sequence-dictionary ${Ref_dir}/Homo_sapiens_assembly38.dict \
   --tmp-dir ${temp_dir} \
   --rscript-file ${genotype_dir}/chr${CHR}_indel.plots.R

singularity exec ${gatk_sif} gatk --java-options -Xmx16g \
ApplyVQSR \
   -R ${Ref} \
   -V ${genotype_dir}/chr${CHR}_indel.raw.vcf.gz \
   -O ${genotype_dir}/chr${CHR}_indel.filt.vcf.gz \
   -L chr${CHR} \
   --truth-sensitivity-filter-level 99.0 \
   --tranches-file ${genotype_dir}/chr${CHR}_indel.tranches \
   --recal-file ${genotype_dir}/chr${CHR}_indel.recal \
   --create-output-variant-index true \
   --sequence-dictionary ${Ref_dir}/Homo_sapiens_assembly38.dict \
   --tmp-dir ${temp_dir} \
   -mode INDEL

singularity exec ${gatk_sif} gatk MergeVcfs \
       --INPUT ${genotype_dir}/chr${CHR}_snp.filt.vcf.gz \
       --INPUT ${genotype_dir}/chr${CHR}_indel.filt.vcf.gz \
       --OUTPUT ${genotype_dir}/chr${CHR}_all.filt.vcf.gz