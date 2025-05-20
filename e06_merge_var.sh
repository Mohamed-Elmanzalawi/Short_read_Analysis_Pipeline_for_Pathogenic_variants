#!/bin/bash
#SBATCH --time=48:00:00        # Time limit (adjust as needed)
#SBATCH --mem=100G             # Memory allocation per task/array job (adjust as needed)
#SBATCH --cpus-per-task=10     # CPUs per task/array job

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
# Extension of the filtered vcf files.
extension=*_filt.txt
#=====================================================================================================

~/miniconda3/bin/python e06.1_merge_var.py $output_dir $extension