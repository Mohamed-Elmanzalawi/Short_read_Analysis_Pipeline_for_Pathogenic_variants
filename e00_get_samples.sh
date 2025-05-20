#!/bin/bash
#SBATCH --time=01:00:00             # Time limit (adjust as needed)
#SBATCH --mem=4G                    # Memory allocation (adjust as needed)

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
num_of_samples=$(jq -r .sample_data.num_of_samples ${config_file})
read_1_extension=$(jq -r .sample_data.read_1_extension ${config_file})
read_2_extension=$(jq -r .sample_data.read_2_extension ${config_file})

#======================================Advanced mode settings======================
advanced_mode=$(jq -r .sample_data.advanced_mode ${config_file})
main_fastq_dir=$(jq -r .sample_data.main_dir ${config_file})
sub_fastq_dir=$(jq -r .sample_data.sub_dir ${config_file})
samples_csv=$(jq -r .sample_data.samples_csv_file ${config_file})

#======================================Normal mode settings========================
reads_dir=$(jq -r .sample_data.reads_dir ${config_file})

#=====================================================================================================

mkdir -p ${output_dir}

if [[ ${advanced_mode} != "True" && ${advanced_mode} != "False" ]]; then
echo "Please set advanced mode in the e99.config,json file to either True or False"
echo "Your input \"${advanced_mode}\" is not valid"
exit 1
fi

#======================================Advanced mode===========================
if [[ ${advanced_mode} == "True" ]]; then

echo Using advanced mode for generating sample_ids.txt file.
sub_fastq_dir=$(echo "$sub_fastq_dir" | sed 's/\///g')
mkdir -p "${output_dir}"
awk -v sub_dir="${sub_fastq_dir}" -v num="${num_of_samples}" 'NR>=1 && NR<=num {print $1 "_" sub_dir "_" $3}' ${samples_csv} > ${output_dir}/sample_ids.txt
awk -v sub_dir="${sub_fastq_dir}" -v num="${num_of_samples}" 'NR>=1 && NR<=num {print $1 "_" sub_dir "_" $3 "\t" $4}' ${samples_csv} > ${output_dir}/sample_ids_with_index.txt

while IFS= read -r line; do
NAME=$line
main_sample_dir_name=$(echo $NAME | cut -d _ -f 1)
samples_dir=${main_fastq_dir}/${main_sample_dir_name}/${sub_fastq_dir}

fastq_dir=${output_dir}/00_samples/${NAME}/
mkdir -p ${fastq_dir}

cp -n ${samples_dir}/${NAME}${read_1_extension} ${fastq_dir}

cp -n ${samples_dir}/${NAME}${read_2_extension} ${fastq_dir}
done < ${output_dir}/sample_ids.txt
fi 


#======================================Normal mode==============================

if [[ ${advanced_mode} == "False" ]]; then

echo Using normal mode for generating sample_ids.txt file.

find ${reads_dir} -type f -name *${read_1_extension} | xargs -I {} basename {} ${read_1_extension} > ${output_dir}/sample_ids.txt

while IFS= read -r line; do
NAME=$line

fastq_dir=${output_dir}/00_samples/${NAME}/
mkdir -p ${fastq_dir}

ln -nf ${reads_dir}/${NAME}${read_1_extension} ${fastq_dir}/${NAME}${read_1_extension}

ln -nf ${reads_dir}/${NAME}${read_2_extension} ${fastq_dir}/${NAME}${read_2_extension}

done < ${output_dir}/sample_ids.txt

fi