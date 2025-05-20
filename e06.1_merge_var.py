import pandas as pd
import os
import sys
import glob
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def find_files(base_dir, pattern):
    search_pattern = os.path.join(base_dir, '**', pattern)
    return glob.glob(search_pattern, recursive=True)

def merge_vcfs(output_dir,extension):
    var_per_sample_dir = f"{output_dir}/05_var_per_sample"
    merged = f"{var_per_sample_dir}/merged_vars.txt"

    logging.info(f'Looking for VCF files that end with "{extension}"')
    var_per_sample_files = find_files(var_per_sample_dir, extension)
    logging.info(f'found "{len(var_per_sample_files)}"')

    dataframes = [pd.read_csv(file, sep="\t") for file in var_per_sample_files]
    logging.info("Merging")
    combined_df = pd.concat(dataframes, ignore_index=True)
    combined_df.to_csv(merged, index=False, sep="\t")
    logging.info("Done")

    return logging.info(f"{merged}  file was created.")

if __name__=="__main__":
    OUTPUT_DIR = sys.argv[1]
    EXTENSION = sys.argv[2]
    merge_vcfs(OUTPUT_DIR, EXTENSION)

