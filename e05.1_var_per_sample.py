import pandas as pd
import os
import sys
import time 
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Clinically significant categories
CLNSIG = ['Likely_pathogenic','Pathogenic/Likely_pathogenic', 'Pathogenic']

def read_csv(path):
    """Read a TXT file"""
    logging.info(f"Reading file: {path}")
    df = pd.read_csv(path, sep="\t")
    logging.info("Reading file: Done")
    return df

def selecting_sample_columns_only(df,sample):
    """Getting the columns and rows relevant to the selected sample"""
    end_col = "Otherinfo12"  # The column that sample names start after
    
    # Identify the indices of start_col and end_col
    end_idx = df.columns.get_loc(end_col)
    sample_idx = df.columns.get_loc(sample)

    # Keep columns from the start column to the end column
    cols_to_keep = df.columns[:end_idx + 1].tolist() + [df.columns[sample_idx]]
    df = df[cols_to_keep]
    return df.rename(columns={sample: 'info'})

def split_otherinfo_column(df, index):
    """Split the 'otherinfo' column to extract specific information."""
    def safe_split(x, index):
    # Split the string by ':' and check if the index exists in the resulting list
        split_values = x.split(':')
        return split_values[index] if len(split_values) > index else None
    return df['info'].apply(lambda x: safe_split(x,index))


def filter_rare_variants(df):
    """Keep rare variants based on allele frequency (AF_nfe)."""
    num_of_var = len(df)
    no_af = df[df['gnomad41_exome_AF_nfe'] == '.']
    with_af = df[df['gnomad41_exome_AF_nfe'] != '.']
    with_af = with_af[with_af['gnomad41_exome_AF_nfe'].astype(float) < 0.01]
    df_filtered = pd.concat([no_af, with_af])
    removed_variants = num_of_var - len(df_filtered)
    return df_filtered, removed_variants

def remove_intronic_and_intergenic(df):
    """Remove intronic and intergenic variants."""
    num_of_var = len(df)
    df_filtered = df[~df['Func.refGene'].isin(['intronic', 'intergenic'])]
    removed_variants = num_of_var - len(df_filtered)
    return df_filtered, removed_variants

def remove_reference_or_unknown_variants(df):
    """Remove rows where genotype (GT) is homozygous reference or unknwon."""
    num_of_var = len(df)
    df_filtered = df[~df["info"].str.startswith(('0/0','0|0','./.', '.|.'))]
    removed_variants = num_of_var - len(df_filtered)
    return df_filtered, removed_variants

def remove_synonymous_variants(df):
    """Remove synonymous variants."""
    num_of_var = len(df)
    df_filtered = df[df['ExonicFunc.refGene'] != 'synonymous SNV']
    removed_variants = num_of_var - len(df_filtered)
    return df_filtered, removed_variants

def filter_pathogenic_variants(df, n_conditions=5):
    """Filter variants based on pathogenicity prediction scores."""
    num_of_var = len(df)
    conditions = [
        (df['SIFT_pred'] == 'D'),
        (df['Polyphen2_HDIV_pred'] == 'D'),
        (df['LRT_pred'].isin(['D'])),
        (df['MutationTaster_pred'].isin(['A', 'D'])),
        (df['FATHMM_pred'] == 'D')
    ]
    pathogenicity_score = sum(cond.astype(int) for cond in conditions)
    df_filtered = df[(pathogenicity_score >= n_conditions) | (df['CLNSIG'].isin(CLNSIG))]
    removed_variants = num_of_var - len(df_filtered)
    return df_filtered, removed_variants
    
def process_sample(annovar_df, output_dir, sample_ids, FILTER_BY_PATHOGENICITY, n_conditions=5):
    """Process a single sample from ANNOVAR output."""
    with open(sample_ids, 'r') as sample_ids:
        for sample in sample_ids:
            sample = sample.strip()
            logging.info(f"Processing sample: {sample}")
            df = selecting_sample_columns_only(annovar_df,sample)
            df['GT']= split_otherinfo_column(df, 0)
            df['AD']= split_otherinfo_column(df, 1)
            df['DP']= split_otherinfo_column(df, 2)
            df['GQ']= split_otherinfo_column(df, 3)

            os.makedirs(f"{output_dir}/{sample}", exist_ok=True)
            result_by_sample_orignal = f"{output_dir}/{sample}/{sample}_original.txt"
            df.insert(0, 'sample', sample)

            # Keeping orginal file
            df.to_csv(result_by_sample_orignal, index=False, sep="\t")
            logging.info(f"A copy before filtration was created for sample {sample}")

            total_var= len(df)
            logging.info(f"Total num of variants = {total_var} ")
            logging.info(f"Commencing variant filtration.")

            df,num_rv1 = filter_rare_variants(df)
            logging.info(f"Removed {num_rv1} variants with AF more than 0.01%")

            df,num_rv2 = remove_intronic_and_intergenic(df)
            logging.info(f"Removed {num_rv2} variants that exist in intronic or intergenic regions")

            df,num_rv3 = remove_reference_or_unknown_variants(df)
            logging.info(f"Removed {num_rv3} variants that are the same as the reference or has unknown genotype ['0/0','0|0','./.', '.|.']")

            df,num_rv4 = remove_synonymous_variants(df)
            logging.info(f"Removed {num_rv4} synonymous variants")
            
            if FILTER_BY_PATHOGENICITY == True:
                df,num_rv5 = filter_pathogenic_variants(df, n_conditions)
                logging.info(f"Filtering variants ...")
                logging.info(f"Removed {num_rv5} variants that are neither pathogenic nor likely pathogenic in ClinVar or did not pass at least 5 pathogenicity scores")
            else:
                logging.info(f"Pipeline filteration by pathogenicity was set to {FILTER_BY_PATHOGENICITY}. Skipping this step ...")

            if len(df) == 0:
                logging.info(f"{sample} had no results after filtering")
            else:
                # Filtered file
                total_af_var= len(df)
                logging.info(f"Total num of variants after filtration = {total_af_var} ")
                result_by_sample_filtered = f"{output_dir}/{sample}/{sample}_filt.txt"
                df.to_csv(result_by_sample_filtered, index=False, sep="\t")
                logging.info(f"Sample {result_by_sample_filtered} filtered variants file was created.")
                logging.info(f"Sample {sample} processing completed.")
                logging.info("=========================================================================================================================================")
    return df


def main(annovar_file, output_dir, sample_ids, FILTER_BY_PATHOGENICITY=True, n_conditions=5, num_processes=2):
    """Main function to process a single ANNOVAR file for multiple samples.
       The script will choose the details for sample selected from the ANNOVAR file and output two files: one 
       file before any filtration + another file after filtration"""
    df = read_csv(annovar_file)
    process_sample(df, output_dir, sample_ids, FILTER_BY_PATHOGENICITY, n_conditions)

if __name__ == "__main__":
    ANNOVAR_ALL_SAMPLES_FILE = sys.argv[1]
    OUTPUT_DIR = sys.argv[2]
    SAMPLE_IDS = sys.argv[3]
    FILTER_BY_PATHOGENICITY = sys.argv[4]
    PATHOGENICITY_CONDITIONS = sys.argv[5]
    main(ANNOVAR_ALL_SAMPLES_FILE, OUTPUT_DIR, SAMPLE_IDS, FILTER_BY_PATHOGENICITY,int(PATHOGENICITY_CONDITIONS))