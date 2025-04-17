# SAPP: Short-read Analysis Pipeline for Pathogenic variants 

A high-performance cluster (HPC) compatible pipeline for short-read sequence analysis for pathogenic variants.
The pipeline was optimised and tested for both Sun Grid Engine and Slurm job scheduling systems.

---

### Content

  - [Installation](#installation)
  - [Pipeline Flowchart](#pipeline-flowchart)
  - [Features](#features)
  - [General Usage](#general-usage)
  - [Details on the output](#details-on-the-output)
  - [Contributors](#contributors)

---

### Installation

#### Source code

1. Cloning the GitHub Repo
```
    git clone https://github.com/Mohamed-Elmanzalawi/Human_Variant_Analysis_Pipeline.git
```
  
2. Download Mamba or Conda  
   Please use the instructions on the official websites:  
   **Conda:** https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html  
   **Mamba:** https://mamba.readthedocs.io/en/latest/installation/mamba-installation.html  
   
4. Create the virtual environment
```
   mamba env create -f environment.yml
```

4. Download the reference genomes from the GATK bundle  
   **Official site:** https://console.cloud.google.com/storage/browser/genomics-public-data/resources/broad/hg38/v0?invt=AbuWvg  
   You can also simply run the script ```01_download_GATK_hg38_v0.sh``` and download all of them in one step using the command below.
```
bash 01_download_GATK_hg38_v0.sh
```
You will find them in the folder named ```00_resources/01_reference38```  
**Note**: The pipeline is compatible with the GATK reference genome since GATK is used in most of the analysis. However, if you want to use another reference genome, be sure to change this in your main config file ```e99_config.json``` and provide the index and dictionary files for that reference genome in the same folder.
  
  5. Download ANNOVAR and its databases  
     **Official site:** https://annovar.openbioinformatics.org/en/latest/user-guide/download/  
     You can also simply run the script ```01_download_annovar.sh``` and download all of them in one step using the command below.   
```
bash 01_download_annovar.sh
```
You will find them in the folder named ```00_resources/02_annovar```  
**Note**: The databases downloaded using the command above might be outdated, so it is advised to check the official website regularly and use the latest databases.

### Pipeline Flowchart 

.. to be updated

### Features

.. to be updated

### General Usage 

.. to be updated

### Details on the output

.. to be updated



